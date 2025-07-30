import SwiftUI

struct ChatWorkspaceView: View {
    @StateObject private var cm = ChatManager()

    var body: some View {
        Group {
            #if os(iOS)
            NavigationStack {
                ZStack(alignment: .leading) {
                    if let idx = cm.activeIndex {
                        ChatView(manager: cm, session: $cm.sessions[idx])
                    } else {
                        Text("No chats")
                    }

                    if !cm.isSidebarHidden {
                        ChatListView(manager: cm)
                            .frame(width: 260)
                            .transition(.move(edge: .leading))
                    }
                }
            }
            #else   // iPad / Mac
            NavigationSplitView {
                ChatListView(manager: cm)
            } detail: {
                if let idx = cm.activeIndex {
                    ChatView(manager: cm, session: $cm.sessions[idx])
                } else {
                    Text("No chats")
                }
            }
            #endif
        }
        .task {          // ⇢ runs once on first appear
            if cm.sessions.isEmpty {
                cm.newChat()        // auto-create initial session
            }
        }
    }
}
