//
//  Message.swift
//  Q2 Edge Chat
//
//  Created by AJ Nettles on 7/20/25.
//

import Foundation

enum Speaker {
    case system, assistant, user
}

class MessageStore: ObservableObject {
    @Published var messages: [Message]
    
    init (messages: [Message]) {
        self.messages = messages
    }
}

struct Message: Hashable, Identifiable {
    let id: UUID
//  let createdAt: timeOrSmth ( will actually be helpful when loading in messages, but not rn
    let speaker: Speaker
    var text: String
    init(speaker: Speaker, text: String) {
        self.speaker = speaker
        self.text = text
        self.id = UUID()
    }
    
    static func ==(lhs: Message, rhs: Message) -> Bool{
        return false
    }
}
