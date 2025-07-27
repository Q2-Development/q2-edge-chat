import Foundation
import SwiftUI
import Combine

@MainActor
class BrowseModelsViewModel: ObservableObject {
    @Published var remoteModels: [HFModel] = []
    @Published var localEntries: [ManifestEntry] = []
    @Published var isLoadingRemote = false
    @Published var downloadingModels: Set<String> = []
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let manager = ModelManager()
    private let store: ManifestStore
    
    init() {
        do {
            self.store = try ManifestStore()
            store.didChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in Task { await self?.loadLocal() } }
                .store(in: &cancellables)
        } catch {
            fatalError("Failed to initialize ManifestStore: \(error.localizedDescription). Please ensure the app has proper file system permissions.")
        }
    }

    func loadLocal() async {
        localEntries = await store.all()
    }

    func loadRemote() async {
        isLoadingRemote = true
        defer { isLoadingRemote = false }
        errorMessage = nil
        do {
            remoteModels = try await manager.fetchModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ model: HFModel) async {
        // Check if already downloading
        guard !downloadingModels.contains(model.id) else { return }
        
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
        
        // Mark as downloading
        downloadingModels.insert(model.id)
        errorMessage = nil
        
        defer {
            downloadingModels.remove(model.id)
        }
        
        do {
            let localURL = try await manager.downloadModelFile(
                from: url,
                modelID: model.id,
                filename: sibling.rfilename
            )
            let entry = ManifestEntry(
                id: model.id,
                localURL: localURL,
                downloadedAt: Date()
            )
            print("🔍 DOWNLOAD DEBUG: Created ManifestEntry with localURL: \(localURL.path)")
            try await store.add(entry)
            await loadLocal()
        } catch {
            errorMessage = "Failed to download \(model.id): \(error.localizedDescription)"
        }
    }
    
    func isDownloading(_ model: HFModel) -> Bool {
        return downloadingModels.contains(model.id)
    }
    
    func isDownloaded(_ model: HFModel) -> Bool {
        return localEntries.contains(where: { $0.id == model.id })
    }

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

