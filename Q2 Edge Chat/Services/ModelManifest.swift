import Foundation

struct ManifestEntry: Codable, Identifiable {
    let id: String
    let localURL: URL
    let downloadedAt: Date
    
    func url() throws -> URL {
        let fm = FileManager.default
        let library = try fm.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelPath = library.appendingPathComponent(localURL.path())
        print("modelPath: \(modelPath)")
        print("modelT: \(library.appending(path: localURL.path))")
        return modelPath
    }
}

actor ManifestStore {
    private let fileURL: URL
    private var entries: [ManifestEntry] = []

    init() throws {
        let fm = FileManager.default
        let support = try fm.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = support.appendingPathComponent("models.json")
        if fm.fileExists(atPath: fileURL.path()) {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([ManifestEntry].self, from: data)
        }
    }

    func all() -> [ManifestEntry] {
        entries
    }

    func add(_ entry: ManifestEntry) throws {
        entries.append(entry)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
    
    
    func download(quickChatModelID: String) async -> ManifestEntry? {
        var message = ""
        
        do {
            if self.all().contains(where: { $0.id == quickChatModelID }) {
                message = "\(quickChatModelID) is already available."
                return nil
            }

            message = "Downloading \(quickChatModelID)..."
            print(message)
            
            let manager = ModelManager()
            
            let modelInfo = try await manager.fetchModelInfo(modelID: quickChatModelID)
            
            let fileToDownload = modelInfo.siblings.first(where: { $0.rfilename.lowercased().hasSuffix(".gguf") })
            
            guard let file = fileToDownload else {
                throw NSError(domain: "AppError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No suitable .gguf file found for the model."])
            }
            
            let downloadURLString = "https://huggingface.co/\(modelInfo.id)/resolve/main/\(file.rfilename)"
            guard let downloadURL = URL(string: downloadURLString) else {
                throw URLError(.badURL)
            }
            
            let localURL = try await manager.downloadModelFile(from: downloadURL, modelID: modelInfo.id, filename: file.rfilename)
            
            let newManifestEntry = ManifestEntry(id: modelInfo.id, localURL: localURL, downloadedAt: Date())
            try self.add(newManifestEntry)
            
            message = "Successfully downloaded \(file.rfilename)!"
            print(message)
            return newManifestEntry
        } catch {
            message = "Download failed: \(error.localizedDescription)"
            print(message)
            return nil
        }
    }

    func remove(id: String) throws {
        entries.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
    
    func first() -> ManifestEntry? {
        entries.first
    }
}
