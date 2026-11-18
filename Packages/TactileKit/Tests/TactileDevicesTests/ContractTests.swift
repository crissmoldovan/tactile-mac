import TactileDevices
import XCTest

final class ContractTests: XCTestCase {
    func testANewDeviceStatusIsReleasedAndUntouched() {
        let status = DeviceStatus()
        XCTAssertEqual(status.state, .released)
        XCTAssertEqual(status.inputMode, .notSwitched)
        XCTAssertEqual(status.touchOrigin, .undetermined)
        XCTAssertEqual(status.exclusive, .notHeld)
    }

    func testADeviceHandleDescribesItself() {
        XCTAssertEqual(DeviceHandle(rawValue: 7).description, "device-7")
    }
}
