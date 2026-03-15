import XCTest
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXNN)
import MLXNN
#endif
#if canImport(MLXRandom)
import MLXRandom
#endif

@testable import Q2_Edge_Chat

#if canImport(MLX) && canImport(MLXLMCommon) && canImport(MLXNN)
final class ApolloOptimizerTests: XCTestCase {
    private final class TinyClassifier: Module, UnaryLayer {
        let hidden = Linear(4, 8)
        let output = Linear(8, 2)

        func callAsFunction(_ x: MLXArray) -> MLXArray {
            output(relu(hidden(x)))
        }
    }

    private func loss(model: TinyClassifier, x: MLXArray, y: MLXArray) -> MLXArray {
        crossEntropy(logits: model(x), targets: y, reduction: .mean)
    }

    private final class TinyLanguageModel: Module, LanguageModel {
        let embedding = Embedding(embeddingCount: 5, dimensions: 8)
        let output = Linear(8, 5, bias: false)

        func prepare(_ input: LMInput, cache: [KVCache], windowSize: Int?) throws -> PrepareResult {
            .tokens(input.text)
        }

        func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
            output(embedding(inputs))
        }

        func newCache(parameters: GenerateParameters?) -> [KVCache] {
            []
        }
    }

    func testApolloProjectedAdamReducesLossOnTinyFullModel() {
        #if canImport(MLXRandom)
        MLXRandom.seed(7)
        #endif

        let model = TinyClassifier()
        eval(model)

        let optimizer = ApolloProjectedAdam(learningRate: 0.05, rank: 2, projectionRefreshInterval: 10)
        let lossAndGrad = valueAndGrad(model: model, loss)

        let inputs = MLXArray([
            Float(2.0), Float(1.0), Float(0.2), Float(0.0),
            Float(1.5), Float(0.8), Float(0.1), Float(0.0),
            Float(1.8), Float(0.6), Float(0.0), Float(0.0),
            Float(1.2), Float(0.3), Float(0.2), Float(0.1),
            Float(-2.0), Float(-1.0), Float(-0.2), Float(0.0),
            Float(-1.5), Float(-0.8), Float(-0.1), Float(0.0),
            Float(-1.8), Float(-0.6), Float(0.0), Float(0.0),
            Float(-1.2), Float(-0.3), Float(-0.2), Float(-0.1),
        ]).reshaped(8, 4)
        let labels = MLXArray([Int32(1), Int32(1), Int32(1), Int32(1), Int32(0), Int32(0), Int32(0), Int32(0)])

        let initialLoss = loss(model: model, x: inputs, y: labels).item(Float.self)

        for _ in 0 ..< 60 {
            let (lossValue, grads) = lossAndGrad(model, inputs, labels)
            optimizer.update(model: model, gradients: grads)
            eval(model, optimizer, lossValue)
        }

        let finalLoss = loss(model: model, x: inputs, y: labels).item(Float.self)
        let stats = optimizer.runtimeStats()

        XCTAssertLessThan(finalLoss, initialLoss)
        XCTAssertLessThan(stats.approximateProjectedOptimizerMemoryBytes, stats.approximateFullOptimizerMemoryBytes)
    }

    func testApolloFullModelTrainerReducesLossAndSavesWeights() throws {
        #if canImport(MLXRandom)
        MLXRandom.seed(11)
        #endif

        let model = TinyLanguageModel()
        eval(model)

        let train = [
            "a b a b",
            "a b a b",
            "b a b a",
            "b a b a",
        ]
        let validate = [
            "a b a b",
            "b a b a",
        ]
        let vocabulary: [String: Int] = [
            "a": 1,
            "b": 2,
            "c": 3,
            "<eos>": 4,
        ]
        let encode: (String) -> [Int] = { text in
            text.split(separator: " ").map { vocabulary[String($0)] ?? 3 } + [4]
        }

        let initialLoss = ApolloFullModelTrain.evaluate(
            model: model,
            dataset: validate,
            batchSize: 2,
            batchCount: 1,
            encode: encode
        )

        let weightsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("apollo_weights_\(UUID().uuidString).safetensors")
        let optimizer = ApolloProjectedAdam(learningRate: 0.05, rank: 2, projectionRefreshInterval: 8)
        let params = ApolloFullModelTrain.Parameters(
            batchSize: 2,
            iterations: 40,
            stepsPerReport: 1,
            stepsPerEval: 10,
            validationBatches: 1,
            saveEvery: 20,
            weightsURL: weightsURL
        )

        var observedTrainingLosses: [Float] = []
        try ApolloFullModelTrain.train(
            model: model,
            train: train,
            validate: validate,
            optimizer: optimizer,
            encode: encode,
            parameters: params
        ) { progress in
            if case .train(_, let trainingLoss, _, _) = progress {
                observedTrainingLosses.append(trainingLoss)
            }
            return .more
        }

        let finalLoss = ApolloFullModelTrain.evaluate(
            model: model,
            dataset: validate,
            batchSize: 2,
            batchCount: 1,
            encode: encode
        )

        XCTAssertGreaterThan(observedTrainingLosses.count, 1)
        XCTAssertLessThan(finalLoss, initialLoss)
        XCTAssertTrue(FileManager.default.fileExists(atPath: weightsURL.path))
    }
}
#endif
