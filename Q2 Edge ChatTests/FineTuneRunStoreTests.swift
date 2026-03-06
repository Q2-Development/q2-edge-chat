import XCTest
@testable import Q2_Edge_Chat

final class FineTuneRunStoreTests: XCTestCase {
    func testUpsertAndReloadRun() async throws {
        let filename = "run_store_\(UUID().uuidString).json"
        let store = try FineTuneRunStore(filename: filename)

        let tmpDataset = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_\(UUID().uuidString).jsonl")
        try "{\"prompt\":\"a\",\"completion\":\"b\"}".write(to: tmpDataset, atomically: true, encoding: .utf8)

        let config = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/test",
            datasetURL: tmpDataset,
            method: .lora
        )

        let record = FineTuneRunRecord(
            id: config.id,
            config: config,
            status: .running,
            startedAt: Date(),
            finishedAt: nil,
            lastProgress: nil,
            artifact: nil,
            errorMessage: nil
        )

        try await store.upsert(record)
        let runs = await store.allRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, config.id)
    }
}
