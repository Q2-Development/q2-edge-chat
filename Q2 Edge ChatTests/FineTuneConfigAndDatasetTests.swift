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

    func testConfigValidationRejectsNonQuantizedRemoteModelForQLoRA() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset_quantized_guard.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/Qwen2.5-0.5B-Instruct",
            datasetURL: tmp,
            method: .qlora
        )

        XCTAssertThrowsError(try cfg.validated())
    }

    func testConfigValidationAllowsLocalModelPathForQLoRA() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset_local_qlora.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "/private/var/mobile/Containers/Data/Application/local-mlx-model",
            datasetURL: tmp,
            method: .qlora
        )

        XCTAssertNoThrow(try cfg.validated())
    }

    func testConfigValidationRejectsQuantizedRemoteModelForApollo() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset_apollo_quantized_guard.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            datasetURL: tmp,
            method: .apollo
        )

        XCTAssertThrowsError(try cfg.validated())
    }

    func testConfigValidationRejectsQuantizedLocalModelForApollo() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset_apollo_quantized_local_guard.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "/private/var/mobile/Containers/Data/Application/tiny-model-4bit",
            datasetURL: tmp,
            method: .apollo
        )

        XCTAssertThrowsError(try cfg.validated())
    }

    func testConfigValidationRejectsOversizedApolloModel() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("unit_dataset_apollo_model_size.jsonl")
        try "{\"prompt\":\"hi\",\"completion\":\"there\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let cfg = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct",
            datasetURL: tmp,
            method: .apollo
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

    func testMemorySafetyPolicyClampsRiskySettings() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_policy.jsonl")
        try "{\"prompt\":\"A\",\"completion\":\"B\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let config = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            datasetURL: tmp,
            method: .qlora,
            loraRank: 32,
            learningRate: 0.0002,
            steps: 120,
            sequenceLength: 512,
            microBatchSize: 4
        )

        let adjusted = config.applyingMemorySafetyPolicy()

        XCTAssertEqual(adjusted.config.microBatchSize, 1)
        XCTAssertEqual(adjusted.config.loraRank, 8)
        XCTAssertEqual(adjusted.config.sequenceLength, 128)
        XCTAssertFalse(adjusted.notes.isEmpty)
    }

    func testMemorySafetyPolicyClampsApolloSettings() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_apollo_policy.jsonl")
        try "{\"prompt\":\"A\",\"completion\":\"B\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let config = FineTuneJobConfig(
            baseModelIdentifier: "/private/var/mobile/local-tiny-model",
            datasetURL: tmp,
            method: .apollo,
            loraRank: 12,
            learningRate: 0.0002,
            steps: 40,
            sequenceLength: 256,
            microBatchSize: 4,
            projectionUpdateInterval: 50
        )

        let adjusted = config.applyingMemorySafetyPolicy()

        XCTAssertEqual(adjusted.config.microBatchSize, 1)
        XCTAssertEqual(adjusted.config.loraRank, 4)
        XCTAssertEqual(adjusted.config.sequenceLength, 64)
    }

    func testEstimatedModelBillionsParsesIdentifier() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dataset_model_parse.jsonl")
        try "{\"prompt\":\"A\",\"completion\":\"B\"}\n".write(to: tmp, atomically: true, encoding: .utf8)

        let config = FineTuneJobConfig(
            baseModelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            datasetURL: tmp,
            method: .lora
        )

        let estimated = try XCTUnwrap(config.estimatedModelBillions())
        XCTAssertEqual(estimated, 1.5, accuracy: 0.001)
    }
}
