import Darwin
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum FineTuneDeviceTelemetryProvider {
    static func current() -> FineTuneDeviceTelemetry {
        let machineIdentifier = resolvedMachineIdentifier()
        let processInfo = ProcessInfo.processInfo

        #if canImport(UIKit)
        let device = UIDevice.current
        let baseModel = device.userInterfaceIdiom == .pad ? "iPad" : device.model
        let deviceModel = "\(baseModel) [\(machineIdentifier)]"

        return FineTuneDeviceTelemetry(
            deviceModel: deviceModel,
            machineIdentifier: machineIdentifier,
            systemName: device.systemName,
            systemVersion: device.systemVersion,
            operatingSystemVersionString: processInfo.operatingSystemVersionString
        )
        #else
        return FineTuneDeviceTelemetry(
            deviceModel: machineIdentifier,
            machineIdentifier: machineIdentifier,
            systemName: "Unknown",
            systemVersion: processInfo.operatingSystemVersionString,
            operatingSystemVersionString: processInfo.operatingSystemVersionString
        )
        #endif
    }

    private static func resolvedMachineIdentifier() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let simulatorModel = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulatorModel.isEmpty {
            return simulatorModel
        }

        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { machine in
                String(cString: machine)
            }
        }
    }
}
