import Foundation
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(MLXNN)
import MLXNN
#endif
#if canImport(MLXOptimizers)
import MLXOptimizers
#endif

#if canImport(MLX) && canImport(MLXLMCommon) && canImport(MLXNN) && canImport(MLXOptimizers)
private struct ApolloBatchIterator: Sequence, IteratorProtocol {
    let dataset: [String]
    let batchSize: Int
    let encode: (String) -> [Int]
    let train: Bool

    var indices: [Int]
    var index = 0

    init(dataset: [String], batchSize: Int, train: Bool, encode: @escaping (String) -> [Int]) {
        self.dataset = dataset
        self.batchSize = batchSize
        self.encode = encode
        self.train = train
        self.indices = Array(0 ..< dataset.count)

        if train {
            self.indices.shuffle()
        }
    }

    mutating func next() -> (MLXArray, MLXArray, MLXArray)? {
        if index >= indices.count {
            if !train {
                return nil
            }

            indices.shuffle()
            index = 0
        }

        let endIndex = Swift.min(index + batchSize, indices.count)
        let batch = (index ..< endIndex)
            .map { encode(dataset[indices[$0]]) }
            .filter { $0.count >= 2 }
        let lengths = batch.map(\.count)
        let maxLength = lengths.max() ?? 0

        guard maxLength > 1 else {
            index = endIndex
            return next()
        }

        let batchArray = MLXArray.zeros([lengths.count, maxLength], type: Int32.self)
        for (row, (tokens, length)) in zip(batch, lengths).enumerated() {
            batchArray[row, 0 ..< length] = MLXArray(tokens.map(Int32.init))
        }

        index = endIndex
        return (batchArray[0..., .stride(to: -1)], batchArray[0..., 1...], MLXArray(lengths))
    }
}

enum ApolloFullModelTrain {
    typealias LossFunction = (Module, MLXArray, MLXArray, MLXArray) -> (MLXArray, MLXArray)

    struct Parameters: Sendable {
        var batchSize = 1
        var iterations = 20
        var stepsPerReport = 1
        var stepsPerEval = 10
        var validationBatches = 1
        var saveEvery = 20
        var weightsURL: URL?

        init(
            batchSize: Int = 1,
            iterations: Int = 20,
            stepsPerReport: Int = 1,
            stepsPerEval: Int = 10,
            validationBatches: Int = 1,
            saveEvery: Int = 20,
            weightsURL: URL? = nil
        ) {
            self.batchSize = batchSize
            self.iterations = iterations
            self.stepsPerReport = stepsPerReport
            self.stepsPerEval = stepsPerEval
            self.validationBatches = validationBatches
            self.saveEvery = saveEvery
            self.weightsURL = weightsURL
        }
    }

    enum Progress: CustomStringConvertible, Sendable {
        case train(iteration: Int, trainingLoss: Float, iterationsPerSecond: Double, tokensPerSecond: Double)
        case validation(iteration: Int, validationLoss: Float, validationTime: Double)
        case save(iteration: Int, url: URL)

        var description: String {
            switch self {
            case .train(let iteration, let trainingLoss, let iterationsPerSecond, let tokensPerSecond):
                return "Iteration \(iteration + 1): training loss \(trainingLoss.formatted()), iterations/sec \(iterationsPerSecond.formatted()), Tokens/sec \(tokensPerSecond.formatted())"
            case .validation(let iteration, let validationLoss, let validationTime):
                return "Iteration \(iteration + 1): validation loss \(validationLoss.formatted()), validation time \(validationTime.formatted())s"
            case .save(let iteration, let url):
                return "Iteration \(iteration + 1): saved weights to \(url.path())"
            }
        }
    }

    enum ProgressDisposition: Sendable {
        case stop
        case more
    }

    static func loss(model: Module, inputs: MLXArray, targets: MLXArray, lengths: MLXArray) -> (MLXArray, MLXArray) {
        let languageModel = model as! any LanguageModel
        let logits = languageModel(inputs, cache: nil).asType(.float32)
        let lengthMask = MLXArray(0 ..< inputs.dim(1))[.newAxis, 0...] .< lengths[0..., .newAxis]
        let tokenCount = lengthMask.sum()
        let ce = (crossEntropy(logits: logits, targets: targets) * lengthMask).sum() / tokenCount
        return (ce, tokenCount)
    }

    static func evaluate(
        model: Module,
        dataset: [String],
        batchSize: Int,
        batchCount: Int,
        encode: @escaping (String) -> [Int],
        loss: LossFunction = loss
    ) -> Float {
        var weightedLosses = [Float]()
        var totalTokenCount = 0

        for (iteration, (inputs, targets, lengths)) in ApolloBatchIterator(
            dataset: dataset,
            batchSize: batchSize,
            train: false,
            encode: encode
        ).enumerated() {
            let (lossValue, tokenCount) = loss(model, inputs, targets, lengths)
            weightedLosses.append((lossValue * tokenCount).item(Float.self))
            totalTokenCount += tokenCount.item(Int.self)

            if batchCount != 0 && iteration + 1 >= batchCount {
                break
            }
        }

        guard totalTokenCount > 0 else {
            return 0
        }

        return (sum(MLXArray(weightedLosses), stream: .cpu) / totalTokenCount).item(Float.self)
    }

    static func saveModelWeights(model: Module, url: URL) throws {
        let parameters = Dictionary(uniqueKeysWithValues: model.parameters().flattened())
        try save(arrays: parameters, url: url)
    }

    static func train(
        model: Module,
        train: [String],
        validate: [String],
        optimizer: Optimizer,
        encode: @escaping (String) -> [Int],
        parameters: Parameters,
        loss: @escaping LossFunction = loss,
        progress: (Progress) -> ProgressDisposition
    ) throws {
        let lossValueGrad = valueAndGrad(model: model) { model, arrays in
            let (ce, tokenCount) = loss(model, arrays[0], arrays[1], arrays[2])
            return [ce, tokenCount]
        }

        var losses = [Float]()
        var tokenCount = 0
        var start = Date.timeIntervalSinceReferenceDate

        for (iteration, (inputs, targets, lengths)) in ApolloBatchIterator(
            dataset: train,
            batchSize: parameters.batchSize,
            train: true,
            encode: encode
        ).enumerated() {
            let (resultArray, gradients) = lossValueGrad(model, [inputs, targets, lengths])
            let lossValue = resultArray[0]
            let tokens = resultArray[1]

            optimizer.update(model: model, gradients: gradients)
            eval(model, optimizer, lossValue)

            losses.append(lossValue.item(Float.self))
            tokenCount += tokens.item(Int.self)

            if (iteration + 1) % parameters.stepsPerReport == 0 {
                let trainingLoss = MLXArray(losses).mean(stream: .cpu).item(Float.self)
                let now = Date.timeIntervalSinceReferenceDate
                let iterationsPerSecond = Double(parameters.stepsPerReport) / max(now - start, 0.0001)
                let tokensPerSecond = Double(tokenCount) / max(now - start, 0.0001)

                if progress(
                    .train(
                        iteration: iteration,
                        trainingLoss: trainingLoss,
                        iterationsPerSecond: iterationsPerSecond,
                        tokensPerSecond: tokensPerSecond
                    )
                ) == .stop {
                    break
                }

                losses.removeAll()
                tokenCount = 0
                start = Date.timeIntervalSinceReferenceDate
            }

            if iteration == 0 || (iteration + 1) % parameters.stepsPerEval == 0 {
                let validationStart = Date.timeIntervalSinceReferenceDate
                let validationLoss = evaluate(
                    model: model,
                    dataset: validate,
                    batchSize: parameters.batchSize,
                    batchCount: parameters.validationBatches,
                    encode: encode,
                    loss: loss
                )
                let now = Date.timeIntervalSinceReferenceDate

                if progress(
                    .validation(
                        iteration: iteration,
                        validationLoss: validationLoss,
                        validationTime: now - validationStart
                    )
                ) == .stop {
                    break
                }

                start = Date.timeIntervalSinceReferenceDate
            }

            if let weightsURL = parameters.weightsURL, (iteration + 1) % parameters.saveEvery == 0 {
                try saveModelWeights(model: model, url: weightsURL)
                if progress(.save(iteration: iteration, url: weightsURL)) == .stop {
                    break
                }
                start = Date.timeIntervalSinceReferenceDate
            }

            if iteration + 1 >= parameters.iterations {
                break
            }
        }
    }
}
#endif
