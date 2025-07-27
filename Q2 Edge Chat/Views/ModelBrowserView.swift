import SwiftUI

struct ModelBrowserView: View {
    @StateObject private var vm = BrowseModelsViewModel()
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        List {
            if !vm.localEntries.isEmpty {
                Section("Downloaded") {
                    ForEach(vm.localEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.id)
                                    .lineLimit(1)
                                    .font(.body)
                                Text("Downloaded on \(entry.downloadedAt, formatter: dateFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
                if vm.isLoadingRemote {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if vm.remoteModels.isEmpty {
                    Text("No models available. Tap refresh to try again.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(vm.remoteModels, id: \.id) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.id)
                                    .lineLimit(1)
                                    .font(.body)
                                if vm.isDownloading(model) {
                                    Text("Downloading...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            
                            if vm.isDownloading(model) {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if vm.isDownloaded(model) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Downloaded")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button("Download") {
                                    Task { await vm.download(model) }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(vm.isDownloading(model))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: vm.isDownloading(model))
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
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(.headline)
                        Spacer()
                        Button("Dismiss") {
                            vm.clearError()
                        }
                        .font(.caption)
                    }
                    
                    Text(msg)
                        .multilineTextAlignment(.leading)
                        .font(.body)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 8)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
