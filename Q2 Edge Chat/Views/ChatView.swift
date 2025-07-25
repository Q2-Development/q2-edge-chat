import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showBrowser = false

    var body: some View {
        VStack(spacing: 0) {
            // Picker + settings toolbar
            HStack {
                ModelPickerView(selection: $vm.selectedModelID) {
                    showBrowser = true
                }
                Spacer()
                Button {
                    // later: open SettingsView
                } label: {
                    Image(systemName: "gearshape")
                        .imageScale(.large)
                }
            }
            .padding()

            Divider()

            // Messages list
            MessagesView(store: vm.messages)

            Divider()

            // Input field + send button
            HStack {
                DynamicTextEditor(text: $vm.inputText)
                    .frame(minHeight: 40, maxHeight: 120)
                    .padding(.vertical, 8)

                Button("Send") {
                    Task { await vm.send() }
                }
                .disabled(vm.isSending || vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(
            // error banner
            Group {
                if let msg = vm.errorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.red)
                        .cornerRadius(6)
                        .padding(.top, 8)
                }
            },
            alignment: .top
        )
        .sheet(isPresented: $showBrowser) {
            NavigationStack {
                ModelBrowserView()
            }
        }
    }
}
