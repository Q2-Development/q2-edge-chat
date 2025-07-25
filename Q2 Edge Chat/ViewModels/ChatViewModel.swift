import Foundation

@MainActor
class ChatViewModel: ObservableObject {
    @Published var selectedModelID: String?
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?

    private let manager = ModelManager()
    private let store = try! ManifestStore()

    func send() async {
        guard let modelID = selectedModelID else {
            errorMessage = "Please select a model"
            return
        }

        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputText = ""

        // Add the user's message
        messages.append(Message(speaker: .user, text: prompt))

        isSending = true
        defer { isSending = false }

        do {
            // Ensure the model is downloaded
            let entries = await store.all()
            guard entries.contains(where: { $0.id == modelID }) else {
                errorMessage = "Model not downloaded"
                return
            }

            // Add a placeholder for the assistant's reply
            let assistantMessage = Message(speaker: .assistant, text: "")
            messages.append(assistantMessage)

            // Simulate a streaming reply (replace with real inference)
            let reply = "This is a stubbed reply from \(modelID)."
            for char in reply {
                try await Task.sleep(nanoseconds: 50_000_000)
                if let idx = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                    messages[idx].text.append(char)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
