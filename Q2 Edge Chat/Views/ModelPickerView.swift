import SwiftUI
import Combine

struct ModelPickerView: View {
    @Binding var selection: String

    @State private var localModels: [ManifestEntry] = []
    @State private var store: ManifestStore?
    @State private var storeError: String?
    @State private var cancellable: AnyCancellable?
    
    private var selectedModel: ManifestEntry? {
        localModels.first { $0.id == selection }
    }
    
    private var displayName: String {
        if let model = selectedModel {
            let components = model.id.split(separator: "/")
            if components.count >= 2 {
                return String(components[1]).replacingOccurrences(of: "-", with: " ")
            }
            return model.id
        }
        return selection.isEmpty ? "Select Model" : selection
    }

    var body: some View {
        Menu {
            if localModels.isEmpty {
                Text("No models available")
                    .foregroundColor(.secondary)
            } else {
                ForEach(localModels, id: \.id) { entry in
                    Button(action: {
                        selection = entry.id
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatModelName(entry.id))
                                .font(.headline)
                            Text(formatAuthor(entry.id))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                NavigationLink(destination: ModelBrowserView()) {
                    Label("Browse More Models", systemImage: "plus.circle")
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.primary)
                    
                    if let model = selectedModel {
                        Text(formatAuthor(model.id))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: 180, alignment: .leading)
                
                Spacer()
                
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
                    .stroke(Color(.systemGray4), lineWidth: 0.5)
            )
        }
        .disabled(localModels.isEmpty)
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
    
    private func formatModelName(_ id: String) -> String {
        let components = id.split(separator: "/")
        if components.count >= 2 {
            return String(components[1])
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }
        return id
    }
    
    private func formatAuthor(_ id: String) -> String {
        let components = id.split(separator: "/")
        if components.count >= 2 {
            return "by \(components[0])"
        }
        return ""
    }
}
