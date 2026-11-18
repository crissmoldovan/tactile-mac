import Foundation
import TactileSupport
import XCTest

/// Tactile's own log lines about one touchscreen, as the report keeps them: found by its USB ID and
/// the handle Tactile gave it, with every serial number and the home folder taken out. The entries
/// are made here: nothing reads the system's log.
final class SupportLogTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_795_000_000.125)

    private func entry(_ seconds: Double, _ category: String, _ message: String) -> SupportLogEntry {
        SupportLogEntry(date: start.addingTimeInterval(seconds), category: category, message: message)
    }

    private var desk: [SupportLogEntry] {
        [
            entry(0, "app", "Tactile 0.7.0 starting (pid 4242, /Users/someone/Applications/Tactile.app)"),
            entry(1, "devices", #"Connected device-3: 222a:0001 "ILITEK-TP" serial "V06.00.00.00" at 0x01141000; 10 contacts"#),
            entry(1.1, "devices", #"Connected device-4: 27c0:0859 "TouchScreen" serial "TEST-SERIAL-0001" at 0x01130000; 10 contacts"#),
            entry(2, "devices", "device-3: holding its touchscreen interface exclusively"),
            entry(2.1, "devices", "device-4: holding its touchscreen interface exclusively"),
            entry(3, "devices", "device-31: holding its touchscreen interface exclusively"),
            entry(4, "model", "Connected: device-3 222a:0001 ILITEK-TP"),
            entry(5, "support", "Support check of 222a:0001 (touchscreen): taking it as Tactile takes a touchscreen"),
            entry(6, "model", "Settings saved to /Users/someone/Library/Application Support/Tactile/settings.json"),
        ]
    }

    func testOnlyThisTouchscreensLinesAreKept() {
        let lines = SupportLog.lines(desk, usbID: "222a:0001", location: "01141000", serials: ["V06.00.00.00"], home: nil)
        XCTAssertEqual(lines, [
            #"2026-11-18T11:06:41.125Z [devices] Connected device-3: 222a:0001 "ILITEK-TP" serial "[serial removed]" at 0x01141000; 10 contacts"#,
            "2026-11-18T11:06:42.125Z [devices] device-3: holding its touchscreen interface exclusively",
            "2026-11-18T11:06:44.125Z [model] Connected: device-3 222a:0001 ILITEK-TP",
            "2026-11-18T11:06:45.125Z [support] Support check of 222a:0001 (touchscreen): taking it as Tactile takes a touchscreen",
        ])
    }

    func testTwoOfTheSameModelAreToldApartByWhereTheyArePlugged() {
        var entries = desk
        entries.append(entry(7, "devices", #"Connected device-5: 222a:0001 "ILITEK-TP" serial "OTHER-UNIT-0002" at 0x01142000; 10 contacts"#))
        entries.append(entry(8, "devices", "device-5: holding its touchscreen interface exclusively"))
        let lines = SupportLog.lines(entries, usbID: "222a:0001", location: "01141000", serials: ["V06.00.00.00"], home: nil)
        XCTAssertFalse(lines.contains { $0.contains("device-5") }, "\(lines)")
        XCTAssertFalse(lines.joined().contains("OTHER-UNIT-0002"))
        XCTAssertEqual(lines.count, 4)
    }

    func testADeviceTactileDoesntListHasOnlyTheChecksLines() {
        let entries = [entry(0, "support", "Support check of 1234:5678 (mouse-only): taking it as Tactile takes a touchscreen")] + desk
        let lines = SupportLog.lines(entries, usbID: "1234:5678", location: "01200000", serials: ["POINTER-SERIAL-0042"], home: nil)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(SupportLog.lines(desk, usbID: "1234:5678", location: nil, serials: [], home: nil), [])
    }

    func testSerialNumbersAreRemoved() {
        XCTAssertEqual(
            SupportRedaction.redact(#"serial "ANY-SERIAL" and again V06.00.00.00, V06.00.00.00"#, serials: ["V06.00.00.00"], home: nil),
            #"serial "[serial removed]" and again [serial removed], [serial removed]"#)
        XCTAssertEqual(SupportRedaction.redact(#"Serial: "abc", serial ''"#, serials: [], home: nil),
                       #"Serial: "[serial removed]", serial ''"#)
        XCTAssertEqual(SupportRedaction.redact("report 12 of 120", serials: ["12", ""], home: nil), "report 12 of 120",
                       "a serial shorter than four characters is too common to take out")
    }

    func testTheHomeFolderAndUserNameAreRemoved() {
        XCTAssertEqual(
            SupportRedaction.redact("at /Users/someone/Applications/Tactile.app and /Users/other/x", serials: [], home: "/Users/someone"),
            "at ~/Applications/Tactile.app and /Users/[user]/x")
    }
}
