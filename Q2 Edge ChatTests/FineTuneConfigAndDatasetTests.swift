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

    func testLoadTrainingCorpusBuildsTrainAndValidateWithoutIntermediateCopies() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_training_corpus.jsonl")
        let rows = (1...25).map { idx in
            "{\"prompt\":\"Prompt \(idx)\",\"completion\":\"Completion \(idx)\"}"
        }.joined(separator: "\n") + "\n"
        try rows.write(to: tmp, atomically: true, encoding: .utf8)

        let service = DatasetIngestService()
        let config = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/test",
            datasetURL: tmp,
            method: .lora,
            steps: 12,
            sequenceLength: 128,
            microBatchSize: 1
        )

        let corpus = try service.loadTrainingCorpus(from: tmp, config: config)

        XCTAssertFalse(corpus.train.isEmpty)
        XCTAssertFalse(corpus.validate.isEmpty)
        XCTAssertEqual(corpus.totalSamples, 25)
    }

    func testLoadTrainingCorpusEnsuresValidationForTinyDataset() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_tiny_training_corpus.jsonl")
        try "{\"prompt\":\"Hi\",\"completion\":\"There\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let service = DatasetIngestService()
        let config = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/test",
            datasetURL: tmp,
            method: .lora,
            steps: 4,
            sequenceLength: 64,
            microBatchSize: 1
        )

        let corpus = try service.loadTrainingCorpus(from: tmp, config: config)

        XCTAssertFalse(corpus.train.isEmpty)
        XCTAssertFalse(corpus.validate.isEmpty)
        XCTAssertEqual(corpus.totalSamples, 1)
    }
}
