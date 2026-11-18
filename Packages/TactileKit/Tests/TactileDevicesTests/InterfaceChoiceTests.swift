import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

/// The wch.cn and the ILITEK sit behind one hub, at these locations (from the surveys).
let wchLocation: UInt32 = 0x0113_0000
let ilitekLocation: UInt32 = 0x0114_1000

/// An interface as the system would describe it, from a descriptor. `usages` is IOKit's list of its
/// application collections, and `listsTouchScreen` adds Touch Screen to it; by default the list is
/// empty and only the descriptor decides.
func interface(_ id: HIDInterfaceID, at location: UInt32, _ descriptor: [UInt8]?, listsTouchScreen: Bool = false,
               usages: [HIDUsage] = [], vendorID: Int = 0, productID: Int = 0, serial: String = "",
               product: String = "", maxInputReportSize: Int? = nil) -> HIDInterfaceDescription {
    HIDInterfaceDescription(id: id, locationID: location, vendorID: vendorID, productID: productID, serial: serial,
                            product: product, usages: (listsTouchScreen ? [.touchScreen] : []) + usages,
                            descriptor: descriptor, maxInputReportSize: maxInputReportSize)
}

private func known(_ descriptions: [HIDInterfaceDescription]) -> [KnownInterface] {
    descriptions.enumerated().map { KnownInterface($0.element, arrival: $0.offset) }
}

final class InterfaceChoiceTests: XCTestCase {

    /// The wch.cn has three interfaces: mouse, touchscreen and vendor. Whatever order they arrive
    /// in, the touchscreen interface is read and the mouse is its sibling; the vendor interface is
    /// neither.
    func testTheStripsThreeInterfaces() throws {
        let strip = try Panels.wch()
        let mouse = interface(1, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages)
        let touch = interface(2, at: wchLocation, try Panels.descriptor(strip, "touchscreen"))
        let vendor = interface(3, at: wchLocation, try Panels.descriptor(strip, "vendor-ff0a"))

        let knownVendor = KnownInterface(vendor, arrival: 0)
        XCTAssertFalse(knownVendor.isTouchscreen)
        XCTAssertFalse(knownVendor.isMouse)

        for order in [[mouse, touch, vendor], [touch, vendor, mouse], [vendor, mouse, touch]] {
            XCTAssertEqual(InterfaceChoice.groups(known(order)), [InterfaceGroup(touch: 2, mouse: 1)])
        }
    }

    func testTheILITEKsTwoInterfaces() throws {
        let ilitek = try Panels.ilitek()
        let touch = interface(7, at: ilitekLocation, try Panels.descriptor(ilitek, "touchscreen"))
        let mouse = interface(8, at: ilitekLocation, try Panels.descriptor(ilitek, "mouse"), usages: Panels.ilitekMouseUsages)
        XCTAssertEqual(InterfaceChoice.groups(known([touch, mouse])), [InterfaceGroup(touch: 7, mouse: 8)])
        XCTAssertEqual(KnownInterface(touch, arrival: 0).contactSlots, 10)
    }

    /// Both panels behind one hub, with the person's own mouse elsewhere: two touchscreens, each
    /// with its own sibling, and the other mouse belongs to neither (Review Focus 6).
    func testBothPanelsAndAnotherMouse() throws {
        let strip = try Panels.wch(), ilitek = try Panels.ilitek()
        let interfaces = known([
            interface(1, at: 0x0010_0000, try Panels.descriptor(strip, "mouse"), usages: [.mouse]),  // someone's mouse
            interface(2, at: ilitekLocation, try Panels.descriptor(ilitek, "mouse"), usages: Panels.ilitekMouseUsages),
            interface(3, at: wchLocation, try Panels.descriptor(strip, "touchscreen")),
            interface(4, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages),
            interface(5, at: ilitekLocation, try Panels.descriptor(ilitek, "touchscreen")),
        ])
        XCTAssertEqual(InterfaceChoice.groups(interfaces), [InterfaceGroup(touch: 3, mouse: 4), InterfaceGroup(touch: 5, mouse: 2)])
    }

    /// A pen display's pen interface carries a Mouse collection beside its Pen one, and a combined
    /// keyboard has one beside its Keyboard one. Their descriptors read as a mouse's, but neither
    /// is ever a touchscreen's mouse sibling; an ordinary mouse at the same location still is.
    func testAPenOrAKeyboardIsNeverASibling() throws {
        let strip = try Panels.wch()
        let penDescriptor = try Panels.penAndMouse(), keyboardDescriptor = try Panels.keyboardAndMouse()
        XCTAssertEqual(InterfaceDecoder(descriptor: penDescriptor)?.kind, .mouse, "the pen interface reads as a mouse")
        XCTAssertEqual(InterfaceDecoder(descriptor: keyboardDescriptor)?.kind, .mouse, "the keyboard interface reads as a mouse")

        let touch = interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"), listsTouchScreen: true)
        let pen = interface(2, at: wchLocation, penDescriptor, usages: [.pen, .mouse])
        let keyboard = interface(3, at: wchLocation, keyboardDescriptor, usages: [.keyboard, .mouse])
        XCTAssertEqual(InterfaceChoice.groups(known([pen, keyboard, touch])), [InterfaceGroup(touch: 1, mouse: nil)])

        let mouse = interface(4, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: [.mouse])
        XCTAssertEqual(InterfaceChoice.groups(known([pen, keyboard, touch, mouse])), [InterfaceGroup(touch: 1, mouse: 4)])
    }

    /// Many pen tablets have a Digitizer (0x0D/0x01) top collection rather than a Pen one. Any usage
    /// on the Digitizer page refuses an interface as a sibling, whatever Mouse collection it also has.
    func testAnInterfaceListingAnyDigitizerUsageIsNeverASibling() throws {
        let strip = try Panels.wch()
        let touch = interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"), listsTouchScreen: true)
        let digitizer = interface(2, at: wchLocation, try Panels.penAndMouse(), usages: [HIDUsage(page: 0x0D, usage: 0x01), .mouse])
        XCTAssertEqual(InterfaceChoice.groups(known([digitizer, touch])), [InterfaceGroup(touch: 1, mouse: nil)])
    }

    /// IOKit lists a mouse's Mouse collection. An interface whose list is empty, or lacks Mouse,
    /// is refused, whatever its descriptor says.
    func testAnInterfaceThatIOKitDoesNotListAsAMouseIsNeverASibling() throws {
        let strip = try Panels.wch()
        let touch = interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"), listsTouchScreen: true)
        let unlisted = interface(2, at: wchLocation, try Panels.descriptor(strip, "mouse"))
        let pointerOnly = interface(3, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: [.pointer])
        XCTAssertEqual(InterfaceChoice.groups(known([unlisted, pointerOnly, touch])), [InterfaceGroup(touch: 1, mouse: nil)])
    }

    /// The two real panels' mouse interfaces, with the usages IOKit lists for them, are siblings.
    func testTheRealPanelsMiceAreStillSiblings() throws {
        let strip = try Panels.wch(), ilitek = try Panels.ilitek()
        let interfaces = known([
            interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"), listsTouchScreen: true),
            interface(2, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages),
            interface(3, at: ilitekLocation, try Panels.descriptor(ilitek, "touchscreen"), listsTouchScreen: true),
            interface(4, at: ilitekLocation, try Panels.descriptor(ilitek, "mouse"), usages: Panels.ilitekMouseUsages),
        ])
        XCTAssertEqual(InterfaceChoice.groups(interfaces), [InterfaceGroup(touch: 1, mouse: 2), InterfaceGroup(touch: 3, mouse: 4)])
    }

    /// A sibling shares the touchscreen's USB vendor and product ID as well as its location.
    func testASiblingHasTheTouchscreensUSBID() throws {
        let strip = try Panels.wch()
        let touch = interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"),
                              vendorID: Panels.wchVendorID, productID: Panels.wchProductID)
        let stranger = interface(2, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: [.mouse], vendorID: 0x05ac, productID: 0x0265)
        let otherProduct = interface(3, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: [.mouse],
                                     vendorID: Panels.wchVendorID, productID: 0x0001)
        XCTAssertEqual(InterfaceChoice.groups(known([stranger, otherProduct, touch])), [InterfaceGroup(touch: 1, mouse: nil)])
        let own = interface(4, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages,
                            vendorID: Panels.wchVendorID, productID: Panels.wchProductID)
        XCTAssertEqual(InterfaceChoice.groups(known([stranger, otherProduct, touch, own])), [InterfaceGroup(touch: 1, mouse: 4)])
    }

    func testAMouseWithNoTouchscreenIsNoTouchscreen() throws {
        let strip = try Panels.wch()
        XCTAssertEqual(InterfaceChoice.groups(known([interface(1, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages)])), [])
        let ilitekTouch = KnownInterface(interface(9, at: ilitekLocation, try Panels.descriptor(Panels.ilitek(), "touchscreen")), arrival: 9)
        XCTAssertNil(InterfaceChoice.mouseSibling(of: ilitekTouch, among: known([
            interface(1, at: wchLocation, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages),
        ])))
    }

    func testTheTouchscreenInterfaceWithMoreFingerSlotsIsUsed() throws {
        let strip = try Panels.wch()
        let one = interface(1, at: wchLocation, Panels.oneFingerTouchscreen)
        let ten = interface(2, at: wchLocation, try Panels.descriptor(strip, "touchscreen"))
        XCTAssertEqual(KnownInterface(one, arrival: 0).contactSlots, 1)
        XCTAssertEqual(InterfaceChoice.groups(known([one, ten])), [InterfaceGroup(touch: 2, mouse: nil)])
        XCTAssertEqual(InterfaceChoice.groups(known([ten, one])), [InterfaceGroup(touch: 2, mouse: nil)])

        // On a tie, the first to arrive.
        let alsoTen = interface(3, at: wchLocation, try Panels.descriptor(strip, "touchscreen"))
        XCTAssertEqual(InterfaceChoice.groups(known([alsoTen, ten])), [InterfaceGroup(touch: 3, mouse: nil)])
    }

    /// IOKit lists the interface as a touchscreen, but its descriptor can't be read: it is still a
    /// touchscreen, with no finger slots known, and a readable one at the same location wins.
    func testATouchscreenWhoseDescriptorCannotBeRead() throws {
        let unreadable = interface(1, at: wchLocation, [0xFF, 0xFF], listsTouchScreen: true)
        let none = interface(2, at: ilitekLocation, nil, listsTouchScreen: true)
        XCTAssertNil(KnownInterface(unreadable, arrival: 0).decoder)
        XCTAssertEqual(InterfaceChoice.groups(known([unreadable, none])),
                       [InterfaceGroup(touch: 1, mouse: nil), InterfaceGroup(touch: 2, mouse: nil)])
        let readable = interface(3, at: wchLocation, Panels.oneFingerTouchscreen)
        XCTAssertEqual(InterfaceChoice.groups(known([unreadable, readable])), [InterfaceGroup(touch: 3, mouse: nil)])
    }

    func testAMouseWhoseDescriptorCannotBeReadIsNoSibling() throws {
        let strip = try Panels.wch()
        let touch = interface(1, at: wchLocation, try Panels.descriptor(strip, "touchscreen"))
        let mouse = interface(2, at: wchLocation, nil, usages: [.mouse])
        XCTAssertEqual(InterfaceChoice.groups(known([touch, mouse])), [InterfaceGroup(touch: 1, mouse: nil)])
    }

    /// Location 0 is no USB location: nothing there is grouped with anything.
    func testNoLocationNoSiblings() throws {
        let strip = try Panels.wch()
        let interfaces = known([
            interface(1, at: 0, try Panels.descriptor(strip, "touchscreen")),
            interface(2, at: 0, try Panels.descriptor(strip, "mouse"), usages: Panels.wchMouseUsages),
            interface(3, at: 0, try Panels.descriptor(strip, "touchscreen")),
        ])
        XCTAssertEqual(InterfaceChoice.groups(interfaces), [InterfaceGroup(touch: 1, mouse: nil), InterfaceGroup(touch: 3, mouse: nil)])
        XCTAssertNil(InterfaceChoice.mouseSibling(of: interfaces[0], among: interfaces))
    }

    func testReportBuffersHaveTheSurveyToolsMargin() throws {
        let strip = try Panels.wch(), ilitek = try Panels.ilitek()
        let wchTouch = try Panels.decoder(strip, "touchscreen")
        XCTAssertEqual(wchTouch.maxInputReportLength, 54)
        XCTAssertEqual(InterfaceChoice.reportBufferSize(decoder: wchTouch, maxInputReportSize: 54), 80)
        XCTAssertEqual(InterfaceChoice.reportBufferSize(decoder: try Panels.decoder(strip, "mouse"), maxInputReportSize: 7), 80)
        XCTAssertEqual(InterfaceChoice.reportBufferSize(decoder: try Panels.decoder(ilitek, "touchscreen"), maxInputReportSize: 64), 80)
        XCTAssertEqual(InterfaceChoice.reportBufferSize(decoder: nil, maxInputReportSize: 200), 216, "IOKit's size when it is larger")
        XCTAssertEqual(InterfaceChoice.reportBufferSize(decoder: nil, maxInputReportSize: nil), 80)
    }

    func testHostClock() {
        let timebase = mach_timebase_info_data_t(numer: 125, denom: 3)
        XCTAssertEqual(HostClock.seconds(fromMachTime: 24_000_000, timebase: timebase), 1.0, accuracy: 1e-12)
        XCTAssertEqual(HostClock.reportTime(timestamp: 24_000_000, now: 1.5, timebase: timebase), 1.0, accuracy: 1e-12)
        XCTAssertEqual(HostClock.reportTime(timestamp: 0, now: 1.5, timebase: timebase), 1.5, "no timestamp: now")
        XCTAssertEqual(HostClock.reportTime(timestamp: 24_000_000 * 10, now: 1.5, timebase: timebase), 1.5, "far ahead: now")
        // On this Mac, the HID clock is the clock `systemUptime` reads.
        let now = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(HostClock.seconds(fromMachTime: mach_absolute_time()), now, accuracy: 0.5)
    }
}
