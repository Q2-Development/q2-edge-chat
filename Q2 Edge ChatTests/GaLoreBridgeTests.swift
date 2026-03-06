import XCTest
@testable import Q2_Edge_Chat

final class GaLoreBridgeTests: XCTestCase {
    func testProjectionRefreshesOnConfiguredInterval() {
        var bridge = GaLoreOptimizerBridge(rank: 4, vectorLength: 64, projectionUpdateInterval: 3, scaleFactor: 0.25, learningRate: 1e-3)
        let gradient = Array(repeating: 0.1, count: 64)

        let s1 = bridge.step(gradient: gradient, globalStep: 1)
        let s2 = bridge.step(gradient: gradient, globalStep: 2)
        let s3 = bridge.step(gradient: gradient, globalStep: 3)
        let s4 = bridge.step(gradient: gradient, globalStep: 4)

        XCTAssertTrue(s1.projectionRefreshed)
        XCTAssertFalse(s2.projectionRefreshed)
        XCTAssertFalse(s3.projectionRefreshed)
        XCTAssertTrue(s4.projectionRefreshed)
    }

    func testProjectedOptimizerMemoryIsLowerThanFull() {
        var bridge = GaLoreOptimizerBridge(rank: 4, vectorLength: 128, projectionUpdateInterval: 200, scaleFactor: 0.25, learningRate: 1e-3)
        let result = bridge.step(gradient: Array(repeating: 0.01, count: 128), globalStep: 1)

        XCTAssertLessThan(result.approximateOptimizerMemoryBytes, result.approximateFullOptimizerMemoryBytes)
    }
}
