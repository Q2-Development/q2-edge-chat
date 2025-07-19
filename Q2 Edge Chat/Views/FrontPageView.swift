import SwiftUI

struct FrontPageView: View {
    @State private var message = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            Text("Q2 Edge Chat")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text("Run AI models locally on your iPhone")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 16) {
                Button("Browse Models") {
                    message = "Browse Models tapped"
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Quick Chat") {
                    Task {
                        do {
                            let manager = ModelManager()
                            let models = try await manager.fetchModels()
                            guard
                                let model = models.first(where: { $0.id.lowercased().contains("small") || $0.id.lowercased().contains("7b") }),
                                let file = model.siblings.first(where: {
                                    $0.rfilename.hasSuffix(".gguf") ||
                                    $0.rfilename.hasSuffix(".bin")
                                }),
                                let url = URL(string: file.blobUrl)
                            else {
                                message = "No suitable model found"
                                return
                            }
                            let localURL = try await manager.downloadModelFile(from: url, modelID: model.id)
                            let store = try ManifestStore()
                            try await store.add(ManifestEntry(id: model.id, localURL: localURL, downloadedAt: Date()))
                            message = "Downloaded \(model.id)"
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)

            Spacer()

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}

struct FrontPageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FrontPageView()
                .preferredColorScheme(.light)
            FrontPageView()
                .preferredColorScheme(.dark)
        }
    }
}
