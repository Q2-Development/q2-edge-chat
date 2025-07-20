import SwiftUI

struct FrontPageView: View {
    @State private var message = ""
    @State private var isDownloading = false

    private let quickChatModelID = "mradermacher/OpenELM-1_1B-Instruct-GGUF"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.accentColor)


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
                .background(Color.primary.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(10)

                Button(action: {
                    Task {
                        await handleQuickChat()
                    }
                }) {
                    if isDownloading {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Downloading...")
                                .padding(.leading, 8)
                        }
                    } else {
                        Text("Quick Chat")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isDownloading)
            }
            .padding(.horizontal, 40)

            Spacer()

            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .background(Color(.systemBackground))
//        .ignoresSafeArea()
    }


    private func handleQuickChat() async {
        isDownloading = true
        message = ""
        do {
            let store = try ManifestStore()
            
            if await store.all().contains(where: { $0.id == quickChatModelID }) {
                message = "\(quickChatModelID) is already available."
                isDownloading = false
                return
            }

            message = "Downloading \(quickChatModelID)..."
            let manager = ModelManager()
            
            let modelInfo = try await manager.fetchModelInfo(modelID: quickChatModelID)
            
            let fileToDownload = modelInfo.siblings.first(where: { $0.rfilename.lowercased().hasSuffix(".gguf") })
            
            guard let file = fileToDownload else {
                throw NSError(domain: "AppError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No suitable .gguf file found for the model."])
            }
            
            let downloadURLString = "https://huggingface.co/\(modelInfo.id)/resolve/main/\(file.rfilename)"
            guard let downloadURL = URL(string: downloadURLString) else {
                throw URLError(.badURL)
            }
            
            let localURL = try await manager.downloadModelFile(from: downloadURL, modelID: modelInfo.id, filename: file.rfilename)
            
            try await store.add(ManifestEntry(id: modelInfo.id, localURL: localURL, downloadedAt: Date()))
            
            message = "Successfully downloaded \(file.rfilename)!"

        } catch {
            message = "Download failed: \(error.localizedDescription)"
        }
        isDownloading = false
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
