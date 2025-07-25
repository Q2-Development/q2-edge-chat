import SwiftUI

struct ChatListView: View {
    @ObservedObject var manager: ChatManager

    var body: some View {
        List {
            Button {
                manager.newChat()
                manager.isSidebarHidden = true
            } label: {
                Label("New Chat", systemImage: "plus")
            }

            ForEach(manager.sessions) { session in
                Button {
                    manager.activeID = session.id
                    manager.isSidebarHidden = true
                } label: {
                    Text(session.title)
                        .lineLimit(1)
                        .foregroundColor(manager.activeID == session.id ? .accentColor : .primary)
                }
            }
            .onDelete { indexSet in
                indexSet.map { manager.sessions[$0].id }.forEach(manager.delete)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
    }
}
