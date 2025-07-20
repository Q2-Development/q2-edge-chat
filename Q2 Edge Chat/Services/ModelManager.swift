import Foundation

struct HFSibling: Codable {
    let rfilename: String
}

struct HFModel: Codable {
    let id: String
    let siblings: [HFSibling]
}

actor ModelManager {
    func fetchModelInfo(modelID: String) async throws -> HFModel {
        
        let urlString = "https://huggingface.co/api/models/\(modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        return try JSONDecoder().decode(HFModel.self, from: data)
    }

    func downloadModelFile(from fileURL: URL, modelID: String, filename: String) async throws -> URL {
        
        let (tempURL, _) = try await URLSession.shared.download(from: fileURL, delegate: nil)
        
        let fm = FileManager.default
        
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let sanitizedModelID = modelID.replacingOccurrences(of: "/", with: "_")
        
        let destDir = support
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(sanitizedModelID, isDirectory: true)
            
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        let destURL = destDir.appendingPathComponent(filename)
        
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        
        try fm.moveItem(at: tempURL, to: destURL)
        
        return destURL
    }
}
