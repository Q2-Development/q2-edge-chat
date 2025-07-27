import Foundation
import LLamaSwift

struct HFSibling: Codable {
    let rfilename: String
}

struct HFModel: Codable {
    let id: String
    let siblings: [HFSibling]
}

actor ModelManager {
    private let pageSize = 20
    func fetchModels() async throws -> [HFModel] {
        guard let url = URL(string: "https://huggingface.co/api/models?full=true&limit=\(pageSize)") else {
            throw ModelManagerError.networkError("Invalid API URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([HFModel].self, from: data)
    }
    
    func fetchModelInfo(modelID: String) async throws -> HFModel {
        
        let urlString = "https://huggingface.co/api/models/\(modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        return try JSONDecoder().decode(HFModel.self, from: data)
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
        
        return destURL
    }
}
