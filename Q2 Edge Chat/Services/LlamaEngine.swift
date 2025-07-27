import Foundation
import LLamaSwift

final class LlamaEngine {
    private let llama: LLamaSwift.LLama
    private let modelURL: URL

    init(modelURL: URL) throws {
        self.modelURL = modelURL
        
        // Validate model file exists and is accessible
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LlamaEngineError.modelNotFound(modelURL.path)
        }
        
        guard FileManager.default.isReadableFile(atPath: modelURL.path) else {
            throw LlamaEngineError.modelNotReadable(modelURL.path)
        }
        
        let validExtensions = [".gguf", ".bin"]
        guard validExtensions.contains(where: { modelURL.path.hasSuffix($0) }) else {
            throw LlamaEngineError.invalidModelFormat(modelURL.pathExtension)
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
            if let fileSize = attributes[.size] as? Int64, fileSize < 1_048_576 {
                throw LlamaEngineError.modelTooSmall(fileSize)
            }
        } catch {
            throw LlamaEngineError.validationFailed("Could not validate model file: \(error.localizedDescription)")
        }
        
        do {
            let model = try LLamaSwift.Model(modelPath: modelURL.path)
            self.llama = LLamaSwift.LLama(model: model)
        } catch {
            throw LlamaEngineError.modelLoadFailed(error.localizedDescription)
        }
    }
    
    enum LlamaEngineError: Error {
        case modelNotFound(String)
        case modelNotReadable(String)
        case invalidModelFormat(String)
        case modelTooSmall(Int64)
        case modelLoadFailed(String)
        case validationFailed(String)
        case generationError(String)
        
        var localizedDescription: String {
            switch self {
            case .modelNotFound(let path):
                return "Model file not found at path: \(path)"
            case .modelNotReadable(let path):
                return "Model file is not readable: \(path)"
            case .invalidModelFormat(let ext):
                return "Invalid model format: .\(ext). Expected .gguf or .bin"
            case .modelTooSmall(let size):
                return "Model file too small (\(size) bytes). May be corrupted."
            case .modelLoadFailed(let error):
                return "Failed to load model: \(error)"
            case .validationFailed(let error):
                return "Model validation failed: \(error)"
            case .generationError(let error):
                return "Text generation failed: \(error)"
            }
        }
    }

    func generate(prompt: String,
                  maxTokens: Int32 = 120,
                  tokenHandler: @escaping (String) -> Void) async throws {
        // Validate input parameters
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LlamaEngineError.generationError("Prompt cannot be empty")
        }
        
        guard maxTokens > 0 && maxTokens <= 4096 else {
            throw LlamaEngineError.generationError("Max tokens must be between 1 and 4096")
        }
        
        // Validate prompt length (reasonable limit to prevent memory issues)
        guard prompt.count <= 50_000 else {
            throw LlamaEngineError.generationError("Prompt too long (max 50,000 characters)")
        }
        
        do {
            for try await token in await llama.infer(prompt: prompt,
                                                     maxTokens: maxTokens) {
                try Task.checkCancellation()
                tokenHandler(token)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LlamaEngineError.generationError(error.localizedDescription)
        }
    }
}
