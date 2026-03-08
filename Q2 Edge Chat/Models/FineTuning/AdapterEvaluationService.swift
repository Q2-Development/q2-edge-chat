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

struct AdapterEvaluationResult: Sendable {
    let baseOutput: String
    let adaptedOutput: String
}

enum AdapterEvaluationError: Error, LocalizedError {
    case promptRequired
    case adapterNotFound(String)
    case trainingUnavailable
    case loraModelUnavailable

    var errorDescription: String? {
        switch self {
        case .promptRequired:
            return "Prompt is required for adapter evaluation."
        case .adapterNotFound(let path):
            return "Adapter file could not be found at: \(path)"
        case .trainingUnavailable:
            return "MLX evaluation dependencies are not available in this build."
        case .loraModelUnavailable:
            return "Loaded model does not expose LoRA layers, so adapter cannot be applied."
        }
    }
}

struct AdapterEvaluationService {
    private let loader = MLXModelLoaderService()

    func compare(
        modelIdentifier: String,
        adapterURL: URL,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> AdapterEvaluationResult {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AdapterEvaluationError.promptRequired
        }
        guard FileManager.default.fileExists(atPath: adapterURL.path) else {
            throw AdapterEvaluationError.adapterNotFound(adapterURL.path)
        }

        #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
        defer { Self.releaseEvaluationMemory() }

        let (_, baseContainer) = try await loader.loadModel(identifier: modelIdentifier)
        let baseOutput = try await generate(
            with: baseContainer,
            prompt: trimmedPrompt,
            maxTokens: maxTokens,
            temperature: temperature
        )

        let (_, adaptedContainer) = try await loader.loadModel(identifier: modelIdentifier)
        try await applyAdapter(at: adapterURL, to: adaptedContainer)
        let adaptedOutput = try await generate(
            with: adaptedContainer,
            prompt: trimmedPrompt,
            maxTokens: maxTokens,
            temperature: temperature
        )

        return AdapterEvaluationResult(baseOutput: baseOutput, adaptedOutput: adaptedOutput)
        #else
        throw AdapterEvaluationError.trainingUnavailable
        #endif
    }

    #if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)
    private func generate(
        with container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String {
        let params = GenerateParameters(
            maxTokens: max(1, min(maxTokens, 512)),
            temperature: max(0, min(temperature, 2)),
            topP: 1.0
        )
        let session = MLXLMCommon.ChatSession(container, generateParameters: params)
        return try await session.respond(to: prompt)
    }

    private func applyAdapter(at adapterURL: URL, to container: ModelContainer) async throws {
        let adapterConfig = try loadAdapterConfiguration(for: adapterURL)
        let adapterWeights = try loadArrays(url: adapterURL)

        try await container.perform { context in
            guard context.model is LoRAModel else {
                throw AdapterEvaluationError.loraModelUnavailable
            }

            _ = try LoRAContainer.from(model: context.model, configuration: adapterConfig)

            let merged = context.model.trainableParameters().mapValues { key, value in
                adapterWeights[key] ?? value
            }
            context.model.update(parameters: merged)
            eval(context.model)
        }
    }

    private func loadAdapterConfiguration(for adapterURL: URL) throws -> LoRAConfiguration {
        let configURL = adapterURL.deletingLastPathComponent().appendingPathComponent("adapter_config.json")
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(LoRAConfiguration.self, from: data) {
            return config
        }

        return LoRAConfiguration(
            numLayers: 8,
            fineTuneType: .lora,
            loraParameters: .init(rank: 8, scale: 10, keys: nil)
        )
    }

    private static func releaseEvaluationMemory() {
        MLX.Memory.clearCache()
    }
    #endif
}
