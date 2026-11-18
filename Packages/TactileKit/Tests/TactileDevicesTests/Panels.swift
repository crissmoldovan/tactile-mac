// The two surveyed panels, as the device layer's tests need them: their interfaces' descriptors
// and decoders, and hand-made reports in each interface's own format.

import CoreGraphics
import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

enum Panels {
    /// The wch.cn "TouchScreen" (27c0:0859), on the 12.3-inch strip: mouse, touchscreen and vendor interfaces.
    static let wchVendorID = 0x27c0, wchProductID = 0x0859
    /// The ILITEK "ILITEK-TP" (222a:0001): mouse and touchscreen interfaces.
    static let ilitekVendorID = 0x222a, ilitekProductID = 0x0001

    /// The usages IOKit lists for each panel's mouse interface, as both surveys recorded them:
    /// the strip's Mouse and Pointer; the ILITEK's Mouse, Pointer and a vendor-defined 0xFF00/0x01.
    static let wchMouseUsages: [HIDUsage] = [.mouse, .pointer]
    static let ilitekMouseUsages: [HIDUsage] = [.mouse, .pointer, HIDUsage(page: 0xFF00, usage: 0x01)]

    /// The wch.cn as survey A recorded it: only its section of that survey is used.
    static func wch() throws -> SurveyFixtures.Touchscreen {
        try XCTUnwrap(SurveyFixtures.surveyA.touchscreen(vendorID: wchVendorID, productID: wchProductID), "no wch.cn in survey A")
    }

    /// The ILITEK as survey B recorded it: only its section of that survey is used.
    static func ilitek() throws -> SurveyFixtures.Touchscreen {
        try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: ilitekVendorID, productID: ilitekProductID), "no ILITEK in survey B")
    }

    static func descriptor(_ panel: SurveyFixtures.Touchscreen, _ key: String) throws -> [UInt8] {
        try XCTUnwrap(panel.interfaces.first { $0.key == key }, "no \(key) interface").descriptor
    }

    static func decoder(_ panel: SurveyFixtures.Touchscreen, _ key: String) throws -> InterfaceDecoder {
        try XCTUnwrap(InterfaceDecoder(descriptor: descriptor(panel, key)), "the \(key) descriptor did not parse")
    }

    static func take(_ panel: SurveyFixtures.Touchscreen, _ number: Int) throws -> SurveyFixtures.Take {
        try XCTUnwrap(panel.takes.first { $0.number == number }, "no take \(number)")
    }

    // MARK: Hand-made reports

    /// An ILITEK mouse-interface report: report ID 4, five buttons, then absolute X (0…16384) and
    /// Y (0…9600), 16 bits each, little-endian.
    static func ilitekMouse(buttons: UInt8, x: Double, y: Double) -> [UInt8] {
        let rawX = UInt16(x * 16384), rawY = UInt16(y * 9600)
        return [0x04, buttons, UInt8(rawX & 0xFF), UInt8(rawX >> 8), UInt8(rawY & 0xFF), UInt8(rawY >> 8)]
    }

    /// A wch.cn mouse-interface report: report ID 7, three buttons, absolute X (0…16383) and Y
    /// (0…9599), 16 bits each, then the wheel.
    static func wchMouse(buttons: UInt8, x: Double, y: Double) -> [UInt8] {
        let rawX = UInt16(x * 16383), rawY = UInt16(y * 9599)
        return [0x07, buttons, UInt8(rawX & 0xFF), UInt8(rawX >> 8), UInt8(rawY & 0xFF), UInt8(rawY >> 8), 0]
    }

    /// A wch.cn touch-interface report (report ID 0x0D, 54 bytes) with one finger down in slot 0.
    /// The panel never sent one; this is its descriptor's layout: ten 5-byte finger collections
    /// (tip, contact ID, X, Y), then Scan Time and Contact Count.
    static func wchTouch(id: UInt8, x: Double, y: Double) -> [UInt8] {
        let rawX = UInt16(x * 16383), rawY = UInt16(y * 9599)
        var bytes = [UInt8](repeating: 0, count: 54)
        bytes[0] = 0x0D
        bytes[1] = 0x01 | (id << 4)
        bytes[2] = UInt8(rawX & 0xFF); bytes[3] = UInt8(rawX >> 8)
        bytes[4] = UInt8(rawY & 0xFF); bytes[5] = UInt8(rawY >> 8)
        bytes[53] = 1
        return bytes
    }

    /// A touchscreen interface with one finger collection (report ID 1): tip, a 7-bit pad, an
    /// 8-bit contact ID, 16-bit X and Y (0…4095), then an 8-bit Contact Count.
    static let oneFingerTouchscreen: [UInt8] = [
        0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x01,
        0x09, 0x22, 0xA1, 0x02,
        0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
        0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
        0x09, 0x51, 0x25, 0x0F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
        0x05, 0x01, 0x09, 0x30, 0x26, 0xFF, 0x0F, 0x75, 0x10, 0x95, 0x01, 0x81, 0x02,
        0x09, 0x31, 0x81, 0x02,
        0xC0,
        0x05, 0x0D, 0x09, 0x54, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
        0xC0,
    ]

    /// `oneFingerTouchscreen` with two feature reports worth reading, in this descriptor order:
    /// 0x03, Contact Count Maximum (2 bytes), then 0x02, the 256-byte certification blob (257 bytes).
    static let twoFeatureReportsTouchscreen: [UInt8] = Array(oneFingerTouchscreen.dropLast()) + [
        0x85, 0x03, 0x05, 0x0D, 0x09, 0x55, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02,
        0x85, 0x02, 0x06, 0x00, 0xFF, 0x09, 0xC5, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x96, 0x00, 0x01, 0xB1, 0x02,
        0xC0,
    ]

    /// A pen's interface, as a pen display has: a Pen collection (report 2: tip, X, Y) followed by
    /// the wch.cn's Mouse collection. Its descriptor reads as a mouse's.
    static func penAndMouse() throws -> [UInt8] {
        let pen: [UInt8] = [
            0x05, 0x0D, 0x09, 0x02, 0xA1, 0x01, 0x85, 0x02,
            0x09, 0x20, 0xA1, 0x00,
            0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
            0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
            0x05, 0x01, 0x09, 0x30, 0x26, 0xFF, 0x0F, 0x75, 0x10, 0x95, 0x01, 0x81, 0x02,
            0x09, 0x31, 0x81, 0x02,
            0xC0, 0xC0,
        ]
        return pen + (try descriptor(wch(), "mouse"))
    }

    /// A combined keyboard and mouse interface: a Keyboard collection (report 1: modifiers and six
    /// keys) followed by the wch.cn's Mouse collection. Its descriptor reads as a mouse's.
    static func keyboardAndMouse() throws -> [UInt8] {
        let keyboard: [UInt8] = [
            0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x85, 0x01,
            0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
            0x95, 0x06, 0x75, 0x08, 0x26, 0xFF, 0x00, 0x19, 0x00, 0x2A, 0xFF, 0x00, 0x81, 0x00,
            0xC0,
        ]
        return keyboard + (try descriptor(wch(), "mouse"))
    }

    /// One interface that is both: the wch.cn's touchscreen descriptor followed by its mouse
    /// descriptor. Many panels put a mouse collection inside their touchscreen interface; this one
    /// decodes report 0x0D as touch and report 0x07 as pointer.
    static func combinedDecoder() throws -> InterfaceDecoder {
        let panel = try wch()
        let bytes = try descriptor(panel, "touchscreen") + descriptor(panel, "mouse")
        return try XCTUnwrap(InterfaceDecoder(descriptor: bytes), "the combined descriptor did not parse")
    }
}
