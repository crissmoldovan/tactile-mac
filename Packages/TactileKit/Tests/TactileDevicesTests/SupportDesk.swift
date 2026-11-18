// The desk the support check's tests use: the two surveyed panels as the HID system describes their
// interfaces, a touchscreen that is only a mouse (made by hand), a pen, an ordinary mouse, an Apple
// trackpad and a device built into the Mac.

import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

enum SupportDesk {
    static let stripTouchID: HIDInterfaceID = 11, stripMouseID: HIDInterfaceID = 12, stripVendorID: HIDInterfaceID = 13
    static let ilitekTouchID: HIDInterfaceID = 21, ilitekMouseID: HIDInterfaceID = 22
    static let pointerID: HIDInterfaceID = 31
    static let penID: HIDInterfaceID = 41
    static let trackpadID: HIDInterfaceID = 51
    static let builtInID: HIDInterfaceID = 61
    static let relativeMouseID: HIDInterfaceID = 71

    static let pointerLocation: UInt32 = 0x0120_0000
    static let penLocation: UInt32 = 0x0130_0000

    static let stripSerial = "TEST-SERIAL-0001"
    static let ilitekSerial = "V06.00.00.00"
    static let pointerSerial = "POINTER-SERIAL-0042"

    static func strip() throws -> [HIDInterfaceDescription] {
        let panel = try Panels.wch()
        func made(_ id: HIDInterfaceID, _ key: String, _ usages: [HIDUsage], size: Int) throws -> HIDInterfaceDescription {
            HIDInterfaceDescription(
                id: id, locationID: wchLocation, vendorID: Panels.wchVendorID, productID: Panels.wchProductID,
                serial: stripSerial, product: "TouchScreen", usages: usages, descriptor: try Panels.descriptor(panel, key),
                maxInputReportSize: size, manufacturer: "wch.cn")
        }
        return [
            try made(stripTouchID, "touchscreen", [.touchScreen, HIDUsage(page: 0x0D, usage: 0x0E)], size: 54),
            try made(stripMouseID, "mouse", Panels.wchMouseUsages, size: 7),
            try made(stripVendorID, "vendor-ff0a", [HIDUsage(page: 0xFF0A, usage: 0xFF)], size: 64),
        ]
    }

    static func ilitek() throws -> [HIDInterfaceDescription] {
        let panel = try Panels.ilitek()
        return [
            HIDInterfaceDescription(
                id: ilitekTouchID, locationID: ilitekLocation, vendorID: Panels.ilitekVendorID,
                productID: Panels.ilitekProductID, serial: ilitekSerial, product: "ILITEK-TP", usages: [.touchScreen],
                descriptor: try Panels.descriptor(panel, "touchscreen"), maxInputReportSize: 64, manufacturer: "ILITEK"),
            HIDInterfaceDescription(
                id: ilitekMouseID, locationID: ilitekLocation, vendorID: Panels.ilitekVendorID,
                productID: Panels.ilitekProductID, serial: ilitekSerial, product: "ILITEK-TP",
                usages: Panels.ilitekMouseUsages, descriptor: try Panels.descriptor(panel, "mouse"), maxInputReportSize: 64,
                manufacturer: "ILITEK"),
        ]
    }

    /// A touchscreen that is only a mouse: one Pointer interface with an absolute X and Y.
    static let pointerVendorID = 0x1234, pointerProductID = 0x5678
    static func pointer() -> HIDInterfaceDescription {
        HIDInterfaceDescription(
            id: pointerID, locationID: pointerLocation, vendorID: pointerVendorID, productID: pointerProductID,
            serial: pointerSerial, product: "Panel \(pointerSerial)", usages: [.pointer],
            descriptor: HandMadeDescriptors.absolutePointer, maxInputReportSize: 6, manufacturer: "Example Panels")
    }

    /// A pen display's pen interface: a Pen collection and a Mouse collection in one interface.
    static func pen() throws -> HIDInterfaceDescription {
        HIDInterfaceDescription(
            id: penID, locationID: penLocation, vendorID: 0x256c, productID: 0x006d, serial: "", product: "Pen Display",
            usages: [.pen, .mouse], descriptor: try Panels.penAndMouse(), maxInputReportSize: 7, manufacturer: "Example Pens")
    }

    /// Apple's own trackpad: a digitiser with an absolute pointer, never offered.
    static func trackpad() throws -> HIDInterfaceDescription {
        HIDInterfaceDescription(
            id: trackpadID, locationID: 0x0140_0000, vendorID: 0x05ac, productID: 0x0265, serial: "", product: "Magic Trackpad",
            usages: [HIDUsage(page: 0x0D, usage: 0x05), .mouse], descriptor: try Panels.descriptor(Panels.wch(), "mouse"),
            maxInputReportSize: 7, manufacturer: "Apple Inc.")
    }

    /// A pointer built into the Mac, by another maker: never offered.
    static func builtIn() -> HIDInterfaceDescription {
        HIDInterfaceDescription(
            id: builtInID, locationID: 0, vendorID: 0x0000, productID: 0x0000, serial: "", product: "Internal Pointer",
            usages: [.pointer], descriptor: HandMadeDescriptors.absolutePointer, maxInputReportSize: 6, isBuiltIn: true)
    }

    /// An ordinary mouse: relative, never offered.
    static func relativeMouse() -> HIDInterfaceDescription {
        HIDInterfaceDescription(
            id: relativeMouseID, locationID: 0x0150_0000, vendorID: 0x046d, productID: 0xc077, serial: "", product: "USB Mouse",
            usages: [.mouse, .pointer], descriptor: HandMadeDescriptors.relativeMouse, maxInputReportSize: 3,
            manufacturer: "Logitech")
    }

    static func all() throws -> [HIDInterfaceDescription] {
        try strip() + ilitek() + [pointer(), try pen(), try trackpad(), builtIn(), relativeMouse()]
    }
}
