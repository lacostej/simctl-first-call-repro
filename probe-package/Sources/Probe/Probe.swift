import Foundation

public enum Probe {
    // Set by the simulator for every process it runs
    public static var simulatorDeviceName: String? {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
    }
}
