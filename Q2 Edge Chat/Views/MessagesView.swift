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
    let messages: [Message]
    var body: some View {
        ScrollView {
            LazyVStack { ForEach(messages) { MessageRow(message:$0) } }
        }
    }
}

