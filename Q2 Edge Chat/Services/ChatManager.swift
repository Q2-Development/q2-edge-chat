import Foundation
import Combine

@MainActor
final class ChatManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var activeID: UUID?
    @Published var isSidebarHidden: Bool = true

    private let manifest = try! ManifestStore()
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadSessions()
        manifest.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sanitizeSessions()
            }
            .store(in: &cancellables)
    }

    // MARK: CRUD

    func newChat() {
        let session = ChatSession.empty(defaultModelID: manifest.all().first?.id)
        sessions.insert(session, at: 0)
        activeID = session.id
        saveSessions()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        saveSessions()
    }

    // MARK: Send

    func send(_ text: String, in id: UUID) async {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages.append(Message(role: .user, text: text))

        // placeholder assistant reply
        var assistant = Message(role: .assistant, text: "")
        sessions[idx].messages.append(assistant)
        saveSessions()

        let reply = "Stub reply for '\(text)' 🎉"
        for char in reply {
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard let a = sessions[idx].messages.lastIndex(of: assistant) else { continue }
            sessions[idx].messages[a].text.append(char)
            assistant = sessions[idx].messages[a]
        }
        saveSessions()
    }

    // MARK: Persistence (simple JSON)

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
        let data = try? JSONEncoder().encode(sessions)
        try? data?.write(to: sessionsFileURL(), options: .atomic)
    }

    private func loadSessions() {
        guard
            let data = try? Data(contentsOf: sessionsFileURL()),
            let saved = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }
        sessions = saved
        activeID = sessions.first?.id
    }

    private func sanitizeSessions() {
        let validModelIDs = Set(manifest.all().map(\.id))
        for i in sessions.indices {
            if !validModelIDs.contains(sessions[i].modelID) {
                sessions[i].modelID = ""
            }
        }
    }

    // Helpers
    var activeIndex: Int? { sessions.firstIndex { $0.id == activeID } }
}
