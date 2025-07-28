import SwiftUI

struct ModelDetailRow: View {
    let model: HFModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }
    
    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.id)
                        .font(.headline)
                        .lineLimit(2)
                    
                    if let author = model.author {
                        Text("by \(author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let likes = model.likes {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("\(likes)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let downloads = model.downloads {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("\(downloads)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if let pipelineTag = model.pipelineTag {
                HStack {
                    Text(pipelineTag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    if let libraryName = model.libraryName {
                        Text(libraryName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                }
            }
            
            if let tags = model.tags, !tags.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 4) {
                    ForEach(Array(tags.prefix(6)), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                    
                    if tags.count > 6 {
                        Text("+\(tags.count - 6)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)
                    }
                }
            }
            
            HStack {
                if let lastModified = model.lastModified, let date = parseDate(lastModified) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updated")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(relativeFormatter.localizedString(for: date, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if isDownloaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Download") {
                        onDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isDownloading)
    }
}

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
                        ModelDetailRow(
                            model: model,
                            isDownloaded: vm.isDownloaded(model),
                            isDownloading: vm.isDownloading(model)
                        ) {
                            Task { await vm.download(model) }
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
