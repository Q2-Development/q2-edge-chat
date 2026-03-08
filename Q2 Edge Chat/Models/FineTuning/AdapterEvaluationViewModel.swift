import Foundation

@MainActor
final class AdapterEvaluationViewModel: ObservableObject {
    @Published var modelIdentifier = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    @Published var adapterPath = ""
    @Published var prompt = ""
    @Published var maxTokens = 128
    @Published var temperature = 0.2

    @Published var isRunning = false
    @Published var statusMessage: String?
    @Published var baseOutput = ""
    @Published var adaptedOutput = ""

    private let service = AdapterEvaluationService()
    private let fileManager = FileManager.default

    func runComparison() {
        let adapter = adapterPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !adapter.isEmpty else {
            statusMessage = "Choose an adapter .safetensors file."
            return
        }

        isRunning = true
        statusMessage = "Running base model..."
        baseOutput = ""
        adaptedOutput = ""

        Task {
            do {
                let result = try await service.compare(
                    modelIdentifier: modelIdentifier,
                    adapterURL: URL(fileURLWithPath: adapter),
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: Float(temperature)
                )
                await MainActor.run {
                    baseOutput = result.baseOutput
                    adaptedOutput = result.adaptedOutput
                    statusMessage = "Comparison complete."
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }

    func importAdapter(from pickedURL: URL) {
        do {
            let localURL = try copyAdapterIntoAppSupport(from: pickedURL)
            adapterPath = localURL.path
            statusMessage = "Adapter imported: \(localURL.lastPathComponent)"
        } catch {
            statusMessage = "Failed to import adapter: \(error.localizedDescription)"
        }
    }
}

private extension AdapterEvaluationViewModel {
    func copyAdapterIntoAppSupport(from sourceURL: URL) throws -> URL {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let supportDir = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let adaptersDir = supportDir.appendingPathComponent("FineTuneAdaptersImported", isDirectory: true)
        try fileManager.createDirectory(at: adaptersDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "safetensors" : sourceURL.pathExtension
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        let adapterDir = adaptersDir.appendingPathComponent("\(base)_\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: adapterDir, withIntermediateDirectories: true)
        let destination = adapterDir.appendingPathComponent("\(base).\(ext)")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        let siblingConfig = sourceURL.deletingLastPathComponent().appendingPathComponent("adapter_config.json")
        if fileManager.fileExists(atPath: siblingConfig.path) {
            let copiedConfig = adapterDir.appendingPathComponent("adapter_config.json")
            if fileManager.fileExists(atPath: copiedConfig.path) {
                try fileManager.removeItem(at: copiedConfig)
            }
            try fileManager.copyItem(at: siblingConfig, to: copiedConfig)
        }

        return destination
    }
}
