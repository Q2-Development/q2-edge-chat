import Foundation
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif

struct LoadedModelDescriptor: Hashable {
    let identifier: String
    let isLocalPath: Bool
}

enum MLXModelLoaderError: Error, LocalizedError {
    case invalidIdentifier

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return "A valid MLX model identifier or local path is required."
        }
    }
}

struct MLXModelLoaderService {
    func loadModel(identifier: String) async throws -> (LoadedModelDescriptor, ModelContainer) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MLXModelLoaderError.invalidIdentifier
        }

        let isLocalPath = normalized.hasPrefix("/")
        #if canImport(MLXLLM) && canImport(MLXLMCommon)
        let config: ModelConfiguration
        if isLocalPath {
            config = ModelConfiguration(directory: URL(fileURLWithPath: normalized))
        } else {
            config = ModelConfiguration(id: normalized)
        }
        let container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        return (LoadedModelDescriptor(identifier: normalized, isLocalPath: isLocalPath), container)
        #else
        throw MLXModelLoaderError.invalidIdentifier
        #endif
    }
}
