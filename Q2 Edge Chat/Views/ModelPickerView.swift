import SwiftUI
import Combine

struct ModelPickerView: View {
    @Binding var selection: String
    let onBrowse: () -> Void

    @State private var localModels: [ManifestEntry] = []
    private let store = try! ManifestStore()
    @State private var cancellable: AnyCancellable?

    var body: some View {
        Menu {
            ForEach(localModels, id: \.id) { entry in
                Button(entry.id) {
                    selection = entry.id
                }
            }
            Divider()
            Button("Browse Models…") {
                onBrowse()
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
            Task { localModels = await store.all() }
            cancellable = store.didChange
                .receive(on: RunLoop.main)
                .sink { _ in Task { localModels = await store.all() } }
        }
        .onDisappear { cancellable?.cancel() }
    }
}
