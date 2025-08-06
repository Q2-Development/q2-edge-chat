import SwiftUI

struct ChatView: View {
    @ObservedObject var manager: ChatManager
    @Binding var session: ChatSession
    @StateObject private var vm: ChatViewModel
    @State private var showingSettings = false
    @State private var showingExport = false

    init(manager: ChatManager, session: Binding<ChatSession>) {
        self.manager = manager
        self._session = session
        self._vm = StateObject(wrappedValue: ChatViewModel(manager: manager, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat Messages Area
            MessagesView(messages: session.messages)
                .background(Color(.systemGroupedBackground))

            // Input Area
            VStack(spacing: 0) {
                Divider()
                
                HStack(alignment: .bottom, spacing: 8) {
                    // Text Input
                    DynamicTextEditor(text: $vm.inputText, placeholder: "Type a message...", maxHeight: 100)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray6))
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )
                    
                    // Send Button
                    Button(action: {
                        Task { await vm.send() }
                    }) {
                        Image(systemName: vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "arrow.up.circle" : "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                    }
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .animation(.easeInOut(duration: 0.1), value: vm.inputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { 
                        manager.isSidebarHidden.toggle() 
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.top, 25)
            }

            ToolbarItem(placement: .principal) {
                ModelPickerView(selection: $session.modelID)
                    .padding(.top, 25)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Model Settings") {
                        showingSettings = true
                    }
                    Button("Clear Chat") {
                        session.messages.removeAll()
                    }
                    Button("Export Chat") {
                        showingExport = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .padding(.top, 25)
            }
        }
        .sheet(isPresented: $showingSettings) {
            ModelSettingsView(settings: $session.modelSettings)
        }
        .sheet(isPresented: $showingExport) {
            ExportChatView(session: session)
        }
    }
}
