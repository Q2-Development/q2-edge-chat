import SwiftUI

struct MessagesView: View {
    let messages: [Message]
    var dismissKeyboard: () -> Void = {}

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 8) {
                                Text("Ready to Chat")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("Start a conversation with your AI assistant")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        ForEach(messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        
                        // Invisible anchor for auto-scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(.vertical, 16)
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        // Dismiss keyboard as soon as user starts scrolling
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.5)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
