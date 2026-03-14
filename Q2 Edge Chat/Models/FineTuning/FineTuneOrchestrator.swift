import Foundation
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXNN)
import MLXNN
#endif
#if canImport(MLXOptimizers)
import MLXOptimizers
#endif

actor FineTuneOrchestrator {
    private let modelLoader = MLXModelLoaderService()
    private let datasetIngest = DatasetIngestService()
    private let guardrails = TrainingGuardrailService()
    private let runStore: FineTuneRunStore

    private var activeRunID: UUID?
    private let control = FineTuneControl()

    init(runStore: FineTuneRunStore) {
        self.runStore = runStore
    }

    func start(config: FineTuneJobConfig, progress: @escaping @Sendable (FineTuneProgress) -> Void) async throws -> FineTuneArtifact {
        if activeRunID != nil {
            throw FineTuneOrchestratorError.alreadyRunning
        }

        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXOptimizers)
        let validatedConfig = try config.validated()
        if let modelBillions = validatedConfig.estimatedModelBillions(),
           modelBillions > FineTuneMemoryPolicy.maxSupportedModelBillions {
            let limit = String(format: "%.1fB", FineTuneMemoryPolicy.maxSupportedModelBillions)
            throw FineTuneOrchestratorError.trainingUnavailable("Model appears to be \(modelBillions)B. Under the 2.2GB iPhone safety profile, use a model at or below \(limit).")
        }

        let safety = validatedConfig.applyingMemorySafetyPolicy()
        let effectiveConfig = safety.config
        let runID = effectiveConfig.id
        activeRunID = runID
        control.reset()
        defer { releaseTrainingResources() }

        var record = FineTuneRunRecord(
            id: runID,
            config: effectiveConfig,
            status: .queued,
            startedAt: Date(),
            finishedAt: nil,
            lastProgress: nil,
            artifact: nil,
            errorMessage: nil
        )
        try await runStore.upsert(record)

        if !safety.notes.isEmpty {
            let message = "Applied iPhone memory safety profile: \(safety.notes.joined(separator: " "))"
            let snapshot = guardrails.snapshot()
            progress(
                FineTuneProgress(
                    runID: runID,
                    step: 0,
                    totalSteps: effectiveConfig.steps,
                    loss: 0,
                    tokensPerSecond: 0,
                    estimatedPeakMemoryBytes: snapshot.residentMemoryBytes,
                    optimizerMemoryBytes: 0,
                    baselineOptimizerMemoryBytes: 0,
                    thermalState: snapshot.thermalState,
                    status: .queued,
                    message: message,
                    method: effectiveConfig.method,
                    timestamp: Date()
                )
            )
        }

        if effectiveConfig.method == .galore {
            let snapshot = guardrails.snapshot()
            progress(
                FineTuneProgress(
                    runID: runID,
                    step: 0,
                    totalSteps: effectiveConfig.steps,
                    loss: 0,
                    tokensPerSecond: 0,
                    estimatedPeakMemoryBytes: snapshot.residentMemoryBytes,
                    optimizerMemoryBytes: 0,
                    baselineOptimizerMemoryBytes: 0,
                    thermalState: snapshot.thermalState,
                    status: .queued,
                    message: "Experimental GaLore mode only projects adapter gradients in this app. Use QLoRA or DoRA for production on iPhone.",
                    method: effectiveConfig.method,
                    timestamp: Date()
                )
            )
        }

        do {
            let corpus = try datasetIngest.loadTrainingCorpus(from: effectiveConfig.datasetURL, config: effectiveConfig)
            let trainData = corpus.train
            let validateData = corpus.validate

            let (_, container) = try await modelLoader.loadModel(identifier: effectiveConfig.baseModelIdentifier)

            record.status = .running
            try await runStore.upsert(record)

            let adapterDirectory = try await runStore.adapterDirectory(for: runID)
            let weightsURL = adapterDirectory.appendingPathComponent("adapters.safetensors")

            let trainState = FineTuneTrainState(config: effectiveConfig)

            try await container.perform { [weak self] context in
                guard let self else { return }

                let languageModel = context.model

                guard let loRAModel = context.model as? LoRAModel else {
                    throw FineTuneOrchestratorError.trainingUnavailable("Loaded model does not expose LoRA layers.")
                }

                let configuredLayers = min(max(1, effectiveConfig.loraRank * 2), loRAModel.loraLayers.count)
                let fineTuneType: LoRAConfiguration.FineTuneType
                switch effectiveConfig.method {
                case .dora:
                    fineTuneType = .dora
                case .lora, .qlora, .galore:
                    fineTuneType = .lora
                }
                let adapterConfig = LoRAConfiguration(
                    numLayers: configuredLayers,
                    fineTuneType: fineTuneType,
                    loraParameters: .init(rank: effectiveConfig.loraRank, scale: Float(effectiveConfig.scaleFactor * 40.0), keys: nil)
                )

                _ = try LoRAContainer.from(model: languageModel, configuration: adapterConfig)

                let optimizer: Optimizer
                let gaLoreOptimizer: GaLoreProjectedAdam?
                if effectiveConfig.method.usesProjectedOptimizerResearchPath {
                    let projected = GaLoreProjectedAdam(
                        learningRate: Float(effectiveConfig.learningRate),
                        rank: effectiveConfig.loraRank,
                        projectionUpdateInterval: effectiveConfig.projectionUpdateInterval,
                        scaleFactor: Float(effectiveConfig.scaleFactor)
                    )
                    optimizer = projected
                    gaLoreOptimizer = projected
                } else {
                    let adam = Adam(learningRate: Float(effectiveConfig.learningRate))
                    optimizer = adam
                    gaLoreOptimizer = nil
                }

                let params = LoRATrain.Parameters(
                    batchSize: effectiveConfig.microBatchSize,
                    iterations: effectiveConfig.steps,
                    stepsPerReport: 1,
                    stepsPerEval: max(10, effectiveConfig.steps / 8),
                    validationBatches: min(2, max(1, validateData.count / max(1, effectiveConfig.microBatchSize))),
                    saveEvery: max(25, effectiveConfig.steps),
                    adapterURL: weightsURL
                )

                try LoRATrain.train(
                    model: languageModel,
                    train: trainData,
                    validate: validateData,
                    optimizer: optimizer,
                    tokenizer: context.tokenizer,
                    parameters: params
                ) { loRAProgress in
                    let snapshot = self.guardrails.snapshot()
                    if self.control.isStopRequested {
                        self.control.markStoppedByUser()
                        return .stop
                    }

                    let decision = self.guardrails.evaluate(snapshot: snapshot)
                    if case .stop(let reason) = decision {
                        self.control.markGuardrailStop(reason)
                        return .stop
                    }

                    let mapped = FineTuneOrchestrator.mapProgress(
                        loRAProgress,
                        runID: runID,
                        config: effectiveConfig,
                        snapshot: snapshot,
                        state: trainState,
                        gaLoreStats: gaLoreOptimizer?.runtimeStats(),
                        messageOverride: {
                            if case .pause(let reason) = decision { return reason }
                            return nil
                        }()
                    )

                    trainState.record(progress: mapped)
                    progress(mapped)
                    return .more
                }

                if !FileManager.default.fileExists(atPath: weightsURL.path) {
                    try LoRATrain.saveLoRAWeights(model: languageModel, url: weightsURL)
                }

                let configData = try JSONEncoder().encode(adapterConfig)
                try configData.write(to: adapterDirectory.appendingPathComponent("adapter_config.json"), options: .atomic)
            }

            if let guardrailReason = control.guardrailReason {
                throw FineTuneOrchestratorError.guardrailStopped(guardrailReason)
            }
            if control.wasStoppedByUser {
                throw FineTuneOrchestratorError.cancelled
            }

            let artifact = try await finalizeArtifact(runID: runID, config: effectiveConfig)
            record.status = .completed
            record.finishedAt = Date()
            record.lastProgress = trainState.latestProgress()
            record.artifact = artifact
            record.config = effectiveConfig
            try await runStore.upsert(record)
            return artifact

        } catch {
            record.status = (error as? FineTuneOrchestratorError) == .cancelled ? .cancelled : .failed
            record.finishedAt = Date()
            record.errorMessage = error.localizedDescription
            try? await runStore.upsert(record)
            throw error
        }
        #else
        throw FineTuneOrchestratorError.trainingUnavailable("MLX training dependencies are not available in this build.")
        #endif
    }

    func stop() {
        control.requestStop()
    }

    func runs() async -> [FineTuneRunRecord] {
        await runStore.allRuns()
    }

    private func releaseTrainingResources() {
        activeRunID = nil
        control.reset()
        #if canImport(MLX)
        MLX.Memory.clearCache()
        #endif
    }

    private func finalizeArtifact(runID: UUID, config: FineTuneJobConfig) async throws -> FineTuneArtifact {
        let dir = try await runStore.adapterDirectory(for: runID)
        let adapterURL = dir.appendingPathComponent("adapters.safetensors")
        let metadataURL = dir.appendingPathComponent("metadata.json")

        let metadata: [String: Any] = [
            "run_id": runID.uuidString,
            "base_model": config.baseModelIdentifier,
            "method": config.method.rawValue,
            "rank": config.loraRank,
            "projection_update_interval": config.projectionUpdateInterval,
            "scale_factor": config.scaleFactor,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)

        return FineTuneArtifact(
            id: UUID(),
            runID: runID,
            config: config,
            baseModelIdentifier: config.baseModelIdentifier,
            adapterURL: adapterURL,
            metadataURL: metadataURL,
            createdAt: Date()
        )
    }

    nonisolated private static func mapProgress(
        _ progress: LoRATrain.Progress,
        runID: UUID,
        config: FineTuneJobConfig,
        snapshot: GuardrailSnapshot,
        state: FineTuneTrainState,
        gaLoreStats: GaLoreRuntimeStats?,
        messageOverride: String?
    ) -> FineTuneProgress {
        let now = Date()
        let fallbackBaseline = UInt64(max(1, config.sequenceLength * config.loraRank * MemoryLayout<Double>.size * 2))

        switch progress {
        case .train(let iteration, let trainingLoss, _, let tokensPerSecond):
            let step = iteration + 1
            let defaultBaseline = max(fallbackBaseline, UInt64(config.sequenceLength * 16 * MemoryLayout<Double>.size * 2))
            let baseline = gaLoreStats?.approximateFullOptimizerMemoryBytes ?? defaultBaseline
            let optimizerMemory = gaLoreStats?.approximateProjectedOptimizerMemoryBytes
                ?? (config.method.usesProjectedOptimizerResearchPath ? UInt64(Double(defaultBaseline) * max(0.1, min(config.scaleFactor, 1.0))) : defaultBaseline)
            let stepMessage: String
            if let gaLoreStats, config.method.usesProjectedOptimizerResearchPath, gaLoreStats.svdFallbackCount > 0 {
                stepMessage = messageOverride ?? "Training step \(step) (projection fallback on \(gaLoreStats.svdFallbackCount) tensor(s))"
            } else if let gaLoreStats, config.method.usesProjectedOptimizerResearchPath, gaLoreStats.projectionRefreshed {
                stepMessage = messageOverride ?? "Training step \(step) (projection refresh)"
            } else {
                stepMessage = messageOverride ?? "Training step \(step)"
            }

            state.update(
                step: step,
                loss: Double(trainingLoss),
                tokensPerSecond: tokensPerSecond,
                optimizerMemoryBytes: optimizerMemory,
                baselineOptimizerMemoryBytes: baseline
            )

            return FineTuneProgress(
                runID: runID,
                step: step,
                totalSteps: config.steps,
                loss: Double(trainingLoss),
                tokensPerSecond: tokensPerSecond,
                estimatedPeakMemoryBytes: max(snapshot.residentMemoryBytes, optimizerMemory),
                optimizerMemoryBytes: optimizerMemory,
                baselineOptimizerMemoryBytes: baseline,
                thermalState: snapshot.thermalState,
                status: .running,
                message: stepMessage,
                method: config.method,
                timestamp: now
            )
        case .validation(let iteration, let validationLoss, _):
            let step = min(config.steps, iteration + 1)
            return FineTuneProgress(
                runID: runID,
                step: step,
                totalSteps: config.steps,
                loss: Double(validationLoss),
                tokensPerSecond: max(0, state.lastTokensPerSecond),
                estimatedPeakMemoryBytes: snapshot.residentMemoryBytes,
                optimizerMemoryBytes: state.lastOptimizerMemoryBytes,
                baselineOptimizerMemoryBytes: state.lastBaselineOptimizerMemoryBytes,
                thermalState: snapshot.thermalState,
                status: .running,
                message: messageOverride ?? "Validation checkpoint at step \(step)",
                method: config.method,
                timestamp: now
            )
        case .save(let iteration, let url):
            let step = min(config.steps, iteration + 1)
            return FineTuneProgress(
                runID: runID,
                step: step,
                totalSteps: config.steps,
                loss: state.lastLoss,
                tokensPerSecond: max(0, state.lastTokensPerSecond),
                estimatedPeakMemoryBytes: snapshot.residentMemoryBytes,
                optimizerMemoryBytes: state.lastOptimizerMemoryBytes,
                baselineOptimizerMemoryBytes: state.lastBaselineOptimizerMemoryBytes,
                thermalState: snapshot.thermalState,
                status: .running,
                message: messageOverride ?? "Saved adapter checkpoint to \(url.lastPathComponent)",
                method: config.method,
                timestamp: now
            )
        }
    }
}

private final class FineTuneControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopRequested = false
    private var stoppedByUser = false
    private var guardrailStop: String?

    func reset() {
        lock.lock()
        stopRequested = false
        stoppedByUser = false
        guardrailStop = nil
        lock.unlock()
    }

    func requestStop() {
        lock.lock()
        stopRequested = true
        lock.unlock()
    }

    func markStoppedByUser() {
        lock.lock()
        stoppedByUser = true
        lock.unlock()
    }

    func markGuardrailStop(_ reason: String) {
        lock.lock()
        stopRequested = true
        guardrailStop = reason
        lock.unlock()
    }

    var isStopRequested: Bool {
        lock.lock()
        let value = stopRequested
        lock.unlock()
        return value
    }

    var wasStoppedByUser: Bool {
        lock.lock()
        let value = stoppedByUser
        lock.unlock()
        return value
    }

    var guardrailReason: String? {
        lock.lock()
        let value = guardrailStop
        lock.unlock()
        return value
    }
}

private final class FineTuneTrainState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastLossValue: Double = 0
    private var lastTokensPerSecondValue: Double = 0
    private var lastOptimizerMemoryBytesValue: UInt64
    private var lastBaselineOptimizerMemoryBytesValue: UInt64
    private var lastProgressValue: FineTuneProgress?

    init(config: FineTuneJobConfig) {
        let baseline = UInt64(max(1, config.sequenceLength * 16 * MemoryLayout<Double>.size * 2))
        self.lastBaselineOptimizerMemoryBytesValue = baseline
        self.lastOptimizerMemoryBytesValue = config.method.usesProjectedOptimizerResearchPath
            ? UInt64(Double(baseline) * max(0.1, min(config.scaleFactor, 1.0)))
            : baseline
    }

    func update(
        step: Int,
        loss: Double,
        tokensPerSecond: Double,
        optimizerMemoryBytes: UInt64,
        baselineOptimizerMemoryBytes: UInt64
    ) {
        lock.lock()
        lastLossValue = loss
        lastTokensPerSecondValue = tokensPerSecond
        lastOptimizerMemoryBytesValue = optimizerMemoryBytes
        lastBaselineOptimizerMemoryBytesValue = baselineOptimizerMemoryBytes
        lock.unlock()
    }

    func record(progress: FineTuneProgress) {
        lock.lock()
        lastProgressValue = progress
        lock.unlock()
    }

    func latestProgress() -> FineTuneProgress? {
        lock.lock()
        let value = lastProgressValue
        lock.unlock()
        return value
    }

    var lastLoss: Double {
        lock.lock()
        let value = lastLossValue
        lock.unlock()
        return value
    }

    var lastTokensPerSecond: Double {
        lock.lock()
        let value = lastTokensPerSecondValue
        lock.unlock()
        return value
    }

    var lastOptimizerMemoryBytes: UInt64 {
        lock.lock()
        let value = lastOptimizerMemoryBytesValue
        lock.unlock()
        return value
    }

    var lastBaselineOptimizerMemoryBytes: UInt64 {
        lock.lock()
        let value = lastBaselineOptimizerMemoryBytesValue
        lock.unlock()
        return value
    }
}

enum FineTuneOrchestratorError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case cancelled
    case guardrailStopped(String)
    case trainingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A fine-tuning job is already running."
        case .cancelled:
            return "Fine-tuning was cancelled."
        case .guardrailStopped(let reason):
            return reason
        case .trainingUnavailable(let reason):
            return reason
        }
    }
}

#if canImport(MLX) && canImport(MLXNN) && canImport(MLXOptimizers)
private struct GaLoreRuntimeStats: Sendable {
    let approximateProjectedOptimizerMemoryBytes: UInt64
    let approximateFullOptimizerMemoryBytes: UInt64
    let projectionRefreshed: Bool
    let svdFallbackCount: Int
}

private final class GaLoreProjectedAdam: Optimizer {
    private enum ProjectionMode {
        case full
        case left
        case right
    }

    private struct ParameterState {
        var step: Int
        var mode: ProjectionMode
        var rows: Int
        var cols: Int
        var rank: Int
        var basis: MLXArray?
        var m: MLXArray
        var v: MLXArray
    }

    private let rank: Int
    private let projectionUpdateInterval: Int
    private let scaleFactor: Float
    private let learningRate: Float
    private let betas: (Float, Float)
    private let eps: Float
    private let svdProvider: @Sendable (MLXArray) throws -> (MLXArray, MLXArray, MLXArray)

    private let lock = NSLock()
    private var states: [String: ParameterState] = [:]
    private var stats = GaLoreRuntimeStats(
        approximateProjectedOptimizerMemoryBytes: 0,
        approximateFullOptimizerMemoryBytes: 0,
        projectionRefreshed: false,
        svdFallbackCount: 0
    )

    init(
        learningRate: Float,
        rank: Int,
        projectionUpdateInterval: Int,
        scaleFactor: Float,
        betas: (Float, Float) = (0.9, 0.999),
        eps: Float = 1e-8,
        svdProvider: @escaping @Sendable (MLXArray) throws -> (MLXArray, MLXArray, MLXArray) = { matrix in
            svd(matrix, stream: .cpu)
        }
    ) {
        self.learningRate = learningRate
        self.rank = max(1, rank)
        self.projectionUpdateInterval = max(1, projectionUpdateInterval)
        self.scaleFactor = max(0.0001, min(scaleFactor, 1.0))
        self.betas = betas
        self.eps = max(eps, 1e-12)
        self.svdProvider = svdProvider
    }

    func innerState() -> [MLXArray] {
        lock.lock()
        let arrays = states.values.flatMap { state -> [MLXArray] in
            if let basis = state.basis {
                return [state.m, state.v, basis]
            }
            return [state.m, state.v]
        }
        lock.unlock()
        return arrays
    }

    func runtimeStats() -> GaLoreRuntimeStats {
        lock.lock()
        let value = stats
        lock.unlock()
        return value
    }

    func update(model: Module, gradients: ModuleParameters) {
        let gradientPairs = gradients.flattened()
        guard !gradientPairs.isEmpty else { return }

        let modelParameters = model.parameters()
        let modelParameterMap = Dictionary(uniqueKeysWithValues: modelParameters.flattened())

        let (b1, b2) = betas

        lock.lock()

        var updatedParameters: [(String, MLXArray)] = []
        updatedParameters.reserveCapacity(gradientPairs.count)

        var fullOptimizerElements = 0
        var projectedOptimizerElements = 0
        var projectionRefreshed = false
        var svdFallbackCount = 0

        for (key, gradientRaw) in gradientPairs {
            guard let parameter = modelParameterMap[key] else { continue }

            let g = gradientRaw.asType(.float32)
            let parameter32 = parameter.asType(.float32)
            fullOptimizerElements += max(1, g.size)

            let shape = g.shape
            let hasMatrixShape = shape.count >= 2
            let rows = hasMatrixShape ? max(1, g.dim(0)) : max(1, g.size)
            let cols = hasMatrixShape ? max(1, g.size / rows) : 1

            if !hasMatrixShape {
                var state = states[key] ?? ParameterState(
                    step: 0,
                    mode: .full,
                    rows: rows,
                    cols: cols,
                    rank: 0,
                    basis: nil,
                    m: MLXArray.zeros(like: g),
                    v: MLXArray.zeros(like: g)
                )

                if state.mode != .full || state.m.shape != g.shape {
                    state = ParameterState(
                        step: 0,
                        mode: .full,
                        rows: rows,
                        cols: cols,
                        rank: 0,
                        basis: nil,
                        m: MLXArray.zeros(like: g),
                        v: MLXArray.zeros(like: g)
                    )
                }

                state.step += 1
                state.m = b1 * state.m + (1 - b1) * g
                state.v = b2 * state.v + (1 - b2) * square(g)

                let update = state.m / (sqrt(state.v) + eps)
                let nextParam = (parameter32 - (learningRate * scaleFactor) * update).asType(parameter.dtype)

                states[key] = state
                projectedOptimizerElements += max(1, state.m.size + state.v.size)
                updatedParameters.append((key, nextParam))
                continue
            }

            let matrix = g.reshaped(rows, cols)
            let r = max(1, min(rank, min(rows, cols)))
            let mode: ProjectionMode = rows <= cols ? .right : .left

            var state = states[key] ?? ParameterState(
                step: 0,
                mode: mode,
                rows: rows,
                cols: cols,
                rank: r,
                basis: nil,
                m: MLXArray(0),
                v: MLXArray(0)
            )

            let stateMismatch = state.mode != mode || state.rows != rows || state.cols != cols || state.rank != r
            if stateMismatch {
                let projectedShape: [Int]
                switch mode {
                case .right:
                    projectedShape = [rows, r]
                case .left:
                    projectedShape = [r, cols]
                case .full:
                    projectedShape = g.shape
                }
                state = ParameterState(
                    step: 0,
                    mode: mode,
                    rows: rows,
                    cols: cols,
                    rank: r,
                    basis: nil,
                    m: MLXArray.zeros(projectedShape, dtype: .float32),
                    v: MLXArray.zeros(projectedShape, dtype: .float32)
                )
            }

            state.step += 1
            let needsRefresh = state.basis == nil || state.step == 1 || (state.step - 1) % projectionUpdateInterval == 0
            var useFullFallbackForStep = false
            if needsRefresh {
                // MLX does not currently support GPU SVD; compute on CPU.
                do {
                    let (u, _, vt) = try svdProvider(matrix)
                    switch mode {
                    case .right:
                        state.basis = vt[0..<r, 0...].transposed().asType(.float32, stream: .gpu)  // [cols, r]
                    case .left:
                        state.basis = u[0..., 0..<r].asType(.float32, stream: .gpu)  // [rows, r]
                    case .full:
                        state.basis = nil
                    }
                    projectionRefreshed = true
                } catch {
                    // Keep training alive: skip refresh and use a full-space update for this tensor this step.
                    state.basis = nil
                    useFullFallbackForStep = true
                    svdFallbackCount += 1
                }
            }

            if useFullFallbackForStep {
                if state.m.shape != matrix.shape || state.v.shape != matrix.shape {
                    state.m = MLXArray.zeros([rows, cols], dtype: .float32)
                    state.v = MLXArray.zeros([rows, cols], dtype: .float32)
                }
                state.m = b1 * state.m + (1 - b1) * matrix
                state.v = b2 * state.v + (1 - b2) * square(matrix)

                let fullUpdate = state.m / (sqrt(state.v) + eps)
                let nextMatrix = parameter32.reshaped(rows, cols) - (learningRate * scaleFactor) * fullUpdate
                let nextParam = nextMatrix.reshaped(parameter.shape).asType(parameter.dtype)

                states[key] = state
                projectedOptimizerElements += max(1, state.m.size + state.v.size)
                updatedParameters.append((key, nextParam))
                continue
            }

            guard let basis = state.basis else {
                // No projection basis available yet; use full Adam-style update.
                if state.m.shape != matrix.shape || state.v.shape != matrix.shape {
                    state.m = MLXArray.zeros([rows, cols], dtype: .float32)
                    state.v = MLXArray.zeros([rows, cols], dtype: .float32)
                }
                state.m = b1 * state.m + (1 - b1) * matrix
                state.v = b2 * state.v + (1 - b2) * square(matrix)

                let fullUpdate = state.m / (sqrt(state.v) + eps)
                let nextMatrix = parameter32.reshaped(rows, cols) - (learningRate * scaleFactor) * fullUpdate
                let nextParam = nextMatrix.reshaped(parameter.shape).asType(parameter.dtype)
                states[key] = state
                projectedOptimizerElements += max(1, state.m.size + state.v.size)
                updatedParameters.append((key, nextParam))
                continue
            }

            let projectedGradient: MLXArray
            let projectedUpdate: MLXArray
            let fullUpdate: MLXArray

            switch mode {
            case .right:
                projectedGradient = matmul(matrix, basis)  // [rows, r]
                state.m = b1 * state.m + (1 - b1) * projectedGradient
                state.v = b2 * state.v + (1 - b2) * square(projectedGradient)
                projectedUpdate = state.m / (sqrt(state.v) + eps)
                fullUpdate = matmul(projectedUpdate, basis.transposed())  // [rows, cols]
            case .left:
                projectedGradient = matmul(basis.transposed(), matrix)  // [r, cols]
                state.m = b1 * state.m + (1 - b1) * projectedGradient
                state.v = b2 * state.v + (1 - b2) * square(projectedGradient)
                projectedUpdate = state.m / (sqrt(state.v) + eps)
                fullUpdate = matmul(basis, projectedUpdate)  // [rows, cols]
            case .full:
                projectedGradient = matrix
                projectedUpdate = matrix
                fullUpdate = matrix
            }

            let nextMatrix = parameter32.reshaped(rows, cols) - (learningRate * scaleFactor) * fullUpdate
            let nextParam = nextMatrix.reshaped(parameter.shape).asType(parameter.dtype)

            states[key] = state
            projectedOptimizerElements += max(1, state.m.size + state.v.size + basis.size)
            updatedParameters.append((key, nextParam))
        }

        lock.unlock()

        let fullBytes = UInt64(max(1, fullOptimizerElements) * MemoryLayout<Float>.size * 2)
        let projectedBytes = UInt64(max(1, projectedOptimizerElements) * MemoryLayout<Float>.size)

        lock.lock()
        stats = GaLoreRuntimeStats(
            approximateProjectedOptimizerMemoryBytes: projectedBytes,
            approximateFullOptimizerMemoryBytes: fullBytes,
            projectionRefreshed: projectionRefreshed,
            svdFallbackCount: svdFallbackCount
        )
        lock.unlock()

        if !updatedParameters.isEmpty {
            model.update(parameters: ModuleParameters.unflattened(updatedParameters))
            eval(model)
        }
    }
}
#endif
