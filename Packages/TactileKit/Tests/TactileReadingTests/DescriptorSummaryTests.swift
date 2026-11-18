import XCTest
import TactileReading
import TactileTestSupport

/// What a descriptor says about its interface, read only, as the support check reports it: the two
/// surveyed panels' interfaces, a mouse-only pointer and a relative mouse made by hand.
final class DescriptorSummaryTests: XCTestCase {

    private func descriptor(_ survey: SurveyFixtures.Survey, vendorID: Int, productID: Int, _ key: String) throws -> [UInt8] {
        let panel = try XCTUnwrap(survey.touchscreen(vendorID: vendorID, productID: productID), "no \(vendorID)")
        return try XCTUnwrap(panel.interfaces.first { $0.key == key }, "no \(key) interface").descriptor
    }

    private func strip(_ key: String) throws -> DescriptorSummary {
        DescriptorSummary(descriptor: try descriptor(SurveyFixtures.surveyA, vendorID: 0x27c0, productID: 0x0859, key))
    }

    private func ilitek(_ key: String) throws -> DescriptorSummary {
        DescriptorSummary(descriptor: try descriptor(SurveyFixtures.surveyB, vendorID: 0x222a, productID: 0x0001, key))
    }

    private typealias Collection = DescriptorSummary.Collection
    private typealias Report = DescriptorSummary.Report

    // MARK: - The surveyed panels

    func testTheStripsTouchscreenInterface() throws {
        let summary = try strip("touchscreen")
        XCTAssertEqual(summary.applicationCollections, [Collection(page: 0x0D, usage: 0x04), Collection(page: 0x0D, usage: 0x0E)])
        XCTAssertTrue(summary.usesReportIDs)
        XCTAssertEqual(summary.inputReports, [Report(id: 0x0D, length: 54)])
        XCTAssertEqual(summary.outputReports, [])
        XCTAssertEqual(summary.featureReports, [Report(id: 0x0A, length: 2), Report(id: 0x21, length: 3)])
        XCTAssertEqual(summary.inputModeReportID, 0x21)
        XCTAssertNil(summary.certificationBlobReportID)
        XCTAssertEqual(summary.contactCountMaximumReportID, 0x0A)
        XCTAssertTrue(summary.isDigitizer)
        XCTAssertFalse(summary.hasAbsolutePointer, "a finger's X and Y are not a pointer's")
        XCTAssertEqual(summary.problems, [])
    }

    func testTheILITEKsTouchscreenInterface() throws {
        let summary = try ilitek("touchscreen")
        XCTAssertEqual(summary.applicationCollections, [Collection(page: 0x0D, usage: 0x04)])
        XCTAssertEqual(summary.inputReports, [Report(id: 0x04, length: 64)])
        XCTAssertEqual(summary.featureReports, [Report(id: 0x06, length: 258)])
        XCTAssertNil(summary.inputModeReportID, "the ILITEK has no Input Mode setting")
        XCTAssertEqual(summary.certificationBlobReportID, 0x06)
        XCTAssertEqual(summary.contactCountMaximumReportID, 0x06)
        XCTAssertTrue(summary.isDigitizer)
        XCTAssertFalse(summary.hasAbsolutePointer)
    }

    func testTheMouseInterfacesAreAbsolutePointers() throws {
        let stripMouse = try strip("mouse")
        XCTAssertEqual(stripMouse.applicationCollections, [Collection(page: 0x01, usage: 0x02)])
        XCTAssertEqual(stripMouse.inputReports, [Report(id: 0x07, length: 7)])
        XCTAssertTrue(stripMouse.hasAbsolutePointer)
        XCTAssertFalse(stripMouse.isDigitizer)

        let ilitekMouse = try ilitek("mouse")
        XCTAssertEqual(ilitekMouse.applicationCollections, [Collection(page: 0x01, usage: 0x02), Collection(page: 0xFF00, usage: 0x01)])
        XCTAssertEqual(ilitekMouse.inputReports, [Report(id: 0x03, length: 64), Report(id: 0x04, length: 6)])
        XCTAssertEqual(ilitekMouse.outputReports, [Report(id: 0x03, length: 64)])
        XCTAssertEqual(ilitekMouse.featureReports, [])
        XCTAssertTrue(ilitekMouse.hasAbsolutePointer)
    }

    func testTheStripsVendorInterface() throws {
        let summary = try strip("vendor-ff0a")
        XCTAssertEqual(summary.applicationCollections, [Collection(page: 0xFF0A, usage: 0xFF)])
        XCTAssertEqual(summary.inputReports, [Report(id: 0x50, length: 64)])
        XCTAssertEqual(summary.outputReports, [Report(id: 0x51, length: 64)])
        XCTAssertFalse(summary.isDigitizer)
        XCTAssertFalse(summary.hasAbsolutePointer)
    }

    // MARK: - Made by hand

    func testAMouseOnlyPointer() {
        let summary = DescriptorSummary(descriptor: HandMadeDescriptors.absolutePointer)
        XCTAssertEqual(summary.applicationCollections, [Collection(page: 0x01, usage: 0x01)])
        XCTAssertEqual(summary.inputReports, [Report(id: 0x02, length: 6)])
        XCTAssertTrue(summary.hasAbsolutePointer)
        XCTAssertFalse(summary.isDigitizer)
        XCTAssertNil(summary.inputModeReportID)
    }

    func testARelativeMouseIsNoAbsolutePointer() {
        let summary = DescriptorSummary(descriptor: HandMadeDescriptors.relativeMouse)
        XCTAssertEqual(summary.applicationCollections, [Collection(page: 0x01, usage: 0x02)])
        XCTAssertFalse(summary.usesReportIDs)
        XCTAssertEqual(summary.inputReports, [Report(id: 0, length: 3)])
        XCTAssertFalse(summary.hasAbsolutePointer)
    }

    /// An absolute X and Y outside any Pointer or Mouse collection, as a joystick has, are no pointer.
    func testAnAbsoluteXAndYOutsideAPointerAreNoPointer() {
        XCTAssertFalse(DescriptorSummary(descriptor: HandMadeDescriptors.joystick).hasAbsolutePointer)
    }

    func testAnUnusableDescriptorIsSummarisedByItsProblem() {
        let tooLong = [UInt8](repeating: 0, count: 65_536)
        let summary = DescriptorSummary(descriptor: tooLong)
        XCTAssertEqual(summary.problems, ["the descriptor is longer than 65535 bytes"])
        XCTAssertEqual(summary.applicationCollections, [])
        XCTAssertEqual(summary.inputReports, [])

        let deep = Array(repeating: [UInt8]([0xA1, 0x01]), count: 70).flatMap { $0 }
        XCTAssertEqual(DescriptorSummary(descriptor: deep).problems.first, "collections nested more than 64 deep")

        let cut: [UInt8] = [0x05, 0x01, 0x09]
        XCTAssertEqual(DescriptorSummary(descriptor: cut).problems, ["descriptor ends in the middle of an item at byte 2"])
    }

    // MARK: - Contact Count Maximum, from what a read returned

    func testContactCountMaximumFromTheReturnedBytes() throws {
        XCTAssertEqual(try strip("touchscreen").contactCountMaximum(fromFeatureReport: [0x0A, 0x0A]), 10)
        let blob = [0x06, 0x05] + [UInt8](repeating: 0xAB, count: 256)
        XCTAssertEqual(try ilitek("touchscreen").contactCountMaximum(fromFeatureReport: blob), 5)
    }

    func testContactCountMaximumNeedsItsOwnReport() throws {
        let summary = try strip("touchscreen")
        XCTAssertNil(summary.contactCountMaximum(fromFeatureReport: []), "nothing came back")
        XCTAssertNil(summary.contactCountMaximum(fromFeatureReport: [0x0A]), "too short")
        XCTAssertNil(summary.contactCountMaximum(fromFeatureReport: [0x21, 0x0A]), "another report")
        XCTAssertNil(try strip("mouse").contactCountMaximum(fromFeatureReport: [0x0A, 0x0A]), "it declares none")
    }
}
