import Foundation

enum FineTuneMemoryPolicy {
    static let maxResidentMemoryBytes: UInt64 = 2_200_000_000
    static let pauseResidentMemoryBytes: UInt64 = 2_050_000_000
    static let maxAdapterSequenceLength = 128
    static let maxApolloSequenceLength = 64
    static let maxGaLoreSequenceLength = 96
    static let maxAdapterRank = 8
    static let maxApolloRank = 4
    static let maxGaLoreRank = 4
    static let maxMicroBatch = 1
    static let maxApolloModelBillions = 0.5
    static let maxSupportedModelBillions = 1.5
}

enum TrainingMethod: String, Codable, CaseIterable, Identifiable {
    case lora
    case qlora
    case dora
    case apollo
    case galore

    var id: String { rawValue }

    static var selectableCases: [TrainingMethod] {
        [.qlora, .dora, .apollo]
    }

    var displayName: String {
        switch self {
        case .lora: return "LoRA (Legacy)"
        case .qlora: return "QLoRA"
        case .dora: return "DoRA"
        case .apollo: return "APOLLO (Experimental)"
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
        case .apollo:
            return "Experimental full-model low-memory trainer. Use only tiny MLX models, ideally local and unquantized, to evaluate APOLLO-style random projection."
        case .galore:
            return "Experimental research path. In this app it projects adapter gradients only, not full-parameter paper-faithful GaLore."
        }
    }

    var requiresQuantizedRemoteModel: Bool {
        switch self {
        case .qlora:
            return true
        case .lora, .dora, .apollo, .galore:
            return false
        }
    }

    var usesAdapterTrainingPath: Bool {
        self != .apollo
    }

    var usesProjectedOptimizerTelemetry: Bool {
        switch self {
        case .apollo, .galore:
            return true
        case .lora, .qlora, .dora:
            return false
        }
    }

    var showsProjectionControls: Bool {
        usesProjectedOptimizerTelemetry
    }

    var rankControlLabel: String {
        switch self {
        case .apollo, .galore:
            return "Projection rank"
        case .lora, .qlora, .dora:
            return "Adapter rank"
        }
    }

    var adapterRankLimit: Int {
        switch self {
        case .apollo:
            return FineTuneMemoryPolicy.maxApolloRank
        case .galore:
            return FineTuneMemoryPolicy.maxGaLoreRank
        case .lora, .qlora, .dora:
            return FineTuneMemoryPolicy.maxAdapterRank
        }
    }

    var sequenceLengthLimit: Int {
        switch self {
        case .apollo:
            return FineTuneMemoryPolicy.maxApolloSequenceLength
        case .galore:
            return FineTuneMemoryPolicy.maxGaLoreSequenceLength
        case .lora, .qlora, .dora:
            return FineTuneMemoryPolicy.maxAdapterSequenceLength
        }
    }

    var modelSizeLimitBillions: Double {
        switch self {
        case .apollo:
            return FineTuneMemoryPolicy.maxApolloModelBillions
        case .lora, .qlora, .dora, .galore:
            return FineTuneMemoryPolicy.maxSupportedModelBillions
        }
    }

    var artifactKind: FineTuneArtifactKind {
        switch self {
        case .apollo:
            return .fullModelWeights
        case .lora, .qlora, .dora, .galore:
            return .adapter
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
        if method == .apollo && isLikelyQuantizedModelIdentifier() {
            throw FineTuneConfigError.fullModelTrainingRequiresNonQuantizedModel(baseModelIdentifier)
        }
        if let modelBillions = estimatedModelBillions(),
           modelBillions > method.modelSizeLimitBillions {
            throw FineTuneConfigError.modelTooLarge(method: method, modelBillions: modelBillions)
        }
        if method == .apollo || method == .galore {
            if projectionUpdateInterval <= 0 {
                throw FineTuneConfigError.invalidProjectionInterval(projectionUpdateInterval)
            }
        }
        if method == .galore {
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
    case fullModelTrainingRequiresNonQuantizedModel(String)
    case modelTooLarge(method: TrainingMethod, modelBillions: Double)

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
        case .fullModelTrainingRequiresNonQuantizedModel(let identifier):
            return "The APOLLO full-model research path does not support quantized remote models. Current identifier: \(identifier). Use a tiny local MLX model or a small unquantized MLX model id."
        case .modelTooLarge(let method, let modelBillions):
            return "\(method.displayName) is capped to \(String(format: "%.1fB", method.modelSizeLimitBillions)) models in this app. Current model appears to be \(modelBillions)B."
        }
    }
}

struct FineTuneDeviceTelemetry: Codable, Hashable {
    var deviceModel: String
    var machineIdentifier: String
    var systemName: String
    var systemVersion: String
    var operatingSystemVersionString: String
}

struct FineTuneRunTelemetry: Codable, Hashable {
    var runID: UUID
    var baseModelIdentifier: String
    var trainingMethod: TrainingMethod
    var finalStatus: FineTuneRunStatus
    var device: FineTuneDeviceTelemetry
    var totalSamples: Int?
    var trainingSampleCount: Int?
    var validationSampleCount: Int?
    var totalSteps: Int
    var completedSteps: Int
    var latestLoss: Double?
    var bestLoss: Double?
    var maxTokensPerSecond: Double
    var peakEstimatedMemoryBytes: UInt64
    var peakOptimizerMemoryBytes: UInt64
    var baselineOptimizerMemoryBytes: UInt64
    var latestThermalState: FineTuneThermalState?
    var errorMessage: String?
    var startedAt: Date
    var finishedAt: Date?
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
    var kind: FineTuneArtifactKind = .adapter

    private enum CodingKeys: String, CodingKey {
        case id
        case runID
        case config
        case baseModelIdentifier
        case adapterURL
        case metadataURL
        case createdAt
        case kind
    }

    init(
        id: UUID,
        runID: UUID,
        config: FineTuneJobConfig,
        baseModelIdentifier: String,
        adapterURL: URL,
        metadataURL: URL,
        createdAt: Date,
        kind: FineTuneArtifactKind = .adapter
    ) {
        self.id = id
        self.runID = runID
        self.config = config
        self.baseModelIdentifier = baseModelIdentifier
        self.adapterURL = adapterURL
        self.metadataURL = metadataURL
        self.createdAt = createdAt
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        runID = try container.decode(UUID.self, forKey: .runID)
        config = try container.decode(FineTuneJobConfig.self, forKey: .config)
        baseModelIdentifier = try container.decode(String.self, forKey: .baseModelIdentifier)
        adapterURL = try container.decode(URL.self, forKey: .adapterURL)
        metadataURL = try container.decode(URL.self, forKey: .metadataURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decodeIfPresent(FineTuneArtifactKind.self, forKey: .kind) ?? .adapter
    }
}

enum FineTuneArtifactKind: String, Codable, Hashable {
    case adapter
    case fullModelWeights

    var displayName: String {
        switch self {
        case .adapter:
            return "Adapter"
        case .fullModelWeights:
            return "Full Model Weights"
        }
    }

    var exportLabel: String {
        switch self {
        case .adapter:
            return "Export Adapter"
        case .fullModelWeights:
            return "Export Weights"
        }
    }
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
    var telemetry: FineTuneRunTelemetry? = nil
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
