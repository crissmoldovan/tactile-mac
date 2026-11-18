import TactileReading
import TactileTestSupport
import XCTest
@testable import TactileDevices

/// Tactile's own record of what it did with each device, for the touchscreen check's report: in
/// memory, bounded, written plain and already redacted, and found by the interface each line is
/// about, never by a product name or a USB ID, which two identical units share.
@MainActor
final class DeviceLogBookTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_795_000_000)

    private func book(capacity: Int = 100) -> DeviceLogBook {
        DeviceLogBook(capacity: capacity, now: { [unowned self] in self.clock })
    }

    func testLinesAreFoundByTheirInterface() {
        let book = book()
        book.note(21, category: "devices", "device-1: took it")
        book.note(31, category: "devices", "device-2: took it")
        book.note(21, category: "support", "Support check: let go")
        XCTAssertEqual(book.entries(about: [21]).map(\.text), ["device-1: took it", "Support check: let go"])
        XCTAssertEqual(book.entries(about: [21]).map(\.category), ["devices", "support"])
        XCTAssertEqual(book.entries(about: [31, 99]).map(\.text), ["device-2: took it"])
        XCTAssertEqual(book.entries(about: []), [])
    }

    func testItKeepsTheNewestLinesOnly() {
        let book = book(capacity: 3)
        for n in 1...5 { book.note(21, category: "devices", "line \(n)") }
        XCTAssertEqual(book.entries(about: [21]).map(\.text), ["line 3", "line 4", "line 5"])
    }

    func testEveryLineIsRedactedAsItIsWritten() {
        let book = book()
        book.note(21, category: "devices", #"Connected "ILITEK-TP" serial "V06.00.00.00" on "Cristian’s monitor"\#n\#u{202E}x"#)
        XCTAssertEqual(book.entries(about: [21]).first?.text, #"Connected "[removed]" serial "[removed]" on "[removed]" x"#,
                       "anything quoted (a name, a serial) goes; controls and bidi characters go")
        book.note(21, category: "devices", #"serial "abc and the rest"#)
        XCTAssertEqual(book.entries(about: [21]).last?.text, #"serial "[removed]"#, "an unpaired quote takes the rest")
        book.note(21, category: "devices", String(repeating: "a", count: 1000))
        XCTAssertEqual(book.entries(about: [21]).last?.text.count, DeviceLogBook.maxLineLength)
    }

    // MARK: - What the source writes

    /// Two identical touchscreens (same USB ID and product, different serials and locations), both
    /// connected and taken: each one's lines are its own, and none holds a serial or a name.
    func testTwoIdenticalUnitsEachHaveTheirOwnLinesWithNoSerialOrName() throws {
        let panel = try Panels.ilitek()
        func unit(_ touch: HIDInterfaceID, _ mouse: HIDInterfaceID, at location: UInt32, serial: String) throws -> [HIDInterfaceDescription] {
            [
                HIDInterfaceDescription(id: touch, locationID: location, vendorID: 0x222a, productID: 0x0001, serial: serial,
                                        product: "ILITEK-TP", usages: [.touchScreen], descriptor: try Panels.descriptor(panel, "touchscreen"),
                                        maxInputReportSize: 64, manufacturer: "ILITEK"),
                HIDInterfaceDescription(id: mouse, locationID: location, vendorID: 0x222a, productID: 0x0001, serial: serial,
                                        product: "ILITEK-TP", usages: Panels.ilitekMouseUsages,
                                        descriptor: try Panels.descriptor(panel, "mouse"), maxInputReportSize: 64, manufacturer: "ILITEK"),
            ]
        }
        let system = FakeHIDSystem(connected: try unit(21, 22, at: 0x0114_1000, serial: "UNIT-A-0001")
                                   + unit(41, 42, at: 0x0115_1000, serial: "UNIT-B-0002"))
        let book = book()
        let delegate = RecordingDelegate()
        let source = HIDTouchscreenSource(system: system, logBook: book)
        source.delegate = delegate
        source.start()
        for touchscreen in delegate.connected { source.setState(.taken, for: touchscreen.handle) }
        system.send(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), on: 42, at: 1)
        system.disconnect(42)

        let a = book.entries(about: [21, 22]).map(\.text)
        let b = book.entries(about: [41, 42]).map(\.text)
        XCTAssertTrue(a.contains { $0.hasPrefix("Connected device-1: 222a:0001 at 0x01141000") }, "\(a)")
        XCTAssertTrue(a.contains { $0.hasPrefix("Took device-1") }, "\(a)")
        XCTAssertTrue(a.contains { $0.contains("read feature report 0x06") }, "\(a)")
        XCTAssertFalse(a.contains { $0.contains("device-2") }, "nothing of the other unit")
        XCTAssertTrue(b.contains { $0.contains("device-2: its mouse interface went") }, "\(b)")
        for line in a + b {
            XCTAssertFalse(line.contains("UNIT-A") || line.contains("UNIT-B"), line)
            XCTAssertFalse(line.contains("ILITEK-TP"), line)
        }
    }
}
