//
//  MainPageView.swift
//  Q2 Edge Chat
//
//  Created by AJ Nettles on 7/20/25.
//

import SwiftUI

struct ChatView: View {
    @State var chatTitle: String = "Chat Title"
    var body: some View {
        NavigationStack {
            VStack {
                MessagesView()
                InputView()
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
    @State var selectedModel = "q2-custom-2b"
    @State var prompt: String = ""
    

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
                    print("Sending prompt: \(prompt)")
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
