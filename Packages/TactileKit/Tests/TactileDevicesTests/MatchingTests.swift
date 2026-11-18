import XCTest
@testable import TactileDevices

/// Which HID interfaces the system is asked to watch. Nothing here makes a manager or opens anything.
final class MatchingTests: XCTestCase {

    /// The touchscreen source watches touchscreen interfaces and mouse interfaces, as it always has.
    func testTheSourceWatchesTouchscreensAndMice() {
        XCTAssertEqual(HIDMatching.touchscreensAndMice.criteria, [
            ["DeviceUsagePage": 0x0D, "DeviceUsage": 0x04],
            ["DeviceUsagePage": 0x01, "DeviceUsage": 0x02],
        ])
    }

    /// The check also watches every interface on the Digitizer page, and pointers: to list the
    /// digitisers Tactile doesn't, and the touchscreens that are only a mouse.
    func testTheCheckWatchesDigitisersPointersAndMice() {
        XCTAssertEqual(HIDMatching.supportCheck.criteria, [
            ["DeviceUsagePage": 0x0D],
            ["DeviceUsagePage": 0x01, "DeviceUsage": 0x01],
            ["DeviceUsagePage": 0x01, "DeviceUsage": 0x02],
        ])
    }

    /// A read that failed brings nothing back; one that worked brings back what it read.
    func testAFeatureReadKeepsWhatCameBack() {
        XCTAssertEqual(FeatureReportRead(result: 0, length: 0, seconds: 0).bytes, [])
        XCTAssertEqual(FeatureReportRead(result: 0, length: 2, seconds: 0, bytes: [0x0A, 0x0A]).bytes, [0x0A, 0x0A])
    }
}
