import Foundation

actor FineTuneRunStore {
    private let fileURL: URL
    private var cachedRuns: [FineTuneRunRecord] = []

    init(filename: String = "fine_tune_runs.json") throws {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.fileURL = supportDir.appendingPathComponent(filename)
        self.cachedRuns = try loadRunsFromDisk()
    }

    func allRuns() -> [FineTuneRunRecord] {
        cachedRuns.sorted(by: { $0.startedAt > $1.startedAt })
    }

    func upsert(_ run: FineTuneRunRecord) throws {
        if let idx = cachedRuns.firstIndex(where: { $0.id == run.id }) {
            cachedRuns[idx] = run
        } else {
            cachedRuns.append(run)
        }
        try persist()
    }

    func run(id: UUID) -> FineTuneRunRecord? {
        cachedRuns.first(where: { $0.id == id })
    }

    func adapterDirectory(for runID: UUID) throws -> URL {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = supportDir
            .appendingPathComponent("FineTuneAdapters", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(cachedRuns)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadRunsFromDisk() throws -> [FineTuneRunRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([FineTuneRunRecord].self, from: data)
    }
}
