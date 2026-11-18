import XCTest
@testable import InputModeCore

final class FeatureWriteTests: XCTestCase {
    private var strip: HIDDescriptor { get throws { try HIDDescriptor(bytes(Fixtures.stripTouchscreen)) } }

    func testTheWholeDeviceConfigurationReportForMultiTouch() throws {
        let plan = try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21, values: [.inputMode: 2])
        XCTAssertEqual(plan.reportID, 0x21)
        XCTAssertEqual(plan.bytes, [0x21, 0x02, 0x00])   // Device Index 0: "all collections"
        XCTAssertEqual(plan.settings.map(\.setting), [.inputMode, .deviceIndex])
        XCTAssertEqual(plan.settings.map(\.value), [2, 0])
        XCTAssertEqual(plan.summary, "feature report 0x21 = 21 02 00 (Input Mode 2, Device Index 0)")
    }

    func testMouseEmulationAndSingleInput() throws {
        XCTAssertEqual(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21, values: [.inputMode: 0]).bytes,
                       [0x21, 0x00, 0x00])
        XCTAssertEqual(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21, values: [.inputMode: 1]).bytes,
                       [0x21, 0x01, 0x00])
    }

    func testTheInputModeReportIsFound() throws {
        XCTAssertEqual(FeatureWritePlanner.inputModeReport(in: try strip), 0x21)
        XCTAssertNil(FeatureWritePlanner.inputModeReport(in: try HIDDescriptor(bytes(Fixtures.ilitekTouchscreen))))
    }

    func testTheStripHasNoSwitchReports() throws {
        XCTAssertEqual(FeatureWritePlanner.switchReports(in: try strip), [])
    }

    func testNothingIsEverPlannedForTheVendorInterface() throws {
        let vendor = try HIDDescriptor(bytes(Fixtures.stripVendor))
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .vendor, descriptor: vendor, reportID: 0x51, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .notATouchscreenInterface(.vendor))
        }
        // Even if the vendor interface were mistaken for a touchscreen, its descriptor has no Touch
        // Screen collection, and is refused for that.
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: vendor, reportID: 0x51, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .noTouchScreenCollection)
        }
    }

    /// A Touch Screen application collection with one input report (0x01: a tip switch and padding),
    /// for the synthetic descriptors below.
    private let touchScreenCollection: [UInt8] = [
        0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x01,
        0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
        0x75, 0x07, 0x81, 0x03,
        0xC0,
    ]

    func testAnOutputReportIsNeverPlanned() throws {
        // A touchscreen with an output report 0x02 holding Input Mode: only feature reports are written.
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x02,
            0x09, 0x52, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0x91, 0x02,
            0xC0,
        ])
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x02, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .reportNotDeclared(0x02))
        }
    }

    func testTheMouseInterfaceIsNeverWritten() throws {
        let mouse = try HIDDescriptor(bytes(Fixtures.stripMouse))
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .mouse, descriptor: mouse, reportID: 0x07, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .notATouchscreenInterface(.mouse))
        }
    }

    func testAReportWithAFieldOutsideTheAllowListIsRefused() throws {
        // Report 0x0A holds Contact Count Maximum, which is read, never written.
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x0A, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .fieldNotAllowed(Usages.contactCountMaximum))
        }
    }

    func testAVendorUsageInAFeatureReportIsRefused() throws {
        // A touchscreen whose Device Configuration report also carries a vendor byte.
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x03,
            0x09, 0x52, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02,
            0x06, 0x00, 0xFF, 0x09, 0x01, 0xB1, 0x02,
            0xC0,
        ])
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x03, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .fieldNotAllowed(HIDUsage(0xFF00, 0x01)))
        }
    }

    func testAnUndeclaredReportIsRefused() throws {
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x22, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .reportNotDeclared(0x22))
        }
    }

    func testAValueOutsideTheDeclaredRangeIsRefused() throws {
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21, values: [.inputMode: 11])) {
            XCTAssertEqual($0 as? WriteRefusal, .valueOutOfRange(.inputMode, value: 11, min: 0, max: 10))
        }
    }

    func testASettingTheReportDoesNotHoldIsRefused() throws {
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21,
                                                          values: [.inputMode: 2, .surfaceSwitch: 1])) {
            XCTAssertEqual($0 as? WriteRefusal, .notInReport(.surfaceSwitch, 0x21))
        }
    }

    func testInputModeHasNoDefault() throws {
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: strip, reportID: 0x21, values: [:])) {
            XCTAssertEqual($0 as? WriteRefusal, .noValue(.inputMode))
        }
    }

    func testSurfaceAndButtonSwitchesAreWrittenOnAsLinuxDoes() throws {
        // A precision-touchpad style Device Configuration report: Surface Switch and Button Switch,
        // one bit each, then six bits of padding.
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x05,
            0x09, 0x23, 0xA1, 0x02,
            0x09, 0x57, 0x09, 0x58, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x02, 0xB1, 0x02,
            0x75, 0x06, 0x95, 0x01, 0xB1, 0x03,
            0xC0, 0xC0,
        ])
        XCTAssertEqual(FeatureWritePlanner.switchReports(in: d), [0x05])
        let plan = try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x05, values: [:])
        XCTAssertEqual(plan.bytes, [0x05, 0x03])
        XCTAssertEqual(plan.settings.map(\.setting), [.surfaceSwitch, .buttonSwitch])
    }

    func testAnArrayFieldIsRefused() throws {
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x03,
            0x09, 0x52, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x00,   // Feature (Data, Array, Abs)
            0xC0,
        ])
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x03, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .arrayField(0x03))
        }
    }

    func testAValueTooWideForItsFieldIsRefusedNotCut() throws {
        // Declared range 0...10, but only two bits: 5 would be sent as 1.
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x03,
            0x09, 0x52, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x02, 0x95, 0x01, 0xB1, 0x02,
            0x75, 0x06, 0x95, 0x01, 0xB1, 0x03,
            0xC0,
        ])
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x03, values: [.inputMode: 5])) {
            XCTAssertEqual($0 as? WriteRefusal, .valueTooWide(.inputMode, value: 5, bits: 2))
        }
        XCTAssertEqual(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x03, values: [.inputMode: 2]).bytes,
                       [0x03, 0x02])
    }

    func testADescriptorWithoutReportIDsIsWrittenWithoutAnIDByte() throws {
        let d = try HIDDescriptor([
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
            0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
            0x75, 0x07, 0x81, 0x03,
            0xC0,
            0x09, 0x0E, 0xA1, 0x01,
            0x09, 0x52, 0x09, 0x53, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x02, 0xB1, 0x02,
            0xC0,
        ])
        XCTAssertFalse(d.usesReportIDs)
        let plan = try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0, values: [.inputMode: 2])
        XCTAssertEqual(plan.bytes, [0x02, 0x00])
        XCTAssertEqual(FeatureWritePlanner.inputModeReport(in: d), 0)
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x21, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .reportNotDeclared(0x21))
        }
    }

    func testLatencyModeIsNotWritten() throws {
        // Not in the rule, and the strip doesn't declare it: a report holding it is refused whole.
        let d = try HIDDescriptor(touchScreenCollection + [
            0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x03,
            0x09, 0x52, 0x09, 0x60, 0x15, 0x00, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x02, 0xB1, 0x02,
            0xC0,
        ])
        XCTAssertThrowsError(try FeatureWritePlanner.plan(role: .touchscreen, descriptor: d, reportID: 0x03, values: [.inputMode: 2])) {
            XCTAssertEqual($0 as? WriteRefusal, .fieldNotAllowed(Usages.latencyMode))
        }
    }

    func testInterfaceRoles() {
        XCTAssertEqual(InterfaceRole(primaryUsagePage: 0x0D, primaryUsage: 0x04), .touchscreen)
        XCTAssertEqual(InterfaceRole(primaryUsagePage: 0x01, primaryUsage: 0x02), .mouse)
        XCTAssertEqual(InterfaceRole(primaryUsagePage: 0x01, primaryUsage: 0x01), .mouse)
        XCTAssertEqual(InterfaceRole(primaryUsagePage: 0xFF0A, primaryUsage: 0xFF), .vendor)
        XCTAssertEqual(InterfaceRole(primaryUsagePage: 0x01, primaryUsage: 0x06), .other)
    }
}
