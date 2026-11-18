import Foundation
import TactileDevices
import TactileSupport
import XCTest

/// The report's log: the log book's lines about the device checked, found by its interfaces, never
/// by its product or USB ID, which a second unit of the same model shares; redacted once more with
/// every serial number Tactile knows. Nothing here reads the system's log.
@MainActor
final class SupportLogTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_795_000_000.125)

    /// Unit A (touch interface 21, mouse 22) and unit B (41, 42): the same model, two serials.
    private func twoUnits() -> DeviceLogBook {
        var clock = start
        let book = DeviceLogBook(now: { defer { clock += 1 }; return clock })
        book.note(21, category: "devices", "Connected device-1: 222a:0001 at 0x01141000; 10 contacts")
        book.note(41, category: "devices", "Connected device-2: 222a:0001 at 0x01151000; 10 contacts")
        book.note(21, category: "devices", "Took device-1: exclusive access held, input mode noInputModeSetting")
        book.note(41, category: "devices", "device-2: its mouse interface went")
        book.note(21, category: "support", "Support check: let go")
        return book
    }

    func testOnlyTheCheckedUnitsLinesAreKept() {
        let lines = SupportLog.lines(twoUnits().entries(about: [21, 22]), serials: [], home: nil)
        XCTAssertEqual(lines, [
            "2026-11-18T11:06:40.125Z [devices] Connected device-1: 222a:0001 at 0x01141000; 10 contacts",
            "2026-11-18T11:06:42.125Z [devices] Took device-1: exclusive access held, input mode noInputModeSetting",
            "2026-11-18T11:06:44.125Z [support] Support check: let go",
        ])
        XCTAssertFalse(lines.joined().contains("device-2"), "nothing of the other unit")
    }

    /// The shapes Tactile's own log gives a touchscreen (`vvvv:pppp:<serial>`, `@<location>:…`, a
    /// command naming it), for a second unit of the same model: none can reach the report, as only the
    /// log book is read; and were one written there, every known serial is taken out.
    func testASecondUnitsSerialNeverReachesTheReport() {
        let book = twoUnits()
        book.note(21, category: "devices", "222a:0001:UNIT-B-0002: nothing for 0.6 s with fingers down; the lift was lost")
        book.note(21, category: "devices", "Command setShowsCircles(@01151000:222a:0001:UNIT-B-0002, true)")
        let lines = SupportLog.lines(book.entries(about: [21, 22]), serials: ["UNIT-A-0001", "UNIT-B-0002"], home: nil)
        XCTAssertFalse(lines.joined().contains("UNIT-B"))
        XCTAssertTrue(lines.contains { $0.hasSuffix("222a:0001:[serial removed]: nothing for 0.6 s with fingers down; the lift was lost") })
    }

    func testSerialNumbersAreRemoved() {
        XCTAssertEqual(
            SupportRedaction.redact(#"serial "ANY-SERIAL" and again V06.00.00.00, V06.00.00.00"#, serials: ["V06.00.00.00"], home: nil),
            #"serial "[serial removed]" and again [serial removed], [serial removed]"#)
        XCTAssertEqual(SupportRedaction.redact(#"Serial: "abc", serial ''"#, serials: [], home: nil),
                       #"Serial: "[serial removed]", serial ''"#)
        XCTAssertEqual(SupportRedaction.redact("report 12 of 120", serials: ["12", ""], home: nil), "report 12 of 120",
                       "a serial shorter than four characters is too common to take out")
        XCTAssertEqual(SupportRedaction.redact(#"serial "AB"CD-0001" here"#, serials: [#"AB"CD-0001"#], home: nil),
                       #"serial "[serial removed]" here"#, "a quote inside a serial doesn't stop it short")
        XCTAssertEqual(SupportRedaction.redact("A-12345 and A-1234", serials: ["A-1234", "A-12345"], home: nil),
                       "[serial removed] and [serial removed]", "the longest first")
    }

    func testTheHomeFolderAndUserNameAreRemoved() {
        XCTAssertEqual(
            SupportRedaction.redact("at /Users/someone/Applications/Tactile.app and /Users/other/x", serials: [], home: "/Users/someone"),
            "at ~/Applications/Tactile.app and /Users/[user]/x")
    }
}
