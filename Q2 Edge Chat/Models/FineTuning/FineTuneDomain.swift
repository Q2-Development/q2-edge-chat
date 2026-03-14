import Foundation

enum FineTuneMemoryPolicy {
    static let maxResidentMemoryBytes: UInt64 = 2_200_000_000
    static let pauseResidentMemoryBytes: UInt64 = 2_050_000_000
    static let maxAdapterSequenceLength = 128
    static let maxGaLoreSequenceLength = 96
    static let maxAdapterRank = 8
    static let maxGaLoreRank = 4
    static let maxMicroBatch = 1
    static let maxSupportedModelBillions = 1.5
}

enum TrainingMethod: String, Codable, CaseIterable, Identifiable {
    case lora
    case qlora
    case dora
    case galore

    var id: String { rawValue }

    static var selectableCases: [TrainingMethod] {
        [.qlora, .dora]
    }

    var displayName: String {
        switch self {
        case .lora: return "LoRA (Legacy)"
        case .qlora: return "QLoRA"
        case .dora: return "DoRA"
        case .galore: return "GaLore (Experimental)"
        }
    }

    var detailText: String {
        switch self {
        case .lora:
            return "Legacy adapter fine-tuning on MLX models."
        case .qlora:
            return "Recommended on iPhone: LoRA adapters on a quantized MLX base model, usually 4-bit."
        case .dora:
            return "Higher-quality adapter path than plain LoRA with slightly more compute. Prefer quantized MLX models on iPhone."
        case .galore:
            return "Experimental research path. In this app it projects adapter gradients only, not full-parameter paper-faithful GaLore."
        }
    }

    var requiresQuantizedRemoteModel: Bool {
        switch self {
        case .qlora:
            return true
        case .lora, .dora, .galore:
            return false
        }
    }

    var usesProjectedOptimizerResearchPath: Bool {
        self == .galore
    }

    var adapterRankLimit: Int {
        switch self {
        case .galore:
            return FineTuneMemoryPolicy.maxGaLoreRank
        case .lora, .qlora, .dora:
            return FineTuneMemoryPolicy.maxAdapterRank
        }
    }

    var sequenceLengthLimit: Int {
        switch self {
        case .galore:
            return FineTuneMemoryPolicy.maxGaLoreSequenceLength
        case .lora, .qlora, .dora:
            return FineTuneMemoryPolicy.maxAdapterSequenceLength
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
        if method.requiresQuantizedRemoteModel && !looksLikeLocalModelReference() && !isLikelyQuantizedModelIdentifier() {
            throw FineTuneConfigError.quantizedModelRequired(baseModelIdentifier)
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

struct FineTuneSafetyAdjustment: Equatable {
    let config: FineTuneJobConfig
    let notes: [String]
}

extension FineTuneJobConfig {
    func applyingMemorySafetyPolicy() -> FineTuneSafetyAdjustment {
        var adjusted = self
        var notes: [String] = []

        if adjusted.microBatchSize > FineTuneMemoryPolicy.maxMicroBatch {
            notes.append("Micro-batch reduced from \(adjusted.microBatchSize) to \(FineTuneMemoryPolicy.maxMicroBatch).")
            adjusted.microBatchSize = FineTuneMemoryPolicy.maxMicroBatch
        }

        let maxRank = adjusted.method.adapterRankLimit
        if adjusted.loraRank > maxRank {
            notes.append("Rank reduced from \(adjusted.loraRank) to \(maxRank).")
            adjusted.loraRank = maxRank
        }

        let maxSequenceLength = adjusted.method.sequenceLengthLimit
        if adjusted.sequenceLength > maxSequenceLength {
            notes.append("Sequence length reduced from \(adjusted.sequenceLength) to \(maxSequenceLength).")
            adjusted.sequenceLength = maxSequenceLength
        }

        if adjusted.method == .qlora && !adjusted.looksLikeLocalModelReference() && !adjusted.isLikelyQuantizedModelIdentifier() {
            notes.append("QLoRA works best with quantized MLX model ids such as `mlx-community/...-4bit`.")
        }

        return FineTuneSafetyAdjustment(config: adjusted, notes: notes)
    }

    func estimatedModelBillions() -> Double? {
        let lower = baseModelIdentifier.lowercased()
        guard let match = lower.range(of: #"(\d+(?:\.\d+)?)\s*b"#, options: .regularExpression) else {
            return nil
        }
        let token = lower[match]
        let number = token.replacingOccurrences(of: "b", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(number)
    }

    func looksLikeLocalModelReference() -> Bool {
        let trimmed = baseModelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") || trimmed.hasPrefix("file://") {
            return true
        }
        return FileManager.default.fileExists(atPath: trimmed)
    }

    func isLikelyQuantizedModelIdentifier() -> Bool {
        let lower = baseModelIdentifier.lowercased()
        let tokens = ["4bit", "8bit", "int4", "int8", "q4", "q8", "awq", "gptq"]
        return tokens.contains { lower.contains($0) }
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
    case quantizedModelRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidModelIdentifier:
            return "Base model identifier is required."
        case .datasetNotFound(let path):
            return "Training dataset could not be found at: \(path)"
        case .invalidRank(let rank):
            return "Adapter rank must be in range 1...256. Current: \(rank)"
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
        case .quantizedModelRequired(let identifier):
            return "QLoRA requires a quantized MLX base model. Current identifier: \(identifier). Use a model id like `mlx-community/...-4bit` or a local quantized MLX path."
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
