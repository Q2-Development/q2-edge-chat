import Foundation
import LLamaSwift

struct HFSibling: Codable {
    let rfilename: String
}

struct ModelDetail {
    let model: HFModel
    let readme: String?
    let hasGGUF: Bool
    let ggufFiles: [HFSibling]
}

struct StaffPickModel {
    let huggingFaceId: String
    let displayName: String
    let description: String
    let parameterCount: String
    let specialty: String
    let category: String
    
    static let staffPicks: [StaffPickModel] = [
        StaffPickModel(
            huggingFaceId: "microsoft/Phi-3-mini-4k-instruct-gguf",
            displayName: "Phi-3 Mini",
            description: "Microsoft's excellent small model with strong reasoning capabilities",
            parameterCount: "3.8B",
            specialty: "General Chat",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "Qwen/Qwen2-1.5B-Instruct-GGUF",
            displayName: "Qwen2 1.5B",
            description: "Efficient multilingual model with great performance-to-size ratio",
            parameterCount: "1.5B",
            specialty: "Multilingual",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "PY007/TinyLlama-1.1B-Chat-v0.3-gguf",
            displayName: "TinyLlama",
            description: "Ultra-small model perfect for testing and resource-constrained environments",
            parameterCount: "1.1B",
            specialty: "Lightweight",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "google/gemma-2b-it-gguf",
            displayName: "Gemma 2B",
            description: "Google's efficient instruction-tuned model with strong safety features",
            parameterCount: "2B",
            specialty: "Safe AI",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "bartowski/Llama-3.2-1B-Instruct-GGUF",
            displayName: "Llama 3.2 1B",
            description: "Meta's latest small model with excellent instruction following",
            parameterCount: "1B",
            specialty: "Instruction Following",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "HuggingFaceTB/SmolLM-1.7B-Instruct-GGUF",
            displayName: "SmolLM 1.7B",
            description: "Highly optimized small model with impressive capabilities",
            parameterCount: "1.7B",
            specialty: "Optimized",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "stabilityai/stablelm-2-1_6b-chat-gguf",
            displayName: "StableLM 2",
            description: "Stability AI's chat-optimized model with balanced performance",
            parameterCount: "1.6B",
            specialty: "Chat",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "bartowski/CodeGemma-2b-GGUF",
            displayName: "CodeGemma 2B",
            description: "Google's coding-focused model for programming assistance",
            parameterCount: "2B",
            specialty: "Code Generation",
            category: "Coding"
        ),
        StaffPickModel(
            huggingFaceId: "microsoft/Phi-3.5-mini-instruct-gguf",
            displayName: "Phi-3.5 Mini",
            description: "Microsoft's updated reasoning model with enhanced capabilities",
            parameterCount: "3.8B",
            specialty: "Reasoning",
            category: "General"
        ),
        StaffPickModel(
            huggingFaceId: "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF",
            displayName: "Qwen2.5 Coder",
            description: "Latest Qwen model specialized for coding tasks",
            parameterCount: "1.5B",
            specialty: "Code Generation",
            category: "Coding"
        )
    ]
}

struct HFModel: Codable {
    let _id: String?
    let id: String
    let author: String?
    let gated: Bool?
    let lastModified: String?
    let likes: Int?
    let trendingScore: Int?
    let isPrivate: Bool?
    let sha: String?
    let downloads: Int?
    let tags: [String]?
    let pipelineTag: String?
    let libraryName: String?
    let createdAt: String?
    let modelId: String?
    let siblings: [HFSibling]
    
    enum CodingKeys: String, CodingKey {
        case _id, id, author, lastModified, likes, trendingScore, downloads, tags, siblings, createdAt, sha, modelId
        case isPrivate = "private"
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case gated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        _id = try container.decodeIfPresent(String.self, forKey: ._id)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        lastModified = try container.decodeIfPresent(String.self, forKey: .lastModified)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes)
        trendingScore = try container.decodeIfPresent(Int.self, forKey: .trendingScore)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        sha = try container.decodeIfPresent(String.self, forKey: .sha)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        pipelineTag = try container.decodeIfPresent(String.self, forKey: .pipelineTag)
        libraryName = try container.decodeIfPresent(String.self, forKey: .libraryName)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        siblings = try container.decode([HFSibling].self, forKey: .siblings)
        
        // Handle gated field that can be either Bool or String
        if let gatedBool = try? container.decodeIfPresent(Bool.self, forKey: .gated) {
            gated = gatedBool
        } else if let gatedString = try? container.decodeIfPresent(String.self, forKey: .gated) {
            gated = gatedString.lowercased() == "true"
        } else {
            gated = nil
        }
    }
}

actor ModelManager {
    private let pageSize = 20
    func fetchModels(search: String? = nil) async throws -> [HFModel] {
        var urlString = "https://huggingface.co/api/models?full=true&limit=\(pageSize)"
        if let search = search {
            urlString += "&search=\(search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        
        guard let url = URL(string: urlString) else {
            throw ModelManagerError.networkError("Invalid API URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Debug: Print raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("🔍 Raw API Response (first 1000 chars): \(String(jsonString.prefix(1000)))")
        }
        
        do {
            return try JSONDecoder().decode([HFModel].self, from: data)
        } catch {
            print("🚨 JSON Decoding Error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("Missing key: \(key.stringValue) at \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch for type: \(type) at \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("Value not found for type: \(type) at \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("Data corrupted at \(context.codingPath)")
                @unknown default:
                    print("Unknown decoding error")
                }
            }
            throw error
        }
    }
    
    func fetchModelInfo(modelID: String) async throws -> HFModel {
        
        let urlString = "https://huggingface.co/api/models/\(modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        return try JSONDecoder().decode(HFModel.self, from: data)
    }
    
    func searchModels(query: String) async throws -> [HFModel] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://huggingface.co/api/models?search=\(encodedQuery)&full=true&limit=20") else {
            throw ModelManagerError.networkError("Invalid search URL")
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([HFModel].self, from: data)
    }
    
    func fetchModelREADME(modelId: String) async throws -> String {
        let encodedModelId = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        guard let url = URL(string: "https://huggingface.co/\(encodedModelId)/raw/main/README.md") else {
            throw ModelManagerError.networkError("Invalid README URL")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return "" // No README available
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func checkGGUFFiles(model: HFModel) -> (hasGGUF: Bool, ggufFiles: [HFSibling]) {
        let ggufFiles = model.siblings.filter { $0.rfilename.hasSuffix(".gguf") }
        return (hasGGUF: !ggufFiles.isEmpty, ggufFiles: ggufFiles)
    }
    
    func fetchModelDetail(modelId: String) async throws -> ModelDetail {
        let model = try await fetchModelInfo(modelID: modelId)
        let readme = try? await fetchModelREADME(modelId: modelId)
        let ggufInfo = checkGGUFFiles(model: model)
        
        return ModelDetail(
            model: model,
            readme: readme,
            hasGGUF: ggufInfo.hasGGUF,
            ggufFiles: ggufInfo.ggufFiles
        )
    }

    func buildLocalModelURL(modelID: String, filename: String) throws -> URL {
        let sanitizedModelID = modelID.replacingOccurrences(of: "/", with: "_")
        
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw ModelManagerError.fileSystemError("Unable to access library directory")
        }
        
        let filePath = libraryURL
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(sanitizedModelID, isDirectory: true)
            .appendingPathComponent(filename)
        
        return filePath
    }
    
    enum ModelManagerError: Error {
        case fileSystemError(String)
        case downloadError(String)
        case networkError(String)
        
        var localizedDescription: String {
            switch self {
            case .fileSystemError(let message):
                return "File system error: \(message)"
            case .downloadError(let message):
                return "Download error: \(message)"
            case .networkError(let message):
                return "Network error: \(message)"
            }
        }
    }
    
    func downloadModelFile(from fileURL: URL, modelID: String, filename: String) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: fileURL, delegate: nil)
        
        let fm = FileManager.default
        let destURL = try buildLocalModelURL(modelID: modelID, filename: filename)
        let destDir = destURL.deletingLastPathComponent()
        
        print("dest: \(destDir.path())")
            
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        
        try fm.moveItem(at: tempURL, to: destURL)
        
        // Return relative path from Library directory to avoid simulator container issues
        let libraryURL = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        
        let relativePath = destURL.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
        return URL(fileURLWithPath: relativePath)
    }
}
