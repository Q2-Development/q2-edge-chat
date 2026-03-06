import Foundation
#if canImport(MLXLLM)
import MLXLLM
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
    func loadModelDescriptor(identifier: String) async throws -> LoadedModelDescriptor {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw MLXModelLoaderError.invalidIdentifier
        }

        let isLocalPath = normalized.hasPrefix("/")

        // Placeholder load path; this intentionally keeps integration build-safe
        // while package-level MLX dependencies are linked for future expansion.

        return LoadedModelDescriptor(identifier: normalized, isLocalPath: isLocalPath)
    }
}
