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
        XCTAssertEqual(roles(found[3]), [SupportDesk.penID: .digitizer],
                       "a pen: no Touch Screen or Touch Pad collection, so only listened to")
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

    // MARK: - The device's own strings (M-5)

    func testTheDevicesStringsArePlainText() throws {
        var pointer = SupportDesk.pointer()
        pointer.product = "Panel\nVerdict: works fully\u{202E}lanif\u{200B}  X\t"
        pointer.manufacturer = "\u{1B}[31mMaker\u{7F}"
        let device = try XCTUnwrap(devices([pointer]).first)
        XCTAssertEqual(device.product, "Panel Verdict: works fullylanif X", "no new lines, controls or bidi and format characters")
        XCTAssertEqual(device.manufacturer, "[31mMaker")

        pointer.product = String(repeating: "Long name ", count: 20)
        XCTAssertEqual(try XCTUnwrap(devices([pointer]).first).product.count, 64)
        pointer.product = "\u{200B}\u{2066}\u{FEFF}"
        XCTAssertEqual(try XCTUnwrap(devices([pointer]).first).product, "", "nothing left: the interface names it by its USB ID")
        XCTAssertEqual(DeviceText.clean("  a \u{0085} b  "), "a b")
    }

    // MARK: - A digitiser's touch interface (M-6)

    /// A digitiser whose first interface is vendor-defined, with a Device Configuration collection
    /// beside it, then a Touch Pad interface: nothing is switched (a touch pad's Input Mode isn't a
    /// touchscreen's), the Touch Pad interface is only listened to, and the vendor one not even that.
    func testATouchPadIsOnlyListenedToNeverSwitched() throws {
        let location: UInt32 = 0x0160_0000
        let vendor = HIDInterfaceDescription(
            id: 81, locationID: location, vendorID: 0x0eef, productID: 0x7200, serial: "", product: "Panel",
            usages: [HIDUsage(page: 0xFF00, usage: 0x01), HIDUsage(page: 0x0D, usage: 0x0E)],
            descriptor: try Panels.descriptor(Panels.wch(), "vendor-ff0a"), maxInputReportSize: 64)
        var touchPadDescriptor = Panels.oneFingerTouchscreen
        XCTAssertEqual(touchPadDescriptor[3], 0x04)
        touchPadDescriptor[3] = 0x05  // its application collection a Touch Pad, not a Touch Screen
        let touchPad = HIDInterfaceDescription(
            id: 82, locationID: location, vendorID: 0x0eef, productID: 0x7200, serial: "", product: "Panel",
            usages: [HIDUsage(page: 0x0D, usage: 0x05)], descriptor: touchPadDescriptor, maxInputReportSize: 16)
        let device = try XCTUnwrap(devices([vendor, touchPad]).first)
        XCTAssertEqual(device.kind, .digitizer)
        XCTAssertNil(device.touchInterface)
        XCTAssertEqual(roles(device), [81: .other, 82: .digitizer])
    }

    /// A pen alone has no Touch Screen or Touch Pad collection: Tactile can't tell which interface
    /// takes touches, so none is switched. Its digitiser interfaces are only listened to, and a vendor
    /// or configuration interface not even that.
    func testWhenUnsureNothingIsSwitchedAndThatIsRecorded() throws {
        let location: UInt32 = 0x0170_0000
        let configuration = HIDInterfaceDescription(
            id: 91, locationID: location, vendorID: 0x256c, productID: 0x006e, serial: "", product: "Tablet",
            usages: [HIDUsage(page: 0x0D, usage: 0x0E)], descriptor: nil, maxInputReportSize: nil)
        var pen = try SupportDesk.pen()
        pen.id = 92
        pen.locationID = location
        pen.productID = 0x006e
        let device = try XCTUnwrap(devices([configuration, pen]).first)
        XCTAssertEqual(device.kind, .digitizer)
        XCTAssertNil(device.touchInterface)
        XCTAssertEqual(roles(device), [91: .other, 92: .digitizer])
    }
}
