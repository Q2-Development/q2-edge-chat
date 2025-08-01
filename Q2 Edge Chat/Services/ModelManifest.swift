import Foundation
import Combine

struct ManifestEntry: Codable, Identifiable {
    let id: String
    let localURL: URL
    let downloadedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id, localURL, downloadedAt
    }
    
    init(id: String, localURL: URL, downloadedAt: Date) {
        self.id = id
        self.localURL = localURL
        self.downloadedAt = downloadedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        
        let urlString = try container.decode(String.self, forKey: .localURL)
        
        if urlString.hasPrefix("file://") {
            // Full file URL - check if it's an old container path
            if let url = URL(string: urlString) {
                let originalPath = url.path
                if FileManager.default.fileExists(atPath: originalPath) {
                    localURL = url
                } else {
                    // File doesn't exist at old path - try to find it in current container
                    // Extract the relative path from the old absolute path
                    // Example: /var/mobile/.../Library/Models/... -> Models/...
                    if let libraryRange = originalPath.range(of: "/Library/") {
                        let relativePath = String(originalPath[libraryRange.upperBound...])
                        
                        guard let currentLibraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                            throw DecodingError.dataCorrupted(DecodingError.Context(
                                codingPath: decoder.codingPath,
                                debugDescription: "Unable to access current library directory"
                            ))
                        }
                        
                        let newURL = currentLibraryURL.appendingPathComponent(relativePath)
                        
                        if FileManager.default.fileExists(atPath: newURL.path) {
                            localURL = newURL
                        } else {
                            localURL = url // Keep original URL for error reporting
                        }
                    } else {
                        localURL = url // Keep original URL
                    }
                }
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid file URL: \(urlString)"
                ))
            }
        } else if urlString.hasPrefix("/") {
            // Absolute path - check if it exists or needs migration
            let originalPath = urlString
            
            if FileManager.default.fileExists(atPath: originalPath) {
                localURL = URL(fileURLWithPath: originalPath)
            } else {
                // File doesn't exist at old path - try to find it in current container
                
                // Extract the relative path from the old absolute path
                if let libraryRange = originalPath.range(of: "/Library/") {
                    let relativePath = String(originalPath[libraryRange.upperBound...])
                    
                    guard let currentLibraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                        throw DecodingError.dataCorrupted(DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Unable to access current library directory"
                        ))
                    }
                    
                    let newURL = currentLibraryURL.appendingPathComponent(relativePath)
                    
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        localURL = newURL
                    } else {
                        // Try to find the model file in any simulator container
                        if let foundPath = Self.findModelInSimulator(filename: URL(fileURLWithPath: originalPath).lastPathComponent) {
                            localURL = foundPath
                        } else {
                            localURL = URL(fileURLWithPath: originalPath) // Keep original for error reporting
                        }
                    }
                } else {
                    localURL = URL(fileURLWithPath: originalPath) // Keep original
                }
            }
        } else {
            // Relative path - convert to absolute using Library directory
            guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unable to access library directory"
                ))
            }
            localURL = libraryURL.appendingPathComponent(urlString)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(downloadedAt, forKey: .downloadedAt)
        // Always store absolute path
        try container.encode(localURL.path, forKey: .localURL)
    }
    
    private static func findModelInSimulator(filename: String) -> URL? {
        let simulatorBasePaths = [
            "/Users/michaelgathara/Library/Developer/CoreSimulator/Devices",
            "/Users/michaelgathara/Library/Developer/Xcode/UserData/Previews/Simulator Devices"
        ]
        
        for basePath in simulatorBasePaths {
            do {
                let deviceDirs = try FileManager.default.contentsOfDirectory(atPath: basePath)
                for deviceID in deviceDirs {
                    let appsPath = "\(basePath)/\(deviceID)/data/Containers/Data/Application"
                    if FileManager.default.fileExists(atPath: appsPath) {
                        let appDirs = try FileManager.default.contentsOfDirectory(atPath: appsPath)
                        for appID in appDirs {
                            let modelsPath = "\(appsPath)/\(appID)/Library/Models"
                            if let foundURL = Self.searchForModel(in: modelsPath, filename: filename) {
                                return foundURL
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    private static func searchForModel(in directory: String, filename: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return nil }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(filename) {
                let fullPath = "\(directory)/\(file)"
                if FileManager.default.fileExists(atPath: fullPath) {
                    return URL(fileURLWithPath: fullPath)
                }
            }
        }
        return nil
    }
}

actor ManifestStore {
    private let fileURL: URL
    private var entries: [ManifestEntry] = []
    nonisolated let didChange = PassthroughSubject<Void, Never>() 

    init() throws {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = support.appendingPathComponent("models.json")
        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([ManifestEntry].self, from: data)
        }
    }

    func all() -> [ManifestEntry] { entries }

    func add(_ entry: ManifestEntry) throws {
        entries.append(entry)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        didChange.send()
    }

    func remove(id: String) throws {
        entries.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        didChange.send()                                   
    }
}
