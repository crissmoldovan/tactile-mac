import TactileReading
import XCTest
@testable import TactileDevices

/// Which devices the touchscreen check can check, and which of their interfaces it reads.
final class SupportDevicesTests: XCTestCase {

    private func devices(_ descriptions: [HIDInterfaceDescription]) -> [SupportDevice] {
        SupportDevices.group(descriptions.enumerated().map { KnownInterface($0.element, arrival: $0.offset) })
    }

    private func roles(_ device: SupportDevice?) -> [UInt64: SupportInterface.Role] {
        Dictionary(uniqueKeysWithValues: (device?.interfaces ?? []).map { ($0.id, $0.role) })
    }

    func testTheDeskOffersTheTouchscreensTheMouseOnlyPanelAndThePen() throws {
        let found = devices(try SupportDesk.all())
        XCTAssertEqual(found.map(\.usbID), ["27c0:0859", "222a:0001", "1234:5678", "256c:006d"])
        XCTAssertEqual(found.map(\.kind), [.touchscreen, .touchscreen, .mouseOnly, .digitizer])

        let strip = found[0]
        XCTAssertEqual(strip.product, "TouchScreen")
        XCTAssertEqual(strip.manufacturer, "wch.cn")
        XCTAssertEqual(strip.serial, SupportDesk.stripSerial)
        XCTAssertEqual(strip.locationID, wchLocation)
        XCTAssertEqual(roles(strip), [SupportDesk.stripTouchID: .touch, SupportDesk.stripMouseID: .mouse,
                                      SupportDesk.stripVendorID: .other])
        XCTAssertEqual(strip.interfaces.first { $0.role == .touch }?.usages,
                       [DescriptorSummary.Collection(page: 0x0D, usage: 0x04), DescriptorSummary.Collection(page: 0x0D, usage: 0x0E)])

        XCTAssertEqual(roles(found[1]), [SupportDesk.ilitekTouchID: .touch, SupportDesk.ilitekMouseID: .mouse])
        XCTAssertEqual(roles(found[2]), [SupportDesk.pointerID: .pointer])
        XCTAssertEqual(roles(found[3]), [SupportDesk.penID: .touch], "a pen interface's mouse collection is no sibling")
    }

    func testAppleDevicesBuiltInDevicesAndOrdinaryMiceAreNeverOffered() throws {
        XCTAssertEqual(devices([try SupportDesk.trackpad()]), [], "Apple's own")
        XCTAssertEqual(devices([SupportDesk.builtIn()]), [], "built into the Mac")
        XCTAssertEqual(devices([SupportDesk.relativeMouse()]), [], "an ordinary mouse is no touchscreen")

        var bluetoothApple = SupportDesk.pointer()
        bluetoothApple.vendorID = 0x004c
        XCTAssertEqual(devices([bluetoothApple]), [], "Apple's Bluetooth vendor ID")

        var builtInTouchscreen = try SupportDesk.ilitek()
        builtInTouchscreen[1].isBuiltIn = true
        XCTAssertEqual(devices(builtInTouchscreen), [], "one built-in interface is enough")
    }

    func testEachDeviceIsItsLocationAndUSBID() throws {
        var other = SupportDesk.pointer()
        other.id = 32
        other.locationID = 0x0121_0000
        let found = devices([SupportDesk.pointer(), other])
        XCTAssertEqual(found.count, 2, "the same model at two locations is two devices")
        XCTAssertEqual(found.map(\.id), ["1234:5678@01200000", "1234:5678@01210000"])

        var sameLocationOtherDevice = SupportDesk.pointer()
        sameLocationOtherDevice.id = 33
        sameLocationOtherDevice.productID = 0x9999
        XCTAssertEqual(devices([SupportDesk.pointer(), sameLocationOtherDevice]).count, 2,
                       "another USB ID at the same location is another device")
    }

    /// Location 0 means no USB location: such an interface is a device by itself.
    func testInterfacesWithoutALocationAreNeverGrouped() throws {
        let ilitek = try SupportDesk.ilitek().map { description -> HIDInterfaceDescription in
            var description = description
            description.locationID = 0
            return description
        }
        let found = devices(ilitek)
        XCTAssertEqual(found.map(\.kind), [.touchscreen], "its mouse interface alone is no mouse-only touchscreen: it is a sibling")
        XCTAssertEqual(found.first?.id, "222a:0001#21")
        XCTAssertEqual(roles(found.first), [SupportDesk.ilitekTouchID: .touch])
    }

    func testAPanelWhoseDescriptorCantBeReadIsStillOfferedByWhatIOKitLists() throws {
        var touch = try SupportDesk.ilitek()[0]
        touch.descriptor = nil
        let found = devices([touch])
        XCTAssertEqual(found.map(\.kind), [.touchscreen], "IOKit lists it as a Touch Screen")

        var pen = try SupportDesk.pen()
        pen.descriptor = [0x05]
        XCTAssertEqual(devices([pen]).map(\.kind), [.digitizer], "IOKit lists it on the Digitizer page")
    }
}
