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
            errorMessage: nil,
            telemetry: FineTuneRunTelemetry(
                runID: config.id,
                baseModelIdentifier: config.baseModelIdentifier,
                trainingMethod: config.method,
                finalStatus: .running,
                device: FineTuneDeviceTelemetry(
                    deviceModel: "iPhone [iPhone16,2]",
                    machineIdentifier: "iPhone16,2",
                    systemName: "iOS",
                    systemVersion: "18.5",
                    operatingSystemVersionString: "Version 18.5"
                ),
                totalSamples: 12,
                trainingSampleCount: 10,
                validationSampleCount: 2,
                totalSteps: 20,
                completedSteps: 4,
                latestLoss: 1.2,
                bestLoss: 1.1,
                maxTokensPerSecond: 64,
                peakEstimatedMemoryBytes: 1234,
                peakOptimizerMemoryBytes: 4321,
                baselineOptimizerMemoryBytes: 9876,
                latestThermalState: .nominal,
                errorMessage: nil,
                startedAt: Date(),
                finishedAt: nil
            )
        )

        try await store.upsert(record)
        let runs = await store.allRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, config.id)
        XCTAssertEqual(runs[0].telemetry?.device.machineIdentifier, "iPhone16,2")

        let reloaded = try FineTuneRunStore(filename: filename)
        let reloadedRuns = await reloaded.allRuns()
        XCTAssertEqual(reloadedRuns.count, 1)
        XCTAssertEqual(reloadedRuns[0].telemetry?.completedSteps, 4)
    }
}
