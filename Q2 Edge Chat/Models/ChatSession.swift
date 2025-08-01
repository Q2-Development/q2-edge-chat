import Foundation

struct ModelSettings: Codable, Hashable {
    var temperature: Float = 0.7
    var maxTokens: Int32 = 120
    var topP: Float = 0.9
    var topK: Int32 = 40
    var repeatPenalty: Float = 1.1
    var systemPrompt: String = ""
    
    static let `default` = ModelSettings()
}

struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var modelID: String
    var messages: [Message]
    var modelSettings: ModelSettings = .default

    static func empty() -> ChatSession {
        ChatSession(
            id: UUID(),
            title: "New Chat",
            createdAt: Date(),
            modelID: "",
            messages: [],
            modelSettings: .default
        )
    }
}
