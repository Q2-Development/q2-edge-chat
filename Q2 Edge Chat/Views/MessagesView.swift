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
    @ObservedObject var store: MessageStore
    var body: some View {
        ScrollView {
            ForEach(store.messages, id: \.self){ message in
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
