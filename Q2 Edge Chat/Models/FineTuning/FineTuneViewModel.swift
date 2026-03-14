import Foundation
import SwiftUI

@MainActor
final class FineTuneViewModel: ObservableObject {
    @Published var modelIdentifier = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    @Published var datasetPath = ""
    @Published var selectedMethod: TrainingMethod = .qlora
    @Published var loraRank: Int = 4
    @Published var learningRate: Double = 0.0002
    @Published var steps: Int = 120
    @Published var sequenceLength: Int = 128
    @Published var microBatchSize: Int = 1
    @Published var projectionUpdateInterval: Int = 200
    @Published var scaleFactor: Double = 0.25

    @Published var isRunning = false
    @Published var latestProgress: FineTuneProgress?
    @Published var statusMessage: String?
    @Published var runs: [FineTuneRunRecord] = []
    @Published var lastArtifact: FineTuneArtifact?

    private let orchestrator: FineTuneOrchestrator
    private let fileManager = FileManager.default

    init(orchestrator: FineTuneOrchestrator? = nil) {
        self.orchestrator = orchestrator ?? FineTuneViewModel.makeDefaultOrchestrator()

        Task {
            await self.reloadRuns()
        }
    }

    func startTraining() {
        let path = datasetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            statusMessage = "Select a JSON/JSONL dataset file."
            return
        }

        let config = FineTuneJobConfig(
            baseModelIdentifier: modelIdentifier,
            datasetURL: URL(fileURLWithPath: path),
            method: selectedMethod,
            loraRank: loraRank,
            learningRate: learningRate,
            steps: steps,
            sequenceLength: sequenceLength,
            microBatchSize: microBatchSize,
            projectionUpdateInterval: projectionUpdateInterval,
            scaleFactor: scaleFactor
        )

        isRunning = true
        statusMessage = "Fine-tuning started"

        Task {
            do {
                let artifact = try await orchestrator.start(config: config) { [weak self] progress in
                    Task { @MainActor in
                        self?.latestProgress = progress
                        self?.statusMessage = progress.message
                    }
                }
                await MainActor.run {
                    self.lastArtifact = artifact
                    self.isRunning = false
                    self.statusMessage = "Run completed. Adapter saved."
                }
                await reloadRuns()
            } catch {
                await MainActor.run {
                    self.isRunning = false
                    self.statusMessage = error.localizedDescription
                }
                await reloadRuns()
            }
        }
    }

    func importDataset(from pickedURL: URL) {
        do {
            let copiedURL = try copyDatasetIntoAppSupport(from: pickedURL)
            datasetPath = copiedURL.path
            statusMessage = "Dataset imported: \(copiedURL.lastPathComponent)"
        } catch {
            statusMessage = "Failed to import dataset: \(error.localizedDescription)"
        }
    }

    func stopTraining() {
        Task {
            await orchestrator.stop()
            await MainActor.run {
                self.statusMessage = "Stopping current run..."
            }
        }
    }

    func reloadRuns() async {
        let records = await orchestrator.runs()
        await MainActor.run {
            self.runs = records
        }
    }

    private static func makeDefaultOrchestrator() -> FineTuneOrchestrator {
        if let store = try? FineTuneRunStore() {
            return FineTuneOrchestrator(runStore: store)
        }
        let fallbackName = "fine_tune_runs_\(UUID().uuidString).json"
        let fallbackStore = try? FineTuneRunStore(filename: fallbackName)
        return FineTuneOrchestrator(runStore: fallbackStore ?? InMemoryFallback.runStore)
    }
}

private enum InMemoryFallback {
    static let runStore: FineTuneRunStore = {
        let filename = "fine_tune_runs_ephemeral_\(UUID().uuidString).json"
        if let store = try? FineTuneRunStore(filename: filename) {
            return store
        }
        fatalError("Unable to initialize FineTuneRunStore")
    }()
}

private extension FineTuneViewModel {
    func copyDatasetIntoAppSupport(from sourceURL: URL) throws -> URL {
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
        let datasetsDir = supportDir.appendingPathComponent("FineTuneDatasets", isDirectory: true)
        try fileManager.createDirectory(at: datasetsDir, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "jsonl" : sourceURL.pathExtension
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let stamp = Int(Date().timeIntervalSince1970)
        let destinationURL = datasetsDir.appendingPathComponent("\(base)_\(stamp).\(ext)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}
