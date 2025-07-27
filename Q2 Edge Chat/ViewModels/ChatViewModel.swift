import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let manager: ChatManager
    private var sessionBinding: Binding<ChatSession>

    var session: ChatSession {
        get { sessionBinding.wrappedValue }
        set { sessionBinding.wrappedValue = newValue }
    }

    init(manager: ChatManager, session: Binding<ChatSession>) {
        self.manager = manager
        self.sessionBinding = session
    }

    func send() async {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        
        // Validate session still exists
        guard manager.sessions.contains(where: { $0.id == session.id }) else {
            errorMessage = "Chat session no longer exists"
            return
        }
        
        let originalInput = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil
        
        do {
            await manager.send(prompt, in: session.id)
        } catch {
            // Restore input text on error and show error message
            inputText = originalInput
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func clearError() {
        errorMessage = nil
    }
}
