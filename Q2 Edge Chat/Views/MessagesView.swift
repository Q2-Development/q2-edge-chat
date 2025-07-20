//
//  MessagesView.swift
//  Q2 Edge Chat
//
//  Created by AJ Nettles on 7/20/25.
//
import SwiftUI

struct MessageView: View {
    var message: Message
    var body: some View {
        Text(message.text)
            .padding()
            .background(message.speaker == Speaker.assistant ? Color.gray : Color.blue)
            .foregroundStyle(message.speaker == Speaker.assistant ? Color.black : Color.white)
            .clipShape(.rect(cornerRadius: 10))
    }
}


struct MessagesView: View {
    @State var messages: [Message] = [
        Message(speaker: Speaker.user, text: "This is a very long paragraph that will for sure continue to keep going until it will now longer update in a defined way and go off the page"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.assistant, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.assistant, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.assistant, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.user, text: "test"),
        Message(speaker: Speaker.assistant, text: "testy")
    ]
    var body: some View {
        ScrollView {
            ForEach(messages, id: \.self){ message in
                if (message.speaker == Speaker.user) {
                    HStack {
                        Spacer()
                        MessageView(message: message)
                    }
                }else {
                    HStack {
                        MessageView(message: message)
                        Spacer()
                    }
                }
            }
        }
        .contentMargins(10, for: .scrollContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
