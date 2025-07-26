import Foundation
import Combine
import SwiftUI

@MainActor
final class ChatManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var activeID: UUID?
    @Published var isSidebarHidden = true

    private let manifest = try! ManifestStore()
    private var bag = Set<AnyCancellable>()

    // MARK: ───────── Init

    init() {
        loadSessions()

        manifest.didChange              // refresh chats if user deletes a model
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.sanitizeSessions() }
            }
            .store(in: &bag)
    }

    // MARK: ───────── CRUD

    func newChat() {
        let chat = ChatSession.empty()
        sessions.insert(chat, at: 0)
        activeID = chat.id
        saveSessions()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        saveSessions()
    }

    // MARK: ───────── Messaging

    func send(_ text: String, in id: UUID) async {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }

        sessions[idx].messages.append(.init(speaker: .user, text: text))

        var assistant = Message(speaker: .assistant, text: "")
        sessions[idx].messages.append(assistant)
        saveSessions()

        // Stubbed streaming reply
        let reply = "Stub reply for “\(text)” 🎉"
        for char in reply {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if let a = sessions[idx].messages.lastIndex(of: assistant) {
                sessions[idx].messages[a].text.append(char)
                assistant = sessions[idx].messages[a]
            }
        }
        saveSessions()
    }

    // MARK: ───────── Persistence helpers

    private func sessionsFileURL() -> URL {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("chats.json")
    }

    private func saveSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: sessionsFileURL(), options: .atomic)
        }
    }

    private func loadSessions() {
        guard
            let data = try? Data(contentsOf: sessionsFileURL()),
            let saved = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }

        sessions = saved
        activeID = sessions.first?.id
    }

    // MARK: ───────── Cleanup when models are removed

    private func sanitizeSessions() async {
        let validIDs = Set(await manifest.all().map(\.id))
        for i in sessions.indices where !validIDs.contains(sessions[i].modelID) {
            sessions[i].modelID = ""
        }
    }

    // MARK: ───────── Convenience

    var activeIndex: Int? { sessions.firstIndex { $0.id == activeID } }
}
