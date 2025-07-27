import Foundation
import Combine
import SwiftUI

@MainActor
final class ChatManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var activeID: UUID?
    @Published var isSidebarHidden = true

    private var engines: [URL: LlamaEngine] = [:]
    private var engineLastUsed: [URL: Date] = [:]
    private let maxCachedEngines = 3
    private let manifest: ManifestStore
    private var bag = Set<AnyCancellable>()
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        do {
            self.manifest = try ManifestStore()
        } catch {
            fatalError("Failed to initialize ManifestStore: \(error.localizedDescription). Please ensure the app has proper file system permissions.")
        }
        
        loadSessions()

        manifest.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.sanitizeSessions() }
            }
            .store(in: &bag)
    }

    func newChat() {
        let chat = ChatSession.empty()
        sessions.insert(chat, at: 0)
        activeID = chat.id
        saveSessions()
    }

    func delete(_ id: UUID) {
        // Cancel any active task for this session
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        saveSessions()
    }

    func send(_ text: String, in id: UUID) async throws {
        // Cancel any existing task for this session
        activeTasks[id]?.cancel()
        
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(.init(speaker: .user, text: text))
        var assistant = Message(speaker: .assistant, text: "")
        sessions[idx].messages.append(assistant)
        saveSessions()

        let manifestEntries = await manifest.all()
        print("🔍 CHAT DEBUG: Available models in manifest: \(manifestEntries.map(\.id))")
        print("🔍 CHAT DEBUG: Selected model ID: \(sessions[idx].modelID)")
        
        guard
            let entry = manifestEntries.first(where: { $0.id == sessions[idx].modelID })
        else {
            print("❌ CHAT DEBUG: Model not found in manifest")
            sessions[idx].messages.append(
                .init(speaker: .assistant,
                      text: "Selected model not downloaded.")
            )
            saveSessions()
            return
        }
        
        print("🔍 CHAT DEBUG: Found model entry: \(entry.id) at \(entry.localURL.path)")

        // Generate response directly without wrapping in Task that swallows errors
        do {
            print("🔍 CHAT DEBUG: About to create engine for URL: \(entry.localURL)")
            let engine = try engine(for: entry.localURL)
            print("✅ CHAT DEBUG: Engine created successfully")
            
            try await engine.generate(prompt: text) { token in
                Task { @MainActor in
                    // Validate session still exists and index is valid
                    guard idx < self.sessions.count,
                          self.sessions[idx].id == id,
                          let ai = self.sessions[idx].messages.lastIndex(of: assistant) else {
                        return
                    }
                    self.sessions[idx].messages[ai].text.append(token)
                    assistant = self.sessions[idx].messages[ai]
                }
            }
        } catch is CancellationError {
            // Handle cancellation gracefully
            guard idx < sessions.count, sessions[idx].id == id else { return }
            if let ai = sessions[idx].messages.lastIndex(of: assistant) {
                sessions[idx].messages[ai].text.append(" [Cancelled]")
            }
        } catch {
            print("❌ CHAT DEBUG: Error during generation: \(error)")
            print("❌ CHAT DEBUG: Error type: \(type(of: error))")
            
            // Validate session still exists before adding error message
            guard idx < sessions.count, sessions[idx].id == id else { return }
            sessions[idx].messages.append(.init(
                speaker: .assistant,
                text: "⚠️ \(error.localizedDescription)"
            ))
            
            // Re-throw error to propagate it to ChatViewModel
            throw error
        }
        
        saveSessions()
    }

    private func engine(for url: URL) throws -> LlamaEngine {
        if let e = engines[url] {
            engineLastUsed[url] = Date()
            return e
        }

        // Clean up old engines if we're at capacity
        if engines.count >= maxCachedEngines {
            evictOldestEngine()
        }

        // Handle iOS Simulator container path changes
        let fullURL: URL
        if url.isFileURL && url.path.hasPrefix("/") {
            // URL is already an absolute path - check if it exists
            if FileManager.default.fileExists(atPath: url.path) {
                fullURL = url
                print("🔍 DEBUG: Using existing absolute path: \(fullURL.path)")
            } else {
                // Absolute path doesn't exist, try to find the model file
                let filename = url.lastPathComponent
                if let foundURL = findActualModelFile(relativePath: "Models/\(filename)") {
                    fullURL = foundURL
                    print("🔍 DEBUG: Found model at new location: \(fullURL.path)")
                } else {
                    // Fallback to original path for error reporting
                    fullURL = url
                    print("❌ DEBUG: Model not found, using original path for error: \(fullURL.path)")
                }
            }
        } else {
            // URL is relative - try to find the actual file
            if let foundURL = findActualModelFile(relativePath: url.path) {
                fullURL = foundURL
                print("🔍 DEBUG: Found model at: \(fullURL.path)")
            } else {
                // Construct full path as fallback
                fullURL = try FileManager.default.url(
                    for: .libraryDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                ).appendingPathComponent(url.path)
                print("🔍 DEBUG: Constructed fallback path: \(fullURL.path)")
            }
        }
        
        // Add debug logging
        print("🔍 DEBUG: Attempting to load model from: \(fullURL.path)")
        print("🔍 DEBUG: File exists: \(FileManager.default.fileExists(atPath: fullURL.path))")
        
        // List parent directory contents for debugging
        let parentDir = fullURL.deletingLastPathComponent()
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: parentDir.path)
            print("🔍 DEBUG: Parent directory contents: \(contents)")
        } catch {
            print("🔍 DEBUG: Cannot list parent directory: \(error)")
        }

        let e = try LlamaEngine(modelURL: fullURL)
        engines[url] = e
        engineLastUsed[url] = Date()
        return e
    }
    
    private func evictOldestEngine() {
        guard let oldestURL = engineLastUsed.min(by: { $0.value < $1.value })?.key else {
            return
        }
        
        engines.removeValue(forKey: oldestURL)
        engineLastUsed.removeValue(forKey: oldestURL)
    }
    
    func clearAllEngines() {
        engines.removeAll()
        engineLastUsed.removeAll()
    }
    
    private func sessionsFileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("chats.json")
    }

    private func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            let url = try sessionsFileURL()
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error.localizedDescription)")
        }
    }

    private func loadSessions() {
        do {
            let url = try sessionsFileURL()
            let data = try Data(contentsOf: url)
            let saved = try JSONDecoder().decode([ChatSession].self, from: data)
            sessions = saved
            activeID = sessions.first?.id
        } catch {
            print("Failed to load sessions: \(error.localizedDescription)")
        }
    }

    private func sanitizeSessions() async {
        let validIDs = Set(await manifest.all().map(\.id))
        for i in sessions.indices where !validIDs.contains(sessions[i].modelID) {
            sessions[i].modelID = ""
        }
    }
    
    private func findActualModelFile(relativePath: String) -> URL? {
        let fm = FileManager.default
        
        // Try current app's Library directory first
        do {
            let libraryURL = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fullPath = libraryURL.appendingPathComponent(relativePath)
            if fm.fileExists(atPath: fullPath.path) {
                print("🔍 MANIFEST DEBUG: Found model at current path: \(fullPath.path)")
                return fullPath
            }
        } catch {
            print("❌ MANIFEST DEBUG: Could not get library directory: \(error)")
        }
        
        // Search for the file in other simulator containers
        let sanitizedModelName = URL(fileURLWithPath: relativePath).lastPathComponent
        print("🔍 MANIFEST DEBUG: Searching for model file: \(sanitizedModelName)")
        
        if let foundPath = findModelFileInSimulator(filename: sanitizedModelName) {
            print("✅ MANIFEST DEBUG: Found model in simulator at: \(foundPath.path)")
            return foundPath
        }
        
        print("❌ MANIFEST DEBUG: Model file not found anywhere: \(relativePath)")
        return nil
    }
    
    private func findModelFileInSimulator(filename: String) -> URL? {
        let simulatorPath = "/Users/michaelgathara/Library/Developer/CoreSimulator/Devices"
        let previewPath = "/Users/michaelgathara/Library/Developer/Xcode/UserData/Previews/Simulator Devices"
        
        for basePath in [simulatorPath, previewPath] {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: basePath)
                for deviceID in contents {
                    let searchPath = "\(basePath)/\(deviceID)/data/Containers/Data/Application"
                    if FileManager.default.fileExists(atPath: searchPath) {
                        let appContents = try FileManager.default.contentsOfDirectory(atPath: searchPath)
                        for appID in appContents {
                            let modelPath = "\(searchPath)/\(appID)/Library/Models"
                            let fullModelPath = "\(modelPath)/\(filename)"
                            if FileManager.default.fileExists(atPath: fullModelPath) {
                                return URL(fileURLWithPath: fullModelPath)
                            }
                            
                            // Also search in subdirectories
                            if FileManager.default.fileExists(atPath: modelPath) {
                                if let found = searchForModelFile(in: modelPath, filename: filename) {
                                    return found
                                }
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
    
    private func searchForModelFile(in directory: String, filename: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return nil }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(filename) || file.hasSuffix(".gguf") || file.hasSuffix(".bin") {
                let fullPath = "\(directory)/\(file)"
                if FileManager.default.fileExists(atPath: fullPath) {
                    return URL(fileURLWithPath: fullPath)
                }
            }
        }
        return nil
    }

    var activeIndex: Int? { sessions.firstIndex { $0.id == activeID } }
}
