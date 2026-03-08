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
        let runID = validatedConfig.id
        activeRunID = runID
        control.reset()

        var record = FineTuneRunRecord(
            id: runID,
            config: validatedConfig,
            status: .queued,
            startedAt: Date(),
            finishedAt: nil,
            lastProgress: nil,
            artifact: nil,
            errorMessage: nil
        )
        try await runStore.upsert(record)

        do {
            let samples = try datasetIngest.loadSamples(from: validatedConfig.datasetURL)
            let dataset = buildTrainingCorpus(from: samples, config: validatedConfig)
            let (trainData, validateData) = splitDataset(dataset)

            let (_, container) = try await modelLoader.loadModel(identifier: validatedConfig.baseModelIdentifier)

            record.status = .running
            try await runStore.upsert(record)

            let adapterDirectory = try await runStore.adapterDirectory(for: runID)
            let weightsURL = adapterDirectory.appendingPathComponent("adapters.safetensors")

            let trainState = FineTuneTrainState(config: validatedConfig)

            try await container.perform { [weak self] context in
                guard let self else { return }

                let languageModel = context.model

                guard let loRAModel = context.model as? LoRAModel else {
                    throw FineTuneOrchestratorError.trainingUnavailable("Loaded model does not expose LoRA layers.")
                }

                let configuredLayers = min(max(1, validatedConfig.loraRank * 2), loRAModel.loraLayers.count)
                let adapterConfig = LoRAConfiguration(
                    numLayers: configuredLayers,
                    fineTuneType: .lora,
                    loraParameters: .init(rank: validatedConfig.loraRank, scale: Float(validatedConfig.scaleFactor * 40.0), keys: nil)
                )

                _ = try LoRAContainer.from(model: languageModel, configuration: adapterConfig)

                let optimizer: Optimizer
                let gaLoreOptimizer: GaLoreProjectedAdam?
                if validatedConfig.method == .galore {
                    let projected = GaLoreProjectedAdam(
                        learningRate: Float(validatedConfig.learningRate),
                        rank: validatedConfig.loraRank,
                        projectionUpdateInterval: validatedConfig.projectionUpdateInterval,
                        scaleFactor: Float(validatedConfig.scaleFactor)
                    )
                    optimizer = projected
                    gaLoreOptimizer = projected
                } else {
                    let adam = Adam(learningRate: Float(validatedConfig.learningRate))
                    optimizer = adam
                    gaLoreOptimizer = nil
                }

                let params = LoRATrain.Parameters(
                    batchSize: validatedConfig.microBatchSize,
                    iterations: validatedConfig.steps,
                    stepsPerReport: 1,
                    stepsPerEval: max(5, validatedConfig.steps / 10),
                    validationBatches: min(10, max(1, validateData.count / max(1, validatedConfig.microBatchSize))),
                    saveEvery: max(25, validatedConfig.steps),
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
                        config: validatedConfig,
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

            let artifact = try await finalizeArtifact(runID: runID, config: validatedConfig)
            record.status = .completed
            record.finishedAt = Date()
            record.lastProgress = trainState.latestProgress()
            record.artifact = artifact
            try await runStore.upsert(record)
            activeRunID = nil
            return artifact

        } catch {
            record.status = (error as? FineTuneOrchestratorError) == .cancelled ? .cancelled : .failed
            record.finishedAt = Date()
            record.errorMessage = error.localizedDescription
            try? await runStore.upsert(record)
            activeRunID = nil
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

    private func buildTrainingCorpus(from samples: [TrainingSample], config: FineTuneJobConfig) -> [String] {
        // Conservative character budget heuristic for device stability.
        // ~4 chars/token is a common rough approximation for English text.
        let maxChars = max(256, config.sequenceLength * 4)
        let promptBudget = max(96, Int(Double(maxChars) * 0.65))
        let completionBudget = max(64, maxChars - promptBudget)

        var rows: [String] = []
        rows.reserveCapacity(samples.count)

        for sample in samples {
            let prompt = truncated(sample.prompt, maxCharacters: promptBudget)
            let completion = truncated(sample.completion, maxCharacters: completionBudget)
            guard !prompt.isEmpty, !completion.isEmpty else { continue }

            rows.append(
                """
                ### Instruction:
                \(prompt)

                ### Response:
                \(completion)
                """
            )
        }

        return rows
    }

    private func splitDataset(_ data: [String]) -> (train: [String], validate: [String]) {
        if data.count < 4 {
            return (data, data)
        }
        let split = max(1, Int(Double(data.count) * 0.9))
        let train = Array(data.prefix(split))
        let validate = Array(data.suffix(max(1, data.count - split)))
        return (train, validate)
    }

    private func truncated(_ text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
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
                ?? (config.method == .galore ? UInt64(Double(defaultBaseline) * max(0.1, min(config.scaleFactor, 1.0))) : defaultBaseline)
            let stepMessage: String
            if let gaLoreStats, config.method == .galore, gaLoreStats.projectionRefreshed {
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
        self.lastOptimizerMemoryBytesValue = config.method == .galore
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
private struct GaLoreSubspace {
    let u: MLXArray
    let vt: MLXArray
    let rows: Int
    let cols: Int
    let rank: Int
}

private struct GaLoreRuntimeStats: Sendable {
    let approximateProjectedOptimizerMemoryBytes: UInt64
    let approximateFullOptimizerMemoryBytes: UInt64
    let projectionRefreshed: Bool
}

private final class GaLoreProjectedAdam: Optimizer {
    private let adam: Adam
    private let rank: Int
    private let projectionUpdateInterval: Int
    private let scaleFactor: Float

    private let lock = NSLock()
    private var step: Int = 0
    private var cachedSubspaces: [String: GaLoreSubspace] = [:]
    private var stats = GaLoreRuntimeStats(
        approximateProjectedOptimizerMemoryBytes: 0,
        approximateFullOptimizerMemoryBytes: 0,
        projectionRefreshed: false
    )

    init(learningRate: Float, rank: Int, projectionUpdateInterval: Int, scaleFactor: Float) {
        self.adam = Adam(learningRate: learningRate)
        self.rank = max(1, rank)
        self.projectionUpdateInterval = max(1, projectionUpdateInterval)
        self.scaleFactor = max(0.0001, min(scaleFactor, 1.0))
    }

    func innerState() -> [MLXArray] {
        adam.innerState()
    }

    func runtimeStats() -> GaLoreRuntimeStats {
        lock.lock()
        let value = stats
        lock.unlock()
        return value
    }

    func update(model: Module, gradients: ModuleParameters) {
        lock.lock()
        step += 1
        let currentStep = step
        let refreshProjection = currentStep == 1 || (currentStep - 1) % projectionUpdateInterval == 0
        lock.unlock()

        var fullOptimizerElements = 0
        var projectedOptimizerElements = 0

        let projectedGradients = gradients.mapValues { key, gradient in
            let g = gradient.asType(.float32)
            fullOptimizerElements += max(1, g.size)

            guard g.shape.count >= 2 else {
                projectedOptimizerElements += max(1, min(rank, g.size))
                return g * scaleFactor
            }

            let rows = max(1, g.dim(0))
            let cols = max(1, g.size / rows)
            let matrix = g.reshaped(rows, cols)
            let subspace = self.subspace(
                for: key,
                matrix: matrix,
                rows: rows,
                cols: cols,
                refresh: refreshProjection
            )

            projectedOptimizerElements += max(1, subspace.rank * (subspace.rows + subspace.cols))

            let projected = self.project(matrix: matrix, subspace: subspace)
            return projected.reshaped(g.shape) * scaleFactor
        }

        adam.update(model: model, gradients: projectedGradients)
        eval(adam)

        let fullBytes = UInt64(max(1, fullOptimizerElements) * MemoryLayout<Float>.size * 2)
        let projectedBytes = UInt64(max(1, projectedOptimizerElements) * MemoryLayout<Float>.size * 2)

        lock.lock()
        stats = GaLoreRuntimeStats(
            approximateProjectedOptimizerMemoryBytes: projectedBytes,
            approximateFullOptimizerMemoryBytes: fullBytes,
            projectionRefreshed: refreshProjection
        )
        lock.unlock()
    }

    private func subspace(
        for key: String,
        matrix: MLXArray,
        rows: Int,
        cols: Int,
        refresh: Bool
    ) -> GaLoreSubspace {
        lock.lock()
        if !refresh, let cached = cachedSubspaces[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let k = max(1, min(rank, min(rows, cols)))
        let (u, _, vt) = svd(matrix)
        let uK = u[0..., 0..<k]
        let vtK = vt[0..<k, 0...]
        let subspace = GaLoreSubspace(u: uK, vt: vtK, rows: rows, cols: cols, rank: k)

        lock.lock()
        cachedSubspaces[key] = subspace
        lock.unlock()

        return subspace
    }

    private func project(matrix: MLXArray, subspace: GaLoreSubspace) -> MLXArray {
        let uT = subspace.u.transposed()
        let v = subspace.vt.transposed()
        let inner = matmul(uT, matmul(matrix, v))
        return matmul(subspace.u, matmul(inner, subspace.vt))
    }
}
#endif
