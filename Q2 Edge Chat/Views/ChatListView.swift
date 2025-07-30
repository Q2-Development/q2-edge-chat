import SwiftUI

struct ChatListView: View {
    @ObservedObject var manager: ChatManager
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chats")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    manager.newChat()
                    manager.isSidebarHidden = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
            
            Divider()
            
            // Chat List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(manager.sessions) { session in
                        ChatListItem(
                            session: session,
                            isActive: manager.activeID == session.id,
                            onTap: {
                                manager.activeID = session.id
                                manager.isSidebarHidden = true
                            },
                            onDelete: {
                                manager.delete(session.id)
                            }
                        )
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            
            Divider()
            
            // Footer with models button
            HStack {
                NavigationLink(destination: ModelBrowserView()) {
                    Label("Browse Models", systemImage: "brain.head.profile")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .navigationBarHidden(true)
    }
}

struct ChatListItem: View {
    let session: ChatSession
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteAlert = false
    
    private var previewText: String {
        if let lastMessage = session.messages.last {
            return lastMessage.text
        }
        return "New conversation"
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(isActive ? .accentColor : .primary)
                    
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Menu {
                        Button("Delete", role: .destructive) {
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .alert("Delete Chat", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this chat? This action cannot be undone.")
        }
    }
}
