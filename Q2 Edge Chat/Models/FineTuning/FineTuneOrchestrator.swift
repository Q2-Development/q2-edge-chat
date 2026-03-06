import Foundation

actor FineTuneOrchestrator {
    private let modelLoader = MLXModelLoaderService()
    private let datasetIngest = DatasetIngestService()
    private let guardrails = TrainingGuardrailService()
    private let runStore: FineTuneRunStore

    private var activeRunID: UUID?
    private var stopRequested = false

    init(runStore: FineTuneRunStore) {
        self.runStore = runStore
    }

    func start(config: FineTuneJobConfig, progress: @escaping @Sendable (FineTuneProgress) -> Void) async throws -> FineTuneArtifact {
        if activeRunID != nil {
            throw FineTuneOrchestratorError.alreadyRunning
        }

        let validatedConfig = try config.validated()
        let runID = validatedConfig.id
        activeRunID = runID
        stopRequested = false

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
            _ = try await modelLoader.loadModelDescriptor(identifier: validatedConfig.baseModelIdentifier)
            let samples = try datasetIngest.loadSamples(from: validatedConfig.datasetURL)

            record.status = .running
            try await runStore.upsert(record)

            var lastLoss = 2.0
            var peakMemory: UInt64 = 0
            let startTime = Date()
            let vectorLength = max(64, validatedConfig.sequenceLength * 4)
            var galoreBridge = GaLoreOptimizerBridge(
                rank: validatedConfig.loraRank,
                vectorLength: vectorLength,
                projectionUpdateInterval: validatedConfig.projectionUpdateInterval,
                scaleFactor: validatedConfig.scaleFactor,
                learningRate: validatedConfig.learningRate
            )

            for step in 1...validatedConfig.steps {
                if stopRequested {
                    throw FineTuneOrchestratorError.cancelled
                }
                try Task.checkCancellation()

                let guardrailSnapshot = guardrails.snapshot()
                let decision = guardrails.evaluate(snapshot: guardrailSnapshot)
                switch decision {
                case .allow:
                    break
                case .pause(let reason):
                    try await sleep(milliseconds: 900)
                    if step % 8 == 0 {
                        await emitProgress(
                            runID: runID,
                            step: step,
                            totalSteps: validatedConfig.steps,
                            method: validatedConfig.method,
                            loss: lastLoss,
                            startTime: startTime,
                            estimatedPeakMemoryBytes: peakMemory,
                            optimizerMemoryBytes: UInt64(vectorLength * MemoryLayout<Double>.size * 2),
                            baselineOptimizerMemoryBytes: UInt64(vectorLength * MemoryLayout<Double>.size * 2),
                            thermalState: guardrailSnapshot.thermalState,
                            status: .paused,
                            message: reason,
                            progress: progress,
                            record: &record
                        )
                    }
                    continue
                case .stop(let reason):
                    throw FineTuneOrchestratorError.guardrailStopped(reason)
                }

                let sample = samples[step % samples.count]
                let tokenEstimate = max(1, (sample.prompt.count + sample.completion.count) / 4)
                let gradient = syntheticGradient(size: vectorLength, step: step)

                var optimizerMemory: UInt64 = UInt64(vectorLength * MemoryLayout<Double>.size * 2)
                let baselineOptimizerMemory: UInt64 = optimizerMemory
                if validatedConfig.method == .galore {
                    let projection = galoreBridge.step(gradient: gradient, globalStep: step)
                    optimizerMemory = projection.approximateOptimizerMemoryBytes
                }

                let syntheticNoise = Double.random(in: -0.003...0.003)
                lastLoss = max(0.04, lastLoss * 0.985 + syntheticNoise)
                peakMemory = max(peakMemory, max(guardrailSnapshot.residentMemoryBytes, optimizerMemory))

                if step == 1 || step % 5 == 0 || step == validatedConfig.steps {
                    await emitProgress(
                        runID: runID,
                        step: step,
                        totalSteps: validatedConfig.steps,
                        method: validatedConfig.method,
                        loss: lastLoss,
                        startTime: startTime,
                        estimatedPeakMemoryBytes: peakMemory,
                        optimizerMemoryBytes: optimizerMemory,
                        baselineOptimizerMemoryBytes: baselineOptimizerMemory,
                        thermalState: guardrailSnapshot.thermalState,
                        status: .running,
                        message: "Processing ~\(tokenEstimate) tokens/sample",
                        progress: progress,
                        record: &record
                    )
                }

                try await sleep(milliseconds: 90)
            }

            let artifact = try await finalizeArtifact(runID: runID, config: validatedConfig)
            record.status = .completed
            record.finishedAt = Date()
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
    }

    func stop() {
        stopRequested = true
    }

    func runs() async -> [FineTuneRunRecord] {
        await runStore.allRuns()
    }

    private func finalizeArtifact(runID: UUID, config: FineTuneJobConfig) async throws -> FineTuneArtifact {
        let dir = try await runStore.adapterDirectory(for: runID)
        let adapterURL = dir.appendingPathComponent("adapter_\(config.method.rawValue).safetensors")
        let metadataURL = dir.appendingPathComponent("metadata.json")

        let adapterPayload = Data("synthetic adapter payload for \(config.method.rawValue)".utf8)
        try adapterPayload.write(to: adapterURL, options: .atomic)

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

    private func syntheticGradient(size: Int, step: Int) -> [Double] {
        let stepScale = Double((step % 50) + 1) * 0.0005
        return (0..<size).map { idx in
            let v = sin(Double(idx) * 0.01 + Double(step) * 0.02)
            return v * stepScale
        }
    }

    private func emitProgress(
        runID: UUID,
        step: Int,
        totalSteps: Int,
        method: TrainingMethod,
        loss: Double,
        startTime: Date,
        estimatedPeakMemoryBytes: UInt64,
        optimizerMemoryBytes: UInt64,
        baselineOptimizerMemoryBytes: UInt64,
        thermalState: FineTuneThermalState,
        status: FineTuneRunStatus,
        message: String,
        progress callback: @escaping @Sendable (FineTuneProgress) -> Void,
        record: inout FineTuneRunRecord
    ) async {
        let elapsed = max(0.001, Date().timeIntervalSince(startTime))
        let tokensPerSecond = (Double(step) * 120.0) / elapsed

        let item = FineTuneProgress(
            runID: runID,
            step: step,
            totalSteps: totalSteps,
            loss: loss,
            tokensPerSecond: tokensPerSecond,
            estimatedPeakMemoryBytes: estimatedPeakMemoryBytes,
            optimizerMemoryBytes: optimizerMemoryBytes,
            baselineOptimizerMemoryBytes: baselineOptimizerMemoryBytes,
            thermalState: thermalState,
            status: status,
            message: message,
            method: method,
            timestamp: Date()
        )
        record.lastProgress = item
        try? await runStore.upsert(record)
        callback(item)
    }

    private func sleep(milliseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

enum FineTuneOrchestratorError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case cancelled
    case guardrailStopped(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A fine-tuning job is already running."
        case .cancelled:
            return "Fine-tuning was cancelled."
        case .guardrailStopped(let reason):
            return reason
        }
    }
}
