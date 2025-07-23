//
//  MainPageView.swift
//  Q2 Edge Chat
//
//  Created by AJ Nettles on 7/20/25.
//

import SwiftUI
import LLamaSwift

struct ChatView: View {
    @State var chatTitle: String = "Chat Title"
    @StateObject var store : MessageStore = MessageStore(messages: [
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
    ])
    var body: some View {
        NavigationStack {
            VStack {
                MessagesView(store: store)
                InputView(store: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {

                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text(chatTitle)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }
}



#Preview {
    ChatView()
}


struct InputView: View {
    private let SYMBOL_SIZE_LENGTH: CGFloat = 25
    @State var selectedModel = "bartowski/Llama-3.2-1B-Instruct-GGUF"
    @State var prompt: String = ""
    @ObservedObject var store: MessageStore
    

    var body: some View {
        VStack {
            Divider()

// Original Text Editor design in mind, assume intensity of 2
//                TextEditor(text: $prompt)
//                    .frame(minHeight: 50)
//                    .clipShape(.rect(cornerSize: CGSize(width: 5, height: 0)))
//                    .shadow(radius: CGFloat(SHADOW_INTENSITY), y: -CGFloat(SHADOW_INTENSITY * 2))
            DynamicTextEditor(text: $prompt, placeholder: "Ask anything", maxHeight: 200, maxHeightCompact: 50)
                
            HStack {
                Button {
                    print("Uploading file or something")
                } label: {
                    Image(systemName: "plus.circle")
                        .resizable()
                        .frame(maxWidth: SYMBOL_SIZE_LENGTH, maxHeight: SYMBOL_SIZE_LENGTH)
                        .aspectRatio(contentMode: .fit)
                }
                
                Spacer()
                
                Text(selectedModel)
                
                Spacer()
                
                Button  {
                    do {
                        Task {
                            print("Sending prompt: \(prompt)")
                            store.messages.append(Message(speaker: .user, text: prompt))
                            
                            print("cleared prompt")
                            let llamaPrompt = prompt
                            prompt = ""
                            var response = ""
                            
                            print("loaded store")
                            let modelStore = try ManifestStore()
                            if let downloadedModel = await modelStore.first() {
                                let model = try Model(modelPath: downloadedModel.url().path() )
                                let llama = LLama(model: model)
                                
                                // Results are delivered through an `AsyncStream`
                                store.messages.append(Message(speaker: .assistant, text: response))
                                for try await token in await llama.infer(prompt: llamaPrompt, maxTokens: 1024) {
                                    print(token, terminator: "")
                                    response += token
                                    store.messages[store.messages.count-1].text = response
                                }
                            }else {
                                print("models not downloaded")
                                let entry = await modelStore.download(quickChatModelID: selectedModel)
                                let model = try Model(modelPath: (entry?.url().path())!)
                                let llama = LLama(model: model)
                                
                                // Results are delivered through an `AsyncStream`
                                store.messages.append(Message(speaker: .assistant, text: response))
                                for try await token in await llama.infer(prompt: llamaPrompt, maxTokens: 1024) {
                                    print(token, terminator: "")
                                    response += token
                                    store.messages[store.messages.count-1].text = response
                                }
                            }

                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle")
                        .resizable()
                        .frame(maxWidth: SYMBOL_SIZE_LENGTH, maxHeight: SYMBOL_SIZE_LENGTH)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
//
