import Foundation

struct HFSibling: Codable {
    let rfilename: String
    let blobUrl: String

    enum CodingKeys: String, CodingKey {
        case rfilename
        case blobUrl = "blob_url"
    }
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

    func downloadModelFile(from fileURL: URL, modelID: String) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: fileURL, delegate: nil)
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let destDir = support
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelID, isDirectory: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = destDir.appendingPathComponent(fileURL.lastPathComponent)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.moveItem(at: tempURL, to: destURL)
        return destURL
    }
}
