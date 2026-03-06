import Foundation

enum TrainingMethod: String, Codable, CaseIterable, Identifiable {
    case lora
    case galore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lora: return "LoRA"
        case .galore: return "GaLore"
        }
    }
}

enum FineTuneRunStatus: String, Codable {
    case queued
    case running
    case paused
    case cancelled
    case failed
    case completed
}

struct FineTuneJobConfig: Codable, Identifiable, Hashable {
    let id: UUID
    var baseModelIdentifier: String
    var datasetURL: URL
    var method: TrainingMethod
    var loraRank: Int
    var learningRate: Double
    var steps: Int
    var sequenceLength: Int
    var microBatchSize: Int
    var projectionUpdateInterval: Int
    var scaleFactor: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        baseModelIdentifier: String,
        datasetURL: URL,
        method: TrainingMethod,
        loraRank: Int = 8,
        learningRate: Double = 2e-4,
        steps: Int = 120,
        sequenceLength: Int = 256,
        microBatchSize: Int = 1,
        projectionUpdateInterval: Int = 200,
        scaleFactor: Double = 0.25,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.baseModelIdentifier = baseModelIdentifier
        self.datasetURL = datasetURL
        self.method = method
        self.loraRank = loraRank
        self.learningRate = learningRate
        self.steps = steps
        self.sequenceLength = sequenceLength
        self.microBatchSize = microBatchSize
        self.projectionUpdateInterval = projectionUpdateInterval
        self.scaleFactor = scaleFactor
        self.createdAt = createdAt
    }

    func validated() throws -> FineTuneJobConfig {
        if baseModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FineTuneConfigError.invalidModelIdentifier
        }
        if !FileManager.default.fileExists(atPath: datasetURL.path) {
            throw FineTuneConfigError.datasetNotFound(datasetURL.path)
        }
        if loraRank <= 0 || loraRank > 256 {
            throw FineTuneConfigError.invalidRank(loraRank)
        }
        if learningRate <= 0 || learningRate > 1 {
            throw FineTuneConfigError.invalidLearningRate(learningRate)
        }
        if steps <= 0 || steps > 50_000 {
            throw FineTuneConfigError.invalidSteps(steps)
        }
        if sequenceLength <= 0 || sequenceLength > 8192 {
            throw FineTuneConfigError.invalidSequenceLength(sequenceLength)
        }
        if microBatchSize <= 0 || microBatchSize > 64 {
            throw FineTuneConfigError.invalidMicroBatch(microBatchSize)
        }
        if method == .galore {
            if projectionUpdateInterval <= 0 {
                throw FineTuneConfigError.invalidProjectionInterval(projectionUpdateInterval)
            }
            if !(0.0 < scaleFactor && scaleFactor <= 1.0) {
                throw FineTuneConfigError.invalidScaleFactor(scaleFactor)
            }
        }
        return self
    }
}

enum FineTuneConfigError: Error, LocalizedError {
    case invalidModelIdentifier
    case datasetNotFound(String)
    case invalidRank(Int)
    case invalidLearningRate(Double)
    case invalidSteps(Int)
    case invalidSequenceLength(Int)
    case invalidMicroBatch(Int)
    case invalidProjectionInterval(Int)
    case invalidScaleFactor(Double)

    var errorDescription: String? {
        switch self {
        case .invalidModelIdentifier:
            return "Base model identifier is required."
        case .datasetNotFound(let path):
            return "Training dataset could not be found at: \(path)"
        case .invalidRank(let rank):
            return "LoRA rank must be in range 1...256. Current: \(rank)"
        case .invalidLearningRate(let value):
            return "Learning rate must be in range (0, 1]. Current: \(value)"
        case .invalidSteps(let value):
            return "Steps must be in range 1...50000. Current: \(value)"
        case .invalidSequenceLength(let value):
            return "Sequence length must be in range 1...8192. Current: \(value)"
        case .invalidMicroBatch(let value):
            return "Micro-batch must be in range 1...64. Current: \(value)"
        case .invalidProjectionInterval(let value):
            return "Projection update interval must be positive. Current: \(value)"
        case .invalidScaleFactor(let value):
            return "Scale factor must be in range (0, 1]. Current: \(value)"
        }
    }
}

struct FineTuneProgress: Codable, Hashable {
    let runID: UUID
    var step: Int
    var totalSteps: Int
    var loss: Double
    var tokensPerSecond: Double
    var estimatedPeakMemoryBytes: UInt64
    var optimizerMemoryBytes: UInt64
    var baselineOptimizerMemoryBytes: UInt64
    var thermalState: FineTuneThermalState
    var status: FineTuneRunStatus
    var message: String
    var method: TrainingMethod
    var timestamp: Date

    var fractionComplete: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, Double(step) / Double(totalSteps))
    }
}

struct FineTuneArtifact: Codable, Identifiable, Hashable {
    let id: UUID
    var runID: UUID
    var config: FineTuneJobConfig
    var baseModelIdentifier: String
    var adapterURL: URL
    var metadataURL: URL
    var createdAt: Date
}

struct FineTuneRunRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var config: FineTuneJobConfig
    var status: FineTuneRunStatus
    var startedAt: Date
    var finishedAt: Date?
    var lastProgress: FineTuneProgress?
    var artifact: FineTuneArtifact?
    var errorMessage: String?
}

enum FineTuneThermalState: String, Codable, Hashable {
    case nominal
    case fair
    case serious
    case critical

    static func from(processInfoState: ProcessInfo.ThermalState) -> FineTuneThermalState {
        switch processInfoState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .critical
        }
    }
}

struct TrainingSample: Codable, Hashable, Identifiable {
    let id: UUID
    let prompt: String
    let completion: String

    init(id: UUID = UUID(), prompt: String, completion: String) {
        self.id = id
        self.prompt = prompt
        self.completion = completion
    }
}
