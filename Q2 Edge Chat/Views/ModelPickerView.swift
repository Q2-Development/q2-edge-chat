import SwiftUI
import Combine

struct ModelPickerView: View {
    @Binding var selection: String

    @State private var localModels: [ManifestEntry] = []
    @State private var store: ManifestStore?
    @State private var storeError: String?
    @State private var cancellable: AnyCancellable?

    var body: some View {
        Menu {
            ForEach(localModels, id: \.id) { entry in
                Button(entry.id) {
                    selection = entry.id
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                    .frame(maxWidth: 200, alignment: .center)
                Image(systemName: "chevron.down")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
        .onAppear {
            Task {
                do {
                    store = try ManifestStore()
                    localModels = await store?.all() ?? []
                    cancellable = store?.didChange
                        .receive(on: RunLoop.main)
                        .sink { _ in Task { localModels = await store?.all() ?? [] } }
                } catch {
                    storeError = error.localizedDescription
                }
            }
        }
        .onDisappear { cancellable?.cancel() }
    }
}
