import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search HuggingFace models...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    isSearching = true
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct SearchResultRow: View {
    let model: HFModel
    let hasGGUF: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.id)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    if let author = model.author {
                        Text("by \(author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        if let pipelineTag = model.pipelineTag {
                            Text(pipelineTag)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        
                        if hasGGUF {
                            Text("GGUF")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
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
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StaffPickCard: View {
    let staffPick: StaffPickModel
    let isDownloaded: Bool
    let isDownloading: Bool
    let onTap: () -> Void
    let onDownload: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(staffPick.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        
                        Text(staffPick.parameterCount)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    if isDownloading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    }
                }
                
                Text(staffPick.specialty)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(staffPick.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if !isDownloaded && !isDownloading {
                    HStack {
                        Spacer()
                        Button("Download") {
                            onDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .onTapGesture {
                            
                        }
                        Spacer()
                    }
                }
            }
            .padding()
            .frame(height: 180)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModelDetailView: View {
    let modelDetail: ModelDetail
    let isDownloaded: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Header with close and download buttons
                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    
                    Spacer()
                    
                    if modelDetail.hasGGUF {
                        if isDownloading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Downloading...")
                                    .font(.caption)
                            }
                        } else if isDownloaded {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Downloaded")
                                    .font(.caption)
                            }
                        } else {
                            Button("Download") {
                                onDownload()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(modelDetail.model.id)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                if let author = modelDetail.model.author {
                                    Text("by \(author)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        // Stats
                        HStack(spacing: 16) {
                            if let likes = modelDetail.model.likes {
                                HStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(.red)
                                    Text("\(likes)")
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let downloads = modelDetail.model.downloads {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("\(downloads)")
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if let lastModified = modelDetail.model.lastModified,
                               let date = ISO8601DateFormatter().date(from: lastModified) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .foregroundColor(.secondary)
                                    Text(relativeFormatter.localizedString(for: date, relativeTo: Date()))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .font(.caption)
                        
                        // Tags
                        HStack {
                            if let pipelineTag = modelDetail.model.pipelineTag {
                                Text(pipelineTag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(6)
                            }
                            
                            if let libraryName = modelDetail.model.libraryName {
                                Text(libraryName)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundColor(.green)
                                    .cornerRadius(6)
                            }
                            
                            if modelDetail.hasGGUF {
                                Text("GGUF Available")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // README Content
                    if let readme = modelDetail.readme, !readme.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model Card")
                                .font(.headline)
                            
                            MarkdownText(markdown: readme)
                        }
                    }
                    
                    Divider()
                    
                    // Files Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Files")
                            .font(.headline)
                        
                        if modelDetail.hasGGUF {
                            Text("GGUF Files (Compatible)")
                                .font(.subheadline)
                                .foregroundColor(.green)
                            
                            ForEach(modelDetail.ggufFiles, id: \.rfilename) { file in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.green)
                                    Text(file.rfilename)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            Text("No GGUF files available for download")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("Model Details")
        .navigationBarTitleDisplayMode(.inline)
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
        ScrollView {
            VStack(spacing: 20) {
                // Downloaded Models Section
                if !vm.localEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Downloaded Models")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        
                        LazyVStack(spacing: 8) {
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
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Staff Picks Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Staff Picks")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    Text("Curated small models (1-3B parameters) optimized for performance")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(vm.staffPicks, id: \.huggingFaceId) { staffPick in
                            StaffPickCard(
                                staffPick: staffPick,
                                isDownloaded: vm.isStaffPickDownloaded(staffPick),
                                isDownloading: vm.isStaffPickDownloading(staffPick),
                                onTap: {
                                    Task { await vm.fetchModelDetail(modelId: staffPick.huggingFaceId) }
                                },
                                onDownload: {
                                    Task { await vm.downloadStaffPick(staffPick) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Search Section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Models")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        
                        SearchBar(
                            searchText: $vm.searchText,
                            isSearching: $vm.isSearching,
                            onClear: vm.clearSearch
                        )
                    }
                    .padding(.horizontal)
                    
                    if !vm.searchResults.isEmpty {
                        LazyVStack(spacing: 1) {
                            ForEach(vm.searchResults, id: \.id) { model in
                                SearchResultRow(
                                    model: model,
                                    hasGGUF: vm.manager.checkGGUFFiles(model: model).hasGGUF,
                                    onTap: {
                                        Task { await vm.fetchModelDetail(modelId: model.id) }
                                    }
                                )
                                .padding(.horizontal)
                                
                                if model.id != vm.searchResults.last?.id {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    } else if !vm.searchText.isEmpty && !vm.isSearching {
                        Text("No models found for '\(vm.searchText)'")
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Models")
        .onAppear {
            Task { await vm.loadLocal() }
        }
        .sheet(isPresented: $vm.showingModelDetail) {
            if let modelDetail = vm.selectedModelDetail {
                ModelDetailView(
                    modelDetail: modelDetail,
                    isDownloaded: vm.isDownloaded(modelDetail.model),
                    isDownloading: vm.isDownloading(modelDetail.model),
                    onDownload: {
                        Task { await vm.download(modelDetail.model) }
                    }
                )
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
