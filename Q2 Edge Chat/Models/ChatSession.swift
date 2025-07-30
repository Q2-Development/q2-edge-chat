import Foundation

struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modelID: String
    var messages: [Message]

    static func empty() -> ChatSession {
        ChatSession(
            id: UUID(),
            title: "New Chat",
            createdAt: Date(),
            modelID: "",
            messages: []
        )
    }
}
