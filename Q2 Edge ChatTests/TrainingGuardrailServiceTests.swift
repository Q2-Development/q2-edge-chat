import XCTest
@testable import Q2_Edge_Chat

final class TrainingGuardrailServiceTests: XCTestCase {
    func testGuardrailPausesWhenMemoryApproachesBudget() {
        let service = TrainingGuardrailService(
            maxResidentMemoryBytes: 2_200_000_000,
            pauseResidentMemoryBytes: 2_050_000_000,
            stopAtThermalState: .critical,
            pauseAtThermalState: .serious
        )

        let snapshot = GuardrailSnapshot(
            thermalState: .nominal,
            residentMemoryBytes: 2_100_000_000
        )

        let decision = service.evaluate(snapshot: snapshot)
        guard case .pause(let message) = decision else {
            return XCTFail("Expected pause decision.")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testGuardrailStopsWhenMemoryExceedsBudget() {
        let service = TrainingGuardrailService(
            maxResidentMemoryBytes: 2_200_000_000,
            pauseResidentMemoryBytes: 2_050_000_000,
            stopAtThermalState: .critical,
            pauseAtThermalState: .serious
        )

        let snapshot = GuardrailSnapshot(
            thermalState: .nominal,
            residentMemoryBytes: 2_250_000_000
        )

        let decision = service.evaluate(snapshot: snapshot)
        guard case .stop(let message) = decision else {
            return XCTFail("Expected stop decision.")
        }
        XCTAssertFalse(message.isEmpty)
    }
}
