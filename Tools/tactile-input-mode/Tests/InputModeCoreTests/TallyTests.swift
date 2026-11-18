import XCTest
@testable import InputModeCore

final class TallyTests: XCTestCase {
    private func stripTouchReport(tips: Int) -> [UInt8] {
        // Report 0x0D: ten 5-byte finger slots (tip in bit 0 of the first byte), scan time, contact count.
        var report = [UInt8](repeating: 0, count: 54)
        report[0] = 0x0D
        for slot in 0..<tips { report[1 + slot * 5] = 0x01 | UInt8(slot << 4) }
        report[53] = UInt8(tips)
        return report
    }

    func testCountsTouchReportsAndTheMostFingersInOne() throws {
        let d = try HIDDescriptor(bytes(Fixtures.stripTouchscreen))
        var tally = InterfaceTally(role: .touchscreen, descriptor: d)
        tally.add(stripTouchReport(tips: 1))
        tally.add(stripTouchReport(tips: 2))
        tally.add(stripTouchReport(tips: 0))
        XCTAssertEqual(tally.reports, 3)
        XCTAssertEqual(tally.byReportID, [0x0D: 3])
        XCTAssertEqual(tally.mostContactsDown, 2)
        XCTAssertEqual(tally.firstReport, stripTouchReport(tips: 1))
    }

    func testCountsFingersInARealIlitekReport() throws {
        var tally = InterfaceTally(role: .touchscreen, descriptor: try HIDDescriptor(bytes(Fixtures.ilitekTouchscreen)))
        tally.add(bytes(Fixtures.ilitekTwoFingers))
        XCTAssertEqual(tally.mostContactsDown, 2)
    }

    func testCountsMouseReportsWithTheButtonHeld() throws {
        var tally = InterfaceTally(role: .mouse, descriptor: try HIDDescriptor(bytes(Fixtures.stripMouse)))
        tally.add(bytes(Fixtures.stripMousePressed))
        tally.add(bytes("0700441f481700"))
        XCTAssertEqual(tally.reports, 2)
        XCTAssertEqual(tally.reportsWithButtonDown, 1)
    }

    func testAReportWithoutADescriptorIsStillCounted() {
        var tally = InterfaceTally(role: .vendor, descriptor: nil)
        tally.add([0x50, 0x01, 0x02])
        XCTAssertEqual(tally.reports, 1)
        XCTAssertEqual(tally.byReportID, [:])
    }

    func testVerdictWhenTouchesArrive() throws {
        var touch = InterfaceTally(role: .touchscreen, descriptor: try HIDDescriptor(bytes(Fixtures.stripTouchscreen)))
        touch.add(stripTouchReport(tips: 2))
        let summary = ListenSummary(tallies: [touch, InterfaceTally(role: .mouse, descriptor: nil)], seconds: 5)
        XCTAssertEqual(summary.outcome, .touchesArrived)
        XCTAssertEqual(summary.lines().first, "touch reports: 1 (most fingers in one report: 2)")
        XCTAssertTrue(summary.lines().contains { $0.contains("WORKED") })
    }

    func testTouchReportsWithNoFingerDownAreNotASuccess() throws {
        // A panel can send an empty release frame after a mode write: reports, but no finger.
        var touch = InterfaceTally(role: .touchscreen, descriptor: try HIDDescriptor(bytes(Fixtures.stripTouchscreen)))
        touch.add(stripTouchReport(tips: 0))
        touch.add(stripTouchReport(tips: 0))
        var mouse = InterfaceTally(role: .mouse, descriptor: try HIDDescriptor(bytes(Fixtures.stripMouse)))
        mouse.add(bytes(Fixtures.stripMousePressed))
        let summary = ListenSummary(tallies: [touch, mouse], seconds: 5)
        XCTAssertEqual(summary.outcome, .touchReportsWithoutFingers)
        XCTAssertEqual(summary.lines().first, "touch reports: 2, none with a finger down")
        XCTAssertFalse(summary.lines().contains { $0.contains("WORKED") })
        XCTAssertTrue(summary.lines().contains { $0.contains("not shown to work") })
    }

    func testTouchReportsFromAnInterfaceWhoseFingersCannotBeReadAreNotASuccess() {
        var touch = InterfaceTally(role: .touchscreen, descriptor: nil)
        touch.add([0x0D, 0x01])
        let summary = ListenSummary(tallies: [touch], seconds: 5)
        XCTAssertEqual(summary.outcome, .touchReportsWithoutFingers)
        XCTAssertFalse(summary.lines().contains { $0.contains("WORKED") })
    }

    func testVerdictWhenOnlyTheMouseSends() throws {
        var mouse = InterfaceTally(role: .mouse, descriptor: try HIDDescriptor(bytes(Fixtures.stripMouse)))
        mouse.add(bytes(Fixtures.stripMousePressed))
        let summary = ListenSummary(tallies: [InterfaceTally(role: .touchscreen, descriptor: nil), mouse], seconds: 5)
        XCTAssertEqual(summary.outcome, .stayedInMouseMode)
        XCTAssertEqual(summary.lines().first, "touch reports: 0")
        XCTAssertTrue(summary.lines().contains { $0.contains("did not work") })
    }

    func testVerdictWhenNothingArrives() {
        let summary = ListenSummary(tallies: [InterfaceTally(role: .touchscreen, descriptor: nil),
                                              InterfaceTally(role: .mouse, descriptor: nil),
                                              InterfaceTally(role: .vendor, descriptor: nil)], seconds: 5)
        XCTAssertEqual(summary.outcome, .nothingArrived)
        XCTAssertEqual(summary.lines().first, "touch reports: 0")
        XCTAssertTrue(summary.lines().contains { $0.contains("nothing was touching the glass") })
    }

    func testVendorReportsAreReported() {
        var vendor = InterfaceTally(role: .vendor, descriptor: nil)
        vendor.add([0x50, 0xAA])
        let summary = ListenSummary(tallies: [vendor], seconds: 5)
        XCTAssertTrue(summary.lines().contains { $0.hasPrefix("vendor reports: 1") })
    }
}
