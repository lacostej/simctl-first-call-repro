import XCTest
@testable import Probe

final class ProbeTests: XCTestCase {
    func testRunsInASimulator() {
        XCTAssertNotNil(Probe.simulatorDeviceName)
    }
}
