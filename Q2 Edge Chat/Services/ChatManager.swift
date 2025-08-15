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
    private var activeTasks: [UUID: Task<Void, Error>] = [:]

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

    func cancel(_ id: UUID) {
        activeTasks[id]?.cancel()
    }

    func persistSessions() {
        saveSessions()
    }

    func isGenerating(_ id: UUID) -> Bool {
        return activeTasks[id] != nil
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
        activeTasks[id]?.cancel()
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(.init(speaker: .user, text: text))
        var assistant = Message(speaker: .assistant, text: "")
        sessions[idx].messages.append(assistant)
        saveSessions()

        let manifestEntries = await manifest.all()
        guard let entry = manifestEntries.first(where: { $0.id == sessions[idx].modelID }) else {
            sessions[idx].messages.append(.init(speaker: .assistant, text: "Selected model not downloaded."))
            saveSessions()
            return
        }

        let engine = try engine(for: entry.localURL)
        let prompt = buildConversationPrompt(for: sessions[idx].messages.dropLast())

        let task = Task<Void, Error> {
            do {
                try await engine.generate(prompt: prompt, settings: self.sessions[idx].modelSettings) { token in
                    Task { @MainActor in
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
                await MainActor.run {
                    guard idx < self.sessions.count, self.sessions[idx].id == id else { return }
                    if let ai = self.sessions[idx].messages.lastIndex(of: assistant) {
                        self.sessions[idx].messages[ai].text.append(" [Cancelled]")
                    }
                }
            } catch {
                await MainActor.run {
                    guard idx < self.sessions.count, self.sessions[idx].id == id else { return }
                    self.sessions[idx].messages.append(.init(speaker: .assistant, text: "⚠️ \(error.localizedDescription)"))
                }
                throw error
            }
        }

        activeTasks[id] = task
        defer { activeTasks.removeValue(forKey: id) }
        try await task.value
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

        let e = try LlamaEngine(modelURL: url)
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
        saveSessions()
    }
    

    var activeIndex: Int? { sessions.firstIndex { $0.id == activeID } }
}

extension ChatManager {
    private func buildConversationPrompt(for messages: ArraySlice<Message>) -> String {
        var parts: [String] = []
        for message in messages.suffix(20) {
            switch message.speaker {
            case .user:
                parts.append("User: \(message.text)")
            case .assistant:
                parts.append("Assistant: \(message.text)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
