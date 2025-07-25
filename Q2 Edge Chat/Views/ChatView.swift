import SwiftUI

struct ChatView: View {
    @ObservedObject var manager: ChatManager
    @Binding var session: ChatSession
    @StateObject private var vm: ChatViewModel

    init(manager: ChatManager, session: Binding<ChatSession>) {
        self.manager = manager
        self._session = session
        self._vm = StateObject(wrappedValue: ChatViewModel(manager: manager, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ModelPickerView(selection: $session.modelID) {
                    manager.isSidebarHidden = false
                }
                Spacer()
                Image(systemName: "gearshape") // placeholder
            }
            .padding()

            Divider()

            MessagesView(messages: session.messages)

            Divider()

            HStack {
                DynamicTextEditor(text: $vm.inputText)
                    .frame(minHeight: 40, maxHeight: 120)
                Button("Send") { Task { await vm.send() } }
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
