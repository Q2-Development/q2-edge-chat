import Foundation
import SwiftUI

@MainActor
class BrowseModelsViewModel: ObservableObject {
    @Published var remoteModels: [HFModel] = []
    @Published var localEntries: [ManifestEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let manager = ModelManager()
    private let store = try! ManifestStore()

    func loadLocal() async {
        localEntries = await store.all()
    }

    func loadRemote() async {
        isLoading = true
        defer { isLoading = false }
        do {
            remoteModels = try await manager.fetchModels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func download(_ model: HFModel) async {
        guard let sibling = model.siblings.first(where: {
            $0.rfilename.hasSuffix(".gguf") || $0.rfilename.hasSuffix(".bin")
        }) else {
            return
        }
        let encoded = model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model.id
        let url = URL(string: "https://huggingface.co/\(encoded)/resolve/main/\(sibling.rfilename)")!
        isLoading = true
        defer { isLoading = false }
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
            try await store.add(entry)
            await loadLocal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: ManifestEntry) async {
        do {
            try await store.remove(id: entry.id)
            await loadLocal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

