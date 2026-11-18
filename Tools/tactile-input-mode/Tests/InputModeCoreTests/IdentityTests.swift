import XCTest
@testable import InputModeCore

final class IdentityTests: XCTestCase {
    private let strip = USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0x0113_0000, serial: "TEST-SERIAL-0001")

    func testASiblingSharesTheLocationAndTheUSBID() {
        let mouse = USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0x0113_0000, serial: "TEST-SERIAL-0001")
        XCTAssertTrue(mouse.isSibling(of: strip))
    }

    func testADeviceElsewhereOrFromAnotherMakerIsNotASibling() {
        XCTAssertFalse(USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0x0114_1000, serial: "").isSibling(of: strip))
        XCTAssertFalse(USBIdentity(vendorID: 0x046D, productID: 0xC52B, locationID: 0x0113_0000, serial: "").isSibling(of: strip))
        XCTAssertFalse(USBIdentity(vendorID: 0x27C0, productID: 0x0001, locationID: 0x0113_0000, serial: "").isSibling(of: strip))
    }

    func testLocationZeroNeverMakesASibling() {
        // With no location ID, unrelated mice would all look alike.
        let touch = USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0, serial: "")
        XCTAssertFalse(USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0, serial: "").isSibling(of: touch))
    }

    func testFilterParsing() {
        let plain = DeviceFilter("27c0:0859")
        XCTAssertEqual(plain?.vendorID, 0x27C0)
        XCTAssertEqual(plain?.productID, 0x0859)
        XCTAssertNil(plain?.serial)
        XCTAssertEqual(DeviceFilter("27c0:0859:TEST-SERIAL-0001")?.serial, "TEST-SERIAL-0001")
        XCTAssertNil(DeviceFilter("27c0"))
        XCTAssertNil(DeviceFilter("zz:0859"))
        XCTAssertNil(DeviceFilter("27c0:0859:"))
    }

    func testFilterMatching() {
        XCTAssertTrue(DeviceFilter("27c0:0859")!.matches(strip))
        XCTAssertTrue(DeviceFilter("27c0:0859:TEST-SERIAL-0001")!.matches(strip))
        XCTAssertFalse(DeviceFilter("27c0:0859:OTHER")!.matches(strip))
        XCTAssertFalse(DeviceFilter("222a:0001")!.matches(strip))
    }

    func testTheFilterForAPresentStripPinsItsSerial() {
        let filter = DeviceFilter(identity: strip)
        XCTAssertTrue(filter.matches(strip))
        XCTAssertFalse(filter.matches(USBIdentity(vendorID: 0x27C0, productID: 0x0859, locationID: 0x0113_0000, serial: "OTHER")))
    }
}
