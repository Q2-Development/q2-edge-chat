import XCTest
@testable import Q2_Edge_Chat

final class FineTuneConfigAndDatasetTests: XCTestCase {
    func testConfigValidationRejectsInvalidScaleFactorForGaLore() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/test",
            datasetURL: tmp,
            method: .galore,
            scaleFactor: 1.5
        )

        XCTAssertThrowsError(try cfg.validated())
    }

    func testDatasetIngestParsesJSONLPromptCompletion() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_jsonl.jsonl")
        let text = "{\"prompt\":\"A\",\"completion\":\"B\"}\n{\"instruction\":\"X\",\"output\":\"Y\"}\n"
        try text.write(to: tmp, atomically: true, encoding: .utf8)

        let service = DatasetIngestService()
        let samples = try service.loadSamples(from: tmp)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].prompt, "A")
        XCTAssertEqual(samples[0].completion, "B")
    }
}
