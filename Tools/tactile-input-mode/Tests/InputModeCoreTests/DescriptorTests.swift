import XCTest
@testable import InputModeCore

final class DescriptorTests: XCTestCase {
    private func parse(_ hex: String) throws -> HIDDescriptor { try HIDDescriptor(bytes(hex)) }

    func testStripTouchscreenDeclaresTwoFeatureReportsAndOneInputReport() throws {
        let d = try parse(Fixtures.stripTouchscreen)
        XCTAssertTrue(d.usesReportIDs)
        XCTAssertEqual(d.applications, [Usages.touchScreen, Usages.deviceConfiguration])
        XCTAssertEqual(d.reportIDs(.input), [0x0D])
        XCTAssertEqual(d.reportIDs(.feature), [0x0A, 0x21])
        XCTAssertEqual(d.reportIDs(.output), [])
        XCTAssertEqual(d.reportLength(.input, 0x0D), 54)
        XCTAssertEqual(d.reportLength(.feature, 0x0A), 2)
        XCTAssertEqual(d.reportLength(.feature, 0x21), 3)
    }

    func testStripDeviceConfigurationReportHoldsInputModeThenDeviceIndex() throws {
        let d = try parse(Fixtures.stripTouchscreen)
        let fields = d.fields(.feature, 0x21)
        XCTAssertEqual(fields.count, 1)
        let field = try XCTUnwrap(fields.first)
        XCTAssertEqual(field.bitOffset, 0)
        XCTAssertEqual(field.bitSize, 8)
        XCTAssertEqual(field.count, 2)
        XCTAssertEqual(field.usage(at: 0), Usages.inputMode)
        XCTAssertEqual(field.usage(at: 1), Usages.deviceIndex)
        XCTAssertEqual(field.logicalMin, 0)
        XCTAssertEqual(field.logicalMax, 10)
        XCTAssertFalse(field.isConstant)
        XCTAssertTrue(field.isVariable)
        XCTAssertEqual(field.application, Usages.deviceConfiguration)
    }

    func testStripDeclaresNoSwitchesNoLatencyModeAndNoCertificationBlob() throws {
        let d = try parse(Fixtures.stripTouchscreen)
        for usage in [Usages.surfaceSwitch, Usages.buttonSwitch, Usages.latencyMode, Usages.certificationBlob] {
            XCTAssertEqual(d.reports(.feature, containing: usage), [], "\(usage)")
        }
        XCTAssertEqual(d.reports(.feature, containing: Usages.inputMode), [0x21])
        XCTAssertEqual(d.reports(.feature, containing: Usages.contactCountMaximum), [0x0A])
    }

    func testStripTouchReportHasTenTipSwitches() throws {
        let d = try parse(Fixtures.stripTouchscreen)
        XCTAssertEqual(d.elements(.input, 0x0D, usage: Usages.tipSwitch).count, 10)
        XCTAssertEqual(d.elements(.input, 0x0D, usage: Usages.contactID).count, 10)
    }

    func testStripMouseInterface() throws {
        let d = try parse(Fixtures.stripMouse)
        XCTAssertEqual(d.applications, [Usages.mouse])
        XCTAssertEqual(d.reportIDs(.input), [0x07])
        XCTAssertEqual(d.reportLength(.input, 0x07), 7)
        XCTAssertEqual(d.reportIDs(.feature), [])
        XCTAssertEqual(d.reportIDs(.output), [])
    }

    func testStripVendorInterfaceHasOnlyVendorUsages() throws {
        let d = try parse(Fixtures.stripVendor)
        XCTAssertEqual(d.applications, [HIDUsage(0xFF0A, 0xFF)])
        XCTAssertEqual(d.reportIDs(.input), [0x50])
        XCTAssertEqual(d.reportIDs(.output), [0x51])
        XCTAssertEqual(d.reportIDs(.feature), [])
        XCTAssertEqual(d.reportLength(.output, 0x51), 64)
        // Logical Maximum 0xFF00 with a minimum of 0 is unsigned: 65280, not -256.
        XCTAssertEqual(d.fields(.output, 0x51).first?.logicalMax, 65280)
    }

    func testIlitekHasTheCertificationBlobAndNoInputMode() throws {
        let d = try parse(Fixtures.ilitekTouchscreen)
        XCTAssertFalse(d.reports(.feature, containing: Usages.certificationBlob).isEmpty)
        XCTAssertEqual(d.reports(.feature, containing: Usages.inputMode), [])
    }

    func testReadsAFieldValueFromARealMouseReport() throws {
        let d = try parse(Fixtures.stripMouse)
        let report = bytes(Fixtures.stripMousePressed)
        let x = try XCTUnwrap(d.elements(.input, 0x07, usage: HIDUsage(0x01, 0x30)).first)
        XCTAssertEqual(d.value(of: x.field, element: x.element, in: report), 8004)   // as the survey decoded it
        let button = try XCTUnwrap(d.elements(.input, 0x07, usage: Usages.button1).first)
        XCTAssertEqual(d.value(of: button.field, element: button.element, in: report), 1)
    }

    func testTheUsagePageInEffectAtTheMainItemApplies() throws {
        // Usage 0x30 is declared under page 0x01, but the page is 0x0D when the Input item comes.
        let d = try HIDDescriptor([
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
            0x05, 0x01, 0x09, 0x30, 0x05, 0x0D, 0x15, 0x00, 0x25, 0x01, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
            0xC0,
        ])
        XCTAssertEqual(d.fields(.input, 0).first?.usage(at: 0), HIDUsage(0x0D, 0x30))
    }

    func testAnExtendedUsageKeepsItsOwnPage() throws {
        let d = try HIDDescriptor([
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
            0x0B, 0x30, 0x00, 0x01, 0x00,   // Usage 0x0001_0030 (X), four bytes
            0x15, 0x00, 0x25, 0x01, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02,
            0xC0,
        ])
        XCTAssertEqual(d.fields(.input, 0).first?.usage(at: 0), HIDUsage(0x01, 0x30))
    }

    func testAnAbsurdReportSizeIsAnErrorNotACrash() {
        XCTAssertThrowsError(try HIDDescriptor([
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
            0x77, 0xFF, 0xFF, 0xFF, 0xFF,   // Report Size 4294967295
            0x97, 0xFF, 0xFF, 0xFF, 0xFF,   // Report Count 4294967295
            0x81, 0x02,
            0xC0,
        ]))
    }

    func testAReportLongerThanAnyRealOneIsAnError() {
        // 256 bits × 12,288 elements: each value is allowed alone, the report is not.
        XCTAssertThrowsError(try HIDDescriptor([
            0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01,
            0x76, 0x00, 0x01, 0x96, 0x00, 0x30, 0x81, 0x02,
            0xC0,
        ]))
    }

    func testATruncatedItemIsAnError() {
        XCTAssertThrowsError(try HIDDescriptor([0x05, 0x0D, 0x09]))   // Usage with its data byte missing
    }

    func testAnUnbalancedEndCollectionIsAnError() {
        XCTAssertThrowsError(try HIDDescriptor([0xC0]))
    }
}
