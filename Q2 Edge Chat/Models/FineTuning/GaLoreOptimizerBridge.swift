import Foundation

struct GaLoreStepResult: Hashable {
    let projectedDimension: Int
    let projectionRefreshed: Bool
    let approximateOptimizerMemoryBytes: UInt64
    let approximateFullOptimizerMemoryBytes: UInt64
    let updateNorm: Double
}

struct GaLoreOptimizerBridge {
    private(set) var rank: Int
    private(set) var vectorLength: Int
    private(set) var projectionUpdateInterval: Int
    private(set) var scaleFactor: Double
    private(set) var learningRate: Double

    private var projectionBasis: [[Double]]

    init(rank: Int, vectorLength: Int, projectionUpdateInterval: Int = 200, scaleFactor: Double = 0.25, learningRate: Double) {
        self.rank = max(1, min(rank, vectorLength))
        self.vectorLength = max(1, vectorLength)
        self.projectionUpdateInterval = max(1, projectionUpdateInterval)
        self.scaleFactor = max(0.0001, min(scaleFactor, 1.0))
        self.learningRate = learningRate
        self.projectionBasis = Self.randomOrthonormalBasis(rank: self.rank, vectorLength: self.vectorLength)
    }

    mutating func step(gradient: [Double], globalStep: Int) -> GaLoreStepResult {
        let projectionRefreshed = shouldRefreshProjection(at: globalStep)
        if projectionRefreshed {
            projectionBasis = Self.randomOrthonormalBasis(rank: rank, vectorLength: vectorLength)
        }

        let projectedGradient = project(gradient: gradient)
        let projectedUpdate = projectedGradient.map { -learningRate * $0 }
        let fullUpdate = reconstruct(update: projectedUpdate)
        let scaledUpdate = fullUpdate.map { $0 * scaleFactor }

        let updateNorm = sqrt(scaledUpdate.reduce(0) { $0 + ($1 * $1) })

        let fullOptimizerMemory = UInt64(vectorLength * MemoryLayout<Double>.size * 2)
        let projectedOptimizerMemory = UInt64(rank * MemoryLayout<Double>.size * 2)

        return GaLoreStepResult(
            projectedDimension: rank,
            projectionRefreshed: projectionRefreshed,
            approximateOptimizerMemoryBytes: projectedOptimizerMemory,
            approximateFullOptimizerMemoryBytes: fullOptimizerMemory,
            updateNorm: updateNorm
        )
    }

    private func shouldRefreshProjection(at globalStep: Int) -> Bool {
        if globalStep <= 1 {
            return true
        }
        return (globalStep - 1) % projectionUpdateInterval == 0
    }

    private func project(gradient: [Double]) -> [Double] {
        projectionBasis.map { row in
            zip(row, gradient).reduce(0) { $0 + ($1.0 * $1.1) }
        }
    }

    private func reconstruct(update: [Double]) -> [Double] {
        var output = Array(repeating: 0.0, count: vectorLength)
        for (rowIndex, row) in projectionBasis.enumerated() {
            let coeff = rowIndex < update.count ? update[rowIndex] : 0
            for col in 0..<vectorLength {
                output[col] += row[col] * coeff
            }
        }
        return output
    }

    private static func randomOrthonormalBasis(rank: Int, vectorLength: Int) -> [[Double]] {
        var rng = SystemRandomNumberGenerator()
        var basis: [[Double]] = []
        basis.reserveCapacity(rank)

        for _ in 0..<rank {
            var vector = (0..<vectorLength).map { _ in Double.random(in: -1...1, using: &rng) }

            for existing in basis {
                let dot = zip(vector, existing).reduce(0) { $0 + ($1.0 * $1.1) }
                for idx in 0..<vectorLength {
                    vector[idx] -= dot * existing[idx]
                }
            }

            let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
            if norm > 1e-8 {
                vector = vector.map { $0 / norm }
            } else {
                vector[0] = 1
            }
            basis.append(vector)
        }

        return basis
    }
}
