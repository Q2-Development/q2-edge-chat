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
            let url = URL(string: "https://huggingface.co/api/models?full=true&limit=\(pageSize)")!
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

    func buildLocalModelURL(modelID: String, filename: String) -> URL {
        let sanitizedModelID = modelID.replacingOccurrences(of: "/", with: "_")
        
        let filePath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(sanitizedModelID, isDirectory: true)
            .appendingPathComponent(filename)
        
        return filePath
    }
    
    func downloadModelFile(from fileURL: URL, modelID: String, filename: String) async throws -> URL {
        
        let (tempURL, _) = try await URLSession.shared.download(from: fileURL, delegate: nil)
        
        let fm = FileManager.default
        
        let support = try fm.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let sanitizedModelID = modelID.replacingOccurrences(of: "/", with: "_")
        
        let destDir = support
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(sanitizedModelID, isDirectory: true)
        
        print("dest: \(destDir.path())")
            
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        let destURL = destDir.appendingPathComponent(filename)
        
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        
        try fm.moveItem(at: tempURL, to: destURL)
        

        // Returning URL from the root of the custom directories to avoid file error related to sandboxing
        return URL(string: "Models")!.appendingPathComponent(sanitizedModelID, isDirectory: true).appendingPathComponent(filename)
    }
}
