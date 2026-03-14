import XCTest
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXNN)
import MLXNN
#endif
#if canImport(MLXRandom)
import MLXRandom
#endif

@testable import Q2_Edge_Chat

#if canImport(MLX) && canImport(MLXNN) && canImport(MLXRandom)
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

    func testApolloProjectedAdamReducesLossOnTinyFullModel() {
        MLXRandom.seed(7)

        let model = TinyClassifier()
        eval(model)

        let optimizer = ApolloProjectedAdam(learningRate: 0.05, rank: 2, projectionRefreshInterval: 10)
        let lossAndGrad = valueAndGrad(model: model, loss)

        let inputs = MLXArray(
            [
                [2.0, 1.0, 0.2, 0.0],
                [1.5, 0.8, 0.1, 0.0],
                [1.8, 0.6, 0.0, 0.0],
                [1.2, 0.3, 0.2, 0.1],
                [-2.0, -1.0, -0.2, 0.0],
                [-1.5, -0.8, -0.1, 0.0],
                [-1.8, -0.6, 0.0, 0.0],
                [-1.2, -0.3, -0.2, -0.1],
            ]
        )
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
}
#endif
