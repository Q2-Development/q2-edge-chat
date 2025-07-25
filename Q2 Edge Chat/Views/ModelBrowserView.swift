import SwiftUI

struct ModelBrowserView: View {
    @StateObject private var vm = BrowseModelsViewModel()

    var body: some View {
        List {
            if !vm.localEntries.isEmpty {
                Section("Downloaded") {
                    ForEach(vm.localEntries) { entry in
                        HStack {
                            Text(entry.id)
                                .lineLimit(1)
                            Spacer()
                            Button("Delete") {
                                Task { await vm.delete(entry) }
                            }
                            .foregroundColor(.red)
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
            }

            Section("Available") {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(vm.remoteModels, id: \.id) { model in
                        HStack {
                            Text(model.id)
                                .lineLimit(1)
                            Spacer()
                            if vm.localEntries.contains(where: { $0.id == model.id }) {
                                Text("Downloaded")
                                    .foregroundColor(.secondary)
                            } else {
                                Button("Download") {
                                    Task { await vm.download(model) }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await vm.loadRemote() } }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            Task {
                await vm.loadLocal()
                await vm.loadRemote()
            }
        }
        .overlay {
            if let msg = vm.errorMessage {
                Text(msg)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.systemBackground).opacity(0.9))
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .padding()
            }
        }
    }
}
