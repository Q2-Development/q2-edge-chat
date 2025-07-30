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
        
        // Handle different URL string formats
        let urlString = try container.decode(String.self, forKey: .localURL)
        print("🔍 MANIFEST DEBUG: Decoding URL string: '\(urlString)'")
        
        if urlString.hasPrefix("file://") {
            // Full file URL - check if it's an old container path
            if let url = URL(string: urlString) {
                let originalPath = url.path
                print("🔍 MANIFEST DEBUG: Original file URL path: \(originalPath)")
                
                // Check if the file exists at the original location
                if FileManager.default.fileExists(atPath: originalPath) {
                    localURL = url
                    print("🔍 MANIFEST DEBUG: Using existing file URL: \(localURL.path)")
                } else {
                    // File doesn't exist at old path - try to find it in current container
                    print("🔍 MANIFEST DEBUG: File not found at old path, attempting migration...")
                    
                    // Extract the relative path from the old absolute path
                    // Example: /var/mobile/.../Library/Models/... -> Models/...
                    if let libraryRange = originalPath.range(of: "/Library/") {
                        let relativePath = String(originalPath[libraryRange.upperBound...])
                        print("🔍 MANIFEST DEBUG: Extracted relative path: \(relativePath)")
                        
                        guard let currentLibraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                            throw DecodingError.dataCorrupted(DecodingError.Context(
                                codingPath: decoder.codingPath,
                                debugDescription: "Unable to access current library directory"
                            ))
                        }
                        
                        let newURL = currentLibraryURL.appendingPathComponent(relativePath)
                        print("🔍 MANIFEST DEBUG: Trying new path: \(newURL.path)")
                        
                        if FileManager.default.fileExists(atPath: newURL.path) {
                            localURL = newURL
                            print("✅ MANIFEST DEBUG: Successfully migrated to: \(localURL.path)")
                        } else {
                            print("❌ MANIFEST DEBUG: File not found at new path either")
                            localURL = url // Keep original URL for error reporting
                        }
                    } else {
                        print("❌ MANIFEST DEBUG: Could not extract relative path from: \(originalPath)")
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
            print("🔍 MANIFEST DEBUG: Original absolute path: \(originalPath)")
            
            if FileManager.default.fileExists(atPath: originalPath) {
                localURL = URL(fileURLWithPath: originalPath)
                print("🔍 MANIFEST DEBUG: Using existing absolute path: \(localURL.path)")
            } else {
                // File doesn't exist at old path - try to find it in current container
                print("🔍 MANIFEST DEBUG: File not found at old absolute path, attempting migration...")
                
                // Extract the relative path from the old absolute path
                if let libraryRange = originalPath.range(of: "/Library/") {
                    let relativePath = String(originalPath[libraryRange.upperBound...])
                    print("🔍 MANIFEST DEBUG: Extracted relative path: \(relativePath)")
                    
                    guard let currentLibraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
                        throw DecodingError.dataCorrupted(DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Unable to access current library directory"
                        ))
                    }
                    
                    let newURL = currentLibraryURL.appendingPathComponent(relativePath)
                    print("🔍 MANIFEST DEBUG: Trying new path: \(newURL.path)")
                    
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        localURL = newURL
                        print("✅ MANIFEST DEBUG: Successfully migrated to: \(localURL.path)")
                    } else {
                        // Try to find the model file in any simulator container
                        if let foundPath = Self.findModelInSimulator(filename: URL(fileURLWithPath: originalPath).lastPathComponent) {
                            localURL = foundPath
                            print("✅ MANIFEST DEBUG: Found model in different container: \(localURL.path)")
                        } else {
                            print("❌ MANIFEST DEBUG: File not found anywhere")
                            localURL = URL(fileURLWithPath: originalPath) // Keep original for error reporting
                        }
                    }
                } else {
                    print("❌ MANIFEST DEBUG: Could not extract relative path from: \(originalPath)")
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
            print("🔍 MANIFEST DEBUG: Converted relative to absolute: \(localURL.path)")
            print("🔍 MANIFEST DEBUG: Library directory: \(libraryURL.path)")
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
        didChange.send()                                   // ← NEW
    }

    func remove(id: String) throws {
        entries.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        didChange.send()                                   // ← NEW
    }
}
