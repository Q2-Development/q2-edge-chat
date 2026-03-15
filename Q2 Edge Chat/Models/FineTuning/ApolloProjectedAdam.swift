import Foundation
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXNN)
import MLXNN
#endif
#if canImport(MLXOptimizers)
import MLXOptimizers
#endif

#if canImport(MLX) && canImport(MLXNN) && canImport(MLXOptimizers)
struct ApolloRuntimeStats: Sendable {
    let approximateProjectedOptimizerMemoryBytes: UInt64
    let approximateFullOptimizerMemoryBytes: UInt64
    let projectionRefreshed: Bool
}

extension ApolloRuntimeStats: ProjectedOptimizerRuntimeStats {
    var fallbackCount: Int { 0 }
}

final class ApolloProjectedAdam: Optimizer {
    enum ProjectionMode {
        case full
        case left
        case right
    }

    struct ParameterState {
        var step: Int
        var mode: ProjectionMode
        var rows: Int
        var cols: Int
        var rank: Int
        var basis: MLXArray?
        var m: MLXArray
        var v: MLXArray
    }

    private let rank: Int
    private let projectionRefreshInterval: Int
    private let learningRate: Float
    private let betas: (Float, Float)
    private let eps: Float

    private let lock = NSLock()
    private var states: [String: ParameterState] = [:]
    private var stats = ApolloRuntimeStats(
        approximateProjectedOptimizerMemoryBytes: 0,
        approximateFullOptimizerMemoryBytes: 0,
        projectionRefreshed: false
    )

    init(
        learningRate: Float,
        rank: Int,
        projectionRefreshInterval: Int = 200,
        betas: (Float, Float) = (0.9, 0.999),
        eps: Float = 1e-8
    ) {
        self.learningRate = learningRate
        self.rank = max(1, rank)
        self.projectionRefreshInterval = max(1, projectionRefreshInterval)
        self.betas = betas
        self.eps = max(eps, 1e-12)
    }

    func innerState() -> [MLXArray] {
        lock.lock()
        let arrays = states.values.flatMap { state -> [MLXArray] in
            if let basis = state.basis {
                return [state.m, state.v, basis]
            }
            return [state.m, state.v]
        }
        lock.unlock()
        return arrays
    }

    func runtimeStats() -> ApolloRuntimeStats {
        lock.lock()
        let value = stats
        lock.unlock()
        return value
    }

    func update(model: Module, gradients: ModuleParameters) {
        let gradientPairs = gradients.flattened()
        guard !gradientPairs.isEmpty else { return }

        let modelParameters = model.parameters()
        let modelParameterMap = Dictionary(uniqueKeysWithValues: modelParameters.flattened())
        let (b1, b2) = betas

        lock.lock()

        var updatedParameters: [(String, MLXArray)] = []
        updatedParameters.reserveCapacity(gradientPairs.count)

        var fullOptimizerElements = 0
        var projectedOptimizerElements = 0
        var projectionRefreshed = false

        for (key, gradientRaw) in gradientPairs {
            guard let parameter = modelParameterMap[key] else { continue }

            let gradient = gradientRaw.asType(.float32)
            let parameter32 = parameter.asType(.float32)
            fullOptimizerElements += max(1, gradient.size)

            let shape = gradient.shape
            let hasMatrixShape = shape.count >= 2
            let rows = hasMatrixShape ? max(1, gradient.dim(0)) : max(1, gradient.size)
            let cols = hasMatrixShape ? max(1, gradient.size / rows) : 1

            if !hasMatrixShape {
                var state = states[key] ?? ParameterState(
                    step: 0,
                    mode: .full,
                    rows: rows,
                    cols: cols,
                    rank: 0,
                    basis: nil,
                    m: MLXArray.zeros(like: gradient),
                    v: MLXArray.zeros(like: gradient)
                )

                if state.mode != .full || state.m.shape != gradient.shape {
                    state = ParameterState(
                        step: 0,
                        mode: .full,
                        rows: rows,
                        cols: cols,
                        rank: 0,
                        basis: nil,
                        m: MLXArray.zeros(like: gradient),
                        v: MLXArray.zeros(like: gradient)
                    )
                }

                state.step += 1
                state.m = b1 * state.m + (1 - b1) * gradient
                state.v = b2 * state.v + (1 - b2) * square(gradient)

                let update = state.m / (sqrt(state.v) + eps)
                let nextParam = (parameter32 - learningRate * update).asType(parameter.dtype)

                states[key] = state
                projectedOptimizerElements += max(1, state.m.size + state.v.size)
                updatedParameters.append((key, nextParam))
                continue
            }

            let matrix = gradient.reshaped(rows, cols)
            let projectedRank = max(1, min(rank, min(rows, cols)))
            let mode: ProjectionMode = rows <= cols ? .right : .left

            var state = states[key] ?? ParameterState(
                step: 0,
                mode: mode,
                rows: rows,
                cols: cols,
                rank: projectedRank,
                basis: nil,
                m: MLXArray(0),
                v: MLXArray(0)
            )

            let stateMismatch = state.mode != mode || state.rows != rows || state.cols != cols || state.rank != projectedRank
            if stateMismatch {
                let projectedShape: [Int] = mode == .right ? [rows, projectedRank] : [projectedRank, cols]
                state = ParameterState(
                    step: 0,
                    mode: mode,
                    rows: rows,
                    cols: cols,
                    rank: projectedRank,
                    basis: nil,
                    m: MLXArray.zeros(projectedShape, dtype: .float32),
                    v: MLXArray.zeros(projectedShape, dtype: .float32)
                )
            }

            state.step += 1
            let needsRefresh = state.basis == nil || state.step == 1 || (state.step - 1) % projectionRefreshInterval == 0
            if needsRefresh {
                state.basis = randomProjectionBasis(
                    rows: rows,
                    cols: cols,
                    rank: projectedRank,
                    mode: mode,
                    seed: key.hashValue ^ state.step
                )
                projectionRefreshed = true
            }

            guard let basis = state.basis else {
                continue
            }

            let projectedGradient: MLXArray
            let fullUpdate: MLXArray

            switch mode {
            case .right:
                projectedGradient = matmul(matrix, basis)
                state.m = b1 * state.m + (1 - b1) * projectedGradient
                state.v = b2 * state.v + (1 - b2) * square(projectedGradient)
                let projectedUpdate = state.m / (sqrt(state.v) + eps)
                fullUpdate = matmul(projectedUpdate, basis.transposed())
            case .left:
                projectedGradient = matmul(basis.transposed(), matrix)
                state.m = b1 * state.m + (1 - b1) * projectedGradient
                state.v = b2 * state.v + (1 - b2) * square(projectedGradient)
                let projectedUpdate = state.m / (sqrt(state.v) + eps)
                fullUpdate = matmul(basis, projectedUpdate)
            case .full:
                projectedGradient = matrix
                state.m = b1 * state.m + (1 - b1) * projectedGradient
                state.v = b2 * state.v + (1 - b2) * square(projectedGradient)
                fullUpdate = state.m / (sqrt(state.v) + eps)
            }

            let nextMatrix = parameter32.reshaped(rows, cols) - learningRate * fullUpdate
            let nextParam = nextMatrix.reshaped(parameter.shape).asType(parameter.dtype)

            states[key] = state
            projectedOptimizerElements += max(1, state.m.size + state.v.size + basis.size)
            updatedParameters.append((key, nextParam))
        }

        lock.unlock()

        let fullBytes = UInt64(max(1, fullOptimizerElements) * MemoryLayout<Float>.size * 2)
        let projectedBytes = UInt64(max(1, projectedOptimizerElements) * MemoryLayout<Float>.size)

        lock.lock()
        stats = ApolloRuntimeStats(
            approximateProjectedOptimizerMemoryBytes: projectedBytes,
            approximateFullOptimizerMemoryBytes: fullBytes,
            projectionRefreshed: projectionRefreshed
        )
        lock.unlock()

        if !updatedParameters.isEmpty {
            model.update(parameters: ModuleParameters.unflattened(updatedParameters))
            eval(model)
        }
    }

    private func randomProjectionBasis(rows: Int, cols: Int, rank: Int, mode: ProjectionMode, seed: Int) -> MLXArray {
        let projectionShape: [Int]
        let scale: Float

        switch mode {
        case .right:
            projectionShape = [cols, rank]
            scale = 1 / Float(max(1, cols)).squareRoot()
        case .left:
            projectionShape = [rows, rank]
            scale = 1 / Float(max(1, rows)).squareRoot()
        case .full:
            projectionShape = [rows, cols]
            scale = 1
        }

        let elementCount = projectionShape.reduce(1, *)
        var values = [Float]()
        values.reserveCapacity(elementCount)

        for index in 0 ..< elementCount {
            let mixed = Double((seed &* 31) &+ index &* 17 &+ 97)
            let sample = sin(mixed * 12.9898 + 78.233) * 43758.5453
            let fractional = sample - floor(sample)
            values.append(Float((fractional * 2.0) - 1.0) * scale)
        }

        return MLXArray(values).reshaped(projectionShape[0], projectionShape[1]).asType(.float32)
    }
}
#endif
