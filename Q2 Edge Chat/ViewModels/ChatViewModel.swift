import Foundation
import Combine
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
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
        inputText = ""
        await manager.send(prompt, in: session.id)
    }
}
