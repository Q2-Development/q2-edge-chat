import Foundation

struct Message: Identifiable, Codable, Hashable {
    enum Speaker: String, Codable {
        case user, assistant
    }

    let id: UUID
    var speaker: Speaker
    var text: String
    var timestamp: Date

    init(id: UUID = UUID(),
         speaker: Speaker,
         text: String,
         timestamp: Date = Date()) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}
