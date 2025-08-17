import Foundation
import SwiftUI
import Combine

@MainActor
class BrowseModelsViewModel: ObservableObject {
    @Published var localEntries: [ManifestEntry] = []
    @Published var downloadingModels: Set<String> = []
    @Published var errorMessage: String?
    
    // Search functionality
    @Published var searchText = ""
    @Published var searchResults: [HFModel] = []
    @Published var isSearching = false
    
    // Staff picks
    @Published var staffPicks = StaffPickModel.staffPicks
    
    // Model detail sheet
    @Published var selectedModelDetail: ModelDetail?
    @Published var showingModelDetail = false
    
    private var cancellables = Set<AnyCancellable>()
    let manager = ModelManager()
    private let store: ManifestStore
    private let downloader = DownloadManager.shared
    
    init() {
        do {
            self.store = try ManifestStore()
            store.didChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in Task { await self?.loadLocal() } }
                .store(in: &cancellables)
            
            // Setup search debouncing
            $searchText
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                .removeDuplicates()
                .sink { [weak self] searchText in
                    Task { await self?.performSearch(query: searchText) }
                }
                .store(in: &cancellables)
        } catch {
            fatalError("Failed to initialize ManifestStore: \(error.localizedDescription). Please ensure the app has proper file system permissions.")
        }
    }

    func loadLocal() async {
        localEntries = await store.all()
    }

    func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        errorMessage = nil
        
        do {
            searchResults = try await manager.searchModels(query: query)
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
    }
    
    func fetchModelDetail(modelId: String) async {
        do {
            selectedModelDetail = try await manager.fetchModelDetail(modelId: modelId)
            showingModelDetail = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func downloadStaffPick(_ staffPick: StaffPickModel) async {
        await fetchModelDetail(modelId: staffPick.huggingFaceId)
        if let modelDetail = selectedModelDetail, modelDetail.hasGGUF {
            await download(modelDetail.model)
        }
    }

    func download(_ model: HFModel, token: String? = nil) async {
        if downloader.isDownloading(model.id) { return }
        
        guard let sibling = model.siblings.first(where: {
            $0.rfilename.hasSuffix(".gguf") || $0.rfilename.hasSuffix(".bin")
        }) else {
            errorMessage = "No compatible model file found (.gguf or .bin required)"
            return
        }
        
        let encoded = model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model.id
        guard let url = URL(string: "https://huggingface.co/\(encoded)/resolve/main/\(sibling.rfilename)") else {
            errorMessage = "Invalid URL for model download"
            return
        }
        
        errorMessage = nil
        
        do {
            try await downloader.startHFDownload(model: model, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func isDownloading(_ model: HFModel) -> Bool { downloader.isDownloading(model.id) }
    
    func isDownloaded(_ model: HFModel) -> Bool {
        return localEntries.contains(where: { $0.id == model.id })
    }
    
    func isStaffPickDownloaded(_ staffPick: StaffPickModel) -> Bool {
        return localEntries.contains(where: { $0.id == staffPick.huggingFaceId })
    }
    
    func isStaffPickDownloading(_ staffPick: StaffPickModel) -> Bool { downloader.isDownloading(staffPick.huggingFaceId) }

    func delete(_ entry: ManifestEntry) async {
        do {
            // Remove from file system first
            let fm = FileManager.default
            if fm.fileExists(atPath: entry.localURL.path) {
                try fm.removeItem(at: entry.localURL)
            }
            
            // Then remove from manifest
            try await store.remove(id: entry.id)
            await loadLocal()
        } catch {
            errorMessage = "Failed to delete \(entry.id): \(error.localizedDescription)"
        }
    }
    
    func clearError() {
        errorMessage = nil
    }
}

