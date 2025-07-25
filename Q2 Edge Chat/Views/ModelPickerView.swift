import SwiftUI

struct ModelPickerView: View {
    @Binding var selection: String?
    let onBrowse: () -> Void

    @State private var localModels: [ManifestEntry] = []

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
                Text(selection ?? "Select Model")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
        .onAppear {
            Task {
                localModels = await (try? ManifestStore())?.all() ?? []
            }
        }
    }
}
