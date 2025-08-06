import Foundation
import SwiftLlama

enum LlamaEngineError: Error {
    case modelNotFound(String)
    case modelNotReadable(String)
    case invalidModelFormat(String)
    case modelTooSmall(Int64)
    case modelLoadFailed(String)
    case modelTooLargeForMemory(String)
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
            return "Unable to load the model. This may be due to a corrupted file or incompatible format. Technical details: \(error)"
        case .modelTooLargeForMemory(let modelName):
            return "The model '\(modelName)' is too large to fit into memory. Please choose a smaller model or free up system memory."
        case .validationFailed(let error):
            return "Model validation failed: \(error)"
        case .generationError(let error):
            return "Unable to generate response. This may be due to an issue with the model or prompt. Technical details: \(error)"
        }
    }
}

final class LlamaEngine {
    private let swiftLlama: SwiftLlama
    private let modelURL: URL

    init(modelURL: URL) throws {
        self.modelURL = modelURL
        
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
            if let fileSize = attributes[.size] as? Int64 {
                if fileSize < 1_048_576 {
                    throw LlamaEngineError.modelTooSmall(fileSize)
                }
            }
        } catch {
            throw LlamaEngineError.validationFailed("Could not validate model file: \(error.localizedDescription)")
        }
        
        do {
            self.swiftLlama = try SwiftLlama(modelPath: modelURL.path)
        } catch {
            let errorMessage = error.localizedDescription.lowercased()
            let modelName = modelURL.lastPathComponent
            
            // Check for memory-related errors
            if errorMessage.contains("memory") || 
               errorMessage.contains("allocation") ||
               errorMessage.contains("out of memory") ||
               errorMessage.contains("failed to allocate") ||
               errorMessage.contains("insufficient memory") ||
               errorMessage.contains("mmap") {
                throw LlamaEngineError.modelTooLargeForMemory(modelName)
            }
            
            throw LlamaEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func generate(prompt: String,
                  settings: ModelSettings = .default,
                  tokenHandler: @escaping (String) -> Void) async throws {
        // Validate input parameters
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LlamaEngineError.generationError("Prompt cannot be empty")
        }
        
        guard settings.maxTokens > 0 && settings.maxTokens <= 4096 else {
            throw LlamaEngineError.generationError("Max tokens must be between 1 and 4096")
        }
        
        // Validate prompt length (reasonable limit to prevent memory issues)
        guard prompt.count <= 50_000 else {
            throw LlamaEngineError.generationError("Prompt too long (max 50,000 characters)")
        }
        
        do {
            let llamaPrompt = Prompt(
                type: .llama3,
                systemPrompt: settings.systemPrompt,
                userMessage: prompt
            )
            
            for try await token in await swiftLlama.start(for: llamaPrompt) {
                try Task.checkCancellation()
                tokenHandler(token)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let errorMessage = error.localizedDescription.lowercased()
            
            // Check for memory-related errors during generation
            if errorMessage.contains("memory") || 
               errorMessage.contains("allocation") ||
               errorMessage.contains("out of memory") ||
               errorMessage.contains("failed to allocate") ||
               errorMessage.contains("insufficient memory") {
                throw LlamaEngineError.modelTooLargeForMemory("Current model")
            }
            
            throw LlamaEngineError.generationError(error.localizedDescription)
        }
    }
}
