import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct GuardrailSnapshot {
    let thermalState: FineTuneThermalState
    let residentMemoryBytes: UInt64
}

enum GuardrailDecision: Equatable {
    case allow
    case pause(String)
    case stop(String)
}

struct TrainingGuardrailService {
    var maxResidentMemoryBytes: UInt64 = 2_600_000_000
    var stopAtThermalState: FineTuneThermalState = .critical
    var pauseAtThermalState: FineTuneThermalState = .serious

    func snapshot() -> GuardrailSnapshot {
        GuardrailSnapshot(
            thermalState: FineTuneThermalState.from(processInfoState: ProcessInfo.processInfo.thermalState),
            residentMemoryBytes: currentResidentMemoryBytes()
        )
    }

    func evaluate(snapshot: GuardrailSnapshot) -> GuardrailDecision {
        if snapshot.thermalState == stopAtThermalState {
            return .stop("Training stopped due to critical thermal pressure.")
        }
        if snapshot.thermalState == pauseAtThermalState {
            return .pause("Training paused due to serious thermal pressure.")
        }
        if snapshot.residentMemoryBytes > maxResidentMemoryBytes {
            return .stop("Training stopped because memory usage exceeded the safety limit.")
        }
        return .allow
    }

    private func currentResidentMemoryBytes() -> UInt64 {
#if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        return UInt64(info.resident_size)
#else
        return 0
#endif
    }
}
