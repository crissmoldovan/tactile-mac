import CoreGraphics
import XCTest
import TactileReading
import TactileTestSupport

/// The wch.cn "TouchScreen" in survey A, and the ILITEK "ILITEK-TP" in survey B.
private let wchVendorID = 0x27c0, wchProductID = 0x0859
private let ilitekVendorID = 0x222a, ilitekProductID = 0x0001

/// The survey tool writes positions rounded to five decimal places (`round5` in
/// Tools/tactile-probe/Sources/Recorder.swift); a decoded position is compared after the same rounding.
private func roundedAsTheToolWrites(_ v: CGFloat) -> Double { (Double(v) * 100_000).rounded() / 100_000 }

private func matches(_ decoded: CGFloat?, _ recorded: Double?) -> Bool {
    switch (decoded, recorded) {
    case (nil, nil): return true
    case let (d?, r?): return abs(roundedAsTheToolWrites(d) - r) <= 1e-9
    default: return false
    }
}

/// The process's physical memory footprint, in bytes.
private func memoryFootprint() -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
}

// MARK: - Descriptors made by hand

/// `value` as a descriptor item's two data bytes, low byte first.
private func twoBytes(_ value: Int16) -> [UInt8] {
    let bits = UInt16(bitPattern: value)
    return [UInt8(bits & 0xFF), UInt8(bits >> 8)]
}

/// A touchscreen interface with one finger, using report ID 1. The finger collection holds a Tip
/// Switch (1 bit, then 7 bits of padding), a Contact Identifier (8 bits), and an X and a Y of 16 bits
/// each over the logical range `logical`, with the Input flags `axisFlags` (0x02: data, variable,
/// absolute) and the physical ranges `physicalX` and `physicalY` in hundredths of a centimetre, so
/// 0…1000 is 100 mm. A Contact Count of 8 bits follows the finger, then `extra`, inside the
/// application collection.
private func oneFingerDescriptor(
    logical: (min: Int16, max: Int16) = (0, 4095), axisFlags: UInt8 = 0x02,
    physicalX: (min: Int16, max: Int16) = (0, 1000), physicalY: (min: Int16, max: Int16) = (0, 500),
    extra: [UInt8] = []
) -> [UInt8] {
    let application: [UInt8] = [0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x01]  // Digitizer, Touch Screen, ID 1
    let tipAndID: [UInt8] = [
        0x09, 0x22, 0xA1, 0x02,  // Finger, Collection (Logical)
        0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,  // Tip Switch
        0x75, 0x07, 0x81, 0x03,  // padding
        0x09, 0x51, 0x25, 0x7F, 0x75, 0x08, 0x81, 0x02,  // Contact Identifier
    ]
    let axes: [UInt8] = [0x05, 0x01, 0x16] + twoBytes(logical.min) + [0x26] + twoBytes(logical.max)
        + [0x55, 0x0E, 0x65, 0x11, 0x75, 0x10]  // 10^-2 cm, 16 bits
        + [0x09, 0x30, 0x36] + twoBytes(physicalX.min) + [0x46] + twoBytes(physicalX.max) + [0x81, axisFlags]
        + [0x09, 0x31, 0x36] + twoBytes(physicalY.min) + [0x46] + twoBytes(physicalY.max) + [0x81, axisFlags]
        + [0xC0]
    let contactCount: [UInt8] = [
        0x05, 0x0D, 0x09, 0x54, 0x15, 0x00, 0x25, 0x0A, 0x35, 0x00, 0x45, 0x00, 0x55, 0x00, 0x65, 0x00,
        0x75, 0x08, 0x81, 0x02,
    ]
    return application + tipAndID + axes + contactCount + extra + [0xC0]
}

/// A report for `oneFingerDescriptor`: the tip on, contact 5, at the raw `x` and `y`, a Contact
/// Count of 1, then `extra`.
private func oneFingerReport(x: UInt16, y: UInt16, extra: [UInt8] = []) -> [UInt8] {
    [0x01, 0x01, 0x05, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8), 0x01] + extra
}

/// What `oneFingerReport` decodes to, with the finger at `position`.
private func oneFingerAt(_ position: CGPoint?) -> DecodedReport {
    .touch(TouchReport(contactCount: 1, slots: [SlotReading(slot: 0, contactID: 5, tip: true, position: position)]))
}

/// A mouse interface without report IDs: one button (1 bit, then 7 bits of padding), then an X and a
/// Y of 16 bits each over the logical range `logical`, with the Input flags `axisFlags`, each
/// 0…1000 hundredths of a centimetre.
private func mouseDescriptor(logical: (min: Int16, max: Int16) = (0, 4095), axisFlags: UInt8 = 0x02) -> [UInt8] {
    [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01]  // Generic Desktop, Mouse, Collection (Application)
        + [0x05, 0x09, 0x19, 0x01, 0x29, 0x01, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02]  // Button 1
        + [0x75, 0x07, 0x81, 0x03]  // padding
        + [0x05, 0x01, 0x16] + twoBytes(logical.min) + [0x26] + twoBytes(logical.max)
        + [0x35, 0x00, 0x46, 0xE8, 0x03, 0x55, 0x0E, 0x65, 0x11, 0x75, 0x10]  // 0…1000 × 10^-2 cm, 16 bits
        + [0x09, 0x30, 0x81, axisFlags, 0x09, 0x31, 0x81, axisFlags]  // X, Y
        + [0xC0]
}

/// A report for `mouseDescriptor`: the first button down, at the raw `x` and `y`.
private func mouseReport(x: UInt16, y: UInt16) -> [UInt8] {
    [0x01, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8)]
}

/// What `mouseReport` decodes to, with the pointer at `position`.
private func pressedAt(_ position: CGPoint?) -> DecodedReport {
    .pointer(PointerReport(buttons: 1, position: position))
}

/// Written once by the worker thread, before it signals; read after.
private final class Outcome<T>: @unchecked Sendable { var value: T? }

/// Runs `body` on a thread of its own (with a secondary thread's small stack) and waits for it.
/// If it is still running after `seconds`, or the process has grown by more than 256 MB, the test
/// process is stopped at once: a parser that loops would otherwise go on taking memory from the
/// person using this Mac.
private func returnsQuickly<T>(_ name: String, seconds: TimeInterval = TestTiming.limit(1),
                               _ body: @escaping @Sendable () -> T) -> (value: T, seconds: TimeInterval, memoryGrowth: Int64) {
    let memoryLimit: Int64 = 256 << 20
    let outcome = Outcome<T>()
    let done = DispatchSemaphore(value: 0)
    let before = memoryFootprint()
    let start = Date()
    Thread {
        outcome.value = body()
        done.signal()
    }.start()
    while done.wait(timeout: .now() + 0.01) == .timedOut {
        let elapsed = Date().timeIntervalSince(start)
        let growth = memoryFootprint() - before
        if elapsed > seconds || growth > memoryLimit {
            let message = "\(name): still running after \(String(format: "%.2f", elapsed)) s, "
                + "with \(growth >> 20) MB more memory; stopping the test process\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
    // The worker has signalled, so it has written the value.
    guard let value = outcome.value else { fatalError("\(name): the worker signalled without a value") }
    return (value, Date().timeIntervalSince(start), memoryFootprint() - before)
}

final class InterfaceDecoderTests: XCTestCase {

    private func wch() throws -> SurveyFixtures.Touchscreen {
        try XCTUnwrap(SurveyFixtures.surveyA.touchscreen(vendorID: wchVendorID, productID: wchProductID))
    }

    private func ilitek() throws -> SurveyFixtures.Touchscreen {
        try XCTUnwrap(SurveyFixtures.surveyB.touchscreen(vendorID: ilitekVendorID, productID: ilitekProductID))
    }

    private func decoder(_ touchscreen: SurveyFixtures.Touchscreen, _ key: String) throws -> InterfaceDecoder {
        let interface = try XCTUnwrap(touchscreen.interfaces.first { $0.key == key }, "no \(key) interface")
        return try XCTUnwrap(InterfaceDecoder(descriptor: interface.descriptor), "the \(key) descriptor did not parse")
    }

    private func reports(_ touchscreen: SurveyFixtures.Touchscreen, on key: String) -> [SurveyFixtures.Report] {
        touchscreen.takes.flatMap(\.reports).filter { $0.interfaceKey == key }
    }

    func testBothSurveysLoad() throws {
        let wch = try wch()
        let ilitek = try ilitek()
        XCTAssertEqual(wch.takes.count, 20)
        XCTAssertGreaterThanOrEqual(ilitek.takes.count, 15)
        XCTAssertEqual(wch.interfaces.map(\.key), ["touchscreen", "mouse", "vendor-ff0a"])
        XCTAssertEqual(ilitek.interfaces.map(\.key), ["touchscreen", "mouse"])
        for interface in wch.interfaces + ilitek.interfaces {
            XCTAssertFalse(interface.descriptor.isEmpty, "\(interface.key) has no descriptor")
        }
    }

    func testInterfaceKindsOfBothPanels() throws {
        func kinds(_ touchscreen: SurveyFixtures.Touchscreen) throws -> [String: InterfaceKind] {
            var result: [String: InterfaceKind] = [:]
            for interface in touchscreen.interfaces {
                result[interface.key] = try XCTUnwrap(InterfaceDecoder(descriptor: interface.descriptor), interface.key).kind
            }
            return result
        }
        XCTAssertEqual(try kinds(wch()), ["touchscreen": .touchscreen, "mouse": .mouse, "vendor-ff0a": .other])
        XCTAssertEqual(try kinds(ilitek()), ["touchscreen": .touchscreen, "mouse": .mouse])
    }

    func testFactsOfBothTouchInterfaces() throws {
        let wch = try decoder(wch(), "touchscreen")
        let ilitek = try decoder(ilitek(), "touchscreen")
        XCTAssertEqual(wch.contactSlots, 10)
        XCTAssertEqual(ilitek.contactSlots, 10)

        let wchSize = try XCTUnwrap(wch.surfaceSizeMM)
        XCTAssertEqual(wchSize.width, 216.9, accuracy: 0.1)
        XCTAssertEqual(wchSize.height, 90.6, accuracy: 0.1)
        let ilitekSize = try XCTUnwrap(ilitek.surfaceSizeMM)
        XCTAssertEqual(ilitekSize.width, 476.1, accuracy: 0.1)
        XCTAssertEqual(ilitekSize.height, 267.8, accuracy: 0.1)

        for decoder in [wch, ilitek] {
            XCTAssertFalse(decoder.reportsContactSize)
            XCTAssertFalse(decoder.reportsConfidence)
        }
    }

    /// The feature reports a host reads when it starts using a touchscreen, as Windows and Linux
    /// do: those declaring Contact Count Maximum (0x0D/0x55) or the certification blob
    /// (0xFF00/0xC5), each with its declared length, the report ID byte included. Reading the
    /// ILITEK's 0x06 is what turns it from a mouse into a touchscreen. The survey tool read exactly
    /// these lengths: 258 bytes from the ILITEK's 0x06, 2 from the strip's 0x0A.
    func testTheFeatureReportsToReadOfBothPanels() throws {
        XCTAssertEqual(try decoder(ilitek(), "touchscreen").featureReportsToRead, [
            FeatureReportToRead(reportID: 0x06, length: 258, contents: [.contactCountMaximum, .certificationBlob]),
        ])
        XCTAssertEqual(try decoder(wch(), "touchscreen").featureReportsToRead, [
            FeatureReportToRead(reportID: 0x0A, length: 2, contents: [.contactCountMaximum]),
        ], "not 0x21, which holds Input Mode and Device Index")
        for (panel, key) in [(try wch(), "mouse"), (try wch(), "vendor-ff0a"), (try ilitek(), "mouse")] {
            XCTAssertEqual(try decoder(panel, key).featureReportsToRead, [], key)
        }
    }

    func testEveryRecordedTouchReportDecodesAsTheSurveyToolSawIt() throws {
        let ilitek = try ilitek()
        let decoder = try decoder(ilitek, "touchscreen")
        var reportsCompared = 0
        var slotsCompared = 0
        var mismatches: [String] = []
        for take in ilitek.takes {
            for (index, report) in take.reports.enumerated() where report.interfaceKey == "touchscreen" {
                let place = "take \(take.number) report \(index)"
                reportsCompared += 1
                guard case .touch(let touch)? = decoder.decode(report.bytes) else {
                    mismatches.append("\(place): not decoded as a touch report")
                    continue
                }
                if touch.contactCount != report.contactCount { mismatches.append("\(place): contact count") }
                if touch.scanTime != report.scanTime { mismatches.append("\(place): scan time") }
                for finger in report.fingers ?? [] {
                    slotsCompared += 1
                    guard finger.slot < touch.slots.count else {
                        mismatches.append("\(place) slot \(finger.slot): missing")
                        continue
                    }
                    let slot = touch.slots[finger.slot]
                    if slot.slot != finger.slot { mismatches.append("\(place) slot \(finger.slot): numbered \(slot.slot)") }
                    if slot.contactID != finger.id { mismatches.append("\(place) slot \(finger.slot): contact ID") }
                    if slot.tip != finger.tip { mismatches.append("\(place) slot \(finger.slot): tip") }
                    if !matches(slot.position?.x, finger.x) { mismatches.append("\(place) slot \(finger.slot): x") }
                    if !matches(slot.position?.y, finger.y) { mismatches.append("\(place) slot \(finger.slot): y") }
                }
            }
        }
        XCTAssertGreaterThan(reportsCompared, 2_000)
        XCTAssertGreaterThan(slotsCompared, 2_000)
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(10))")
    }

    func testEveryRecordedPointerReportDecodesAsTheSurveyToolSawIt() throws {
        let wch = try wch()
        let decoder = try decoder(wch, "mouse")
        var reportsCompared = 0
        var mismatches: [String] = []
        for take in wch.takes {
            for (index, report) in take.reports.enumerated() where report.interfaceKey == "mouse" {
                let place = "take \(take.number) report \(index)"
                reportsCompared += 1
                guard case .pointer(let pointer)? = decoder.decode(report.bytes) else {
                    mismatches.append("\(place): not decoded as a pointer report")
                    continue
                }
                guard let recorded = report.pointer else {
                    mismatches.append("\(place): the tool recorded no pointer")
                    continue
                }
                if pointer.buttons != recorded.buttons { mismatches.append("\(place): buttons") }
                if !matches(pointer.position?.x, recorded.x) { mismatches.append("\(place): x") }
                if !matches(pointer.position?.y, recorded.y) { mismatches.append("\(place): y") }
            }
        }
        XCTAssertGreaterThan(reportsCompared, 4_000)
        XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(10))")
    }

    func testAReportTooShortForItsLayoutIsSkipped() throws {
        // The ILITEK's touch reports were recorded. The wch.cn never sent one, so its report is
        // built at the length its descriptor declares: report ID 0x0D and 53 bytes of nothing.
        let ilitek = try ilitek()
        let ilitekReport = try XCTUnwrap(reports(ilitek, on: "touchscreen").first).bytes
        let wchReport = [UInt8(0x0D)] + [UInt8](repeating: 0, count: 53)
        let cases = [(try decoder(ilitek, "touchscreen"), ilitekReport), (try decoder(wch(), "touchscreen"), wchReport)]
        for (decoder, report) in cases {
            XCTAssertNil(decoder.decode([]))
            XCTAssertNotNil(decoder.decode(report), "the whole report should decode")
            XCTAssertNil(decoder.decode(Array(report.prefix(report.count / 2))))
        }
    }

    func testAnUnknownReportIDIsSkipped() throws {
        let ilitek = try ilitek()
        let wch = try wch()
        let cases = [
            (try decoder(ilitek, "touchscreen"), try XCTUnwrap(reports(ilitek, on: "touchscreen").first).bytes),
            (try decoder(wch, "mouse"), try XCTUnwrap(reports(wch, on: "mouse").first).bytes),
        ]
        for (decoder, report) in cases {
            XCTAssertNotNil(decoder.decode(report), "the recorded report should decode")
            var unknown = report
            unknown[0] = 0xEE
            XCTAssertNil(decoder.decode(unknown))
        }
    }

    func testGarbageIsNotADescriptor() {
        XCTAssertNil(InterfaceDecoder(descriptor: []))
        XCTAssertNil(InterfaceDecoder(descriptor: [0xFF, 0xFF, 0xFF]))
    }

    /// A descriptor is input from whatever is plugged in, so it is not trusted. A hang or a trap
    /// here would take down every touchscreen the app is driving.
    func testAHostileDescriptorCannotHangOrCrashTheApp() throws {
        let mouse: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01]  // Generic Desktop, Mouse, Collection (Application)

        // One Input item of Report Count 0xFFFFFFFF and Report Size 32: a report of 16 GiB.
        let hugeCount = mouse + [0x09, 0x30, 0x75, 0x20, 0x97, 0xFF, 0xFF, 0xFF, 0xFF, 0x81, 0x02, 0xC0]
        let huge = returnsQuickly("Report Count 0xFFFFFFFF") { InterfaceDecoder(descriptor: hugeCount) }
        XCTAssertNil(huge.value, "a report longer than 65,535 bytes makes the descriptor unusable")
        XCTAssertLessThan(huge.seconds, TestTiming.limit(1))
        XCTAssertLessThan(huge.memoryGrowth, 16 << 20)

        // An X 64 bits wide, signed (Logical Minimum -1), and a report that holds its largest value.
        let wideX = mouse + [0x09, 0x30, 0x15, 0xFF, 0x26, 0xFF, 0x7F, 0x75, 0x40, 0x95, 0x01, 0x81, 0x02, 0xC0]
        let wide = returnsQuickly("a 64-bit X field") { InterfaceDecoder(descriptor: wideX) }
        let decoder = try XCTUnwrap(wide.value, "a field wider than 32 bits is left unread; the descriptor is still usable")
        XCTAssertEqual(decoder.maxInputReportLength, 8)
        let report: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F]
        XCTAssertEqual(
            returnsQuickly("decoding a 64-bit X field") { decoder.decode(report) }.value, .other,
            "the report's only field is left unread, so it carries nothing")

        // Collections nested 10,000 deep, with 4,096 one-bit fields in the innermost one.
        let nested = mouse + [UInt8](repeating: 0, count: 2 * 10_000).enumerated().map { $0.offset % 2 == 0 ? 0xA1 : 0x00 }
            + [0x09, 0x30, 0x75, 0x01, 0x96, 0x00, 0x10, 0x81, 0x02] + [UInt8](repeating: 0xC0, count: 10_001)
        let deep = returnsQuickly("collections nested 10,000 deep") { InterfaceDecoder(descriptor: nested) }
        XCTAssertNil(deep.value, "collections nested more than 64 deep make the descriptor unusable")
        XCTAssertLessThan(deep.seconds, TestTiming.limit(1))
    }

    // MARK: - Descriptors made by hand

    /// A field wider than 32 bits is left unread, and only that field: the rest of its report is
    /// read. Here a 40-bit field follows the touch report's Contact Count.
    func testAFieldWiderThan32BitsLeavesTheRestOfItsReportReadable() throws {
        let cases: [(String, extra: [UInt8], reportBytes: Int)] = [
            ("nothing more", [], 8),
            ("40 bits of constant padding", [0x75, 0x28, 0x95, 0x01, 0x81, 0x03], 13),
            ("a 40-bit vendor-defined value", [0x06, 0x00, 0xFF, 0x09, 0x01, 0x75, 0x28, 0x95, 0x01, 0x81, 0x02], 13),
        ]
        for (name, extra, reportBytes) in cases {
            let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: oneFingerDescriptor(extra: extra)), name)
            XCTAssertEqual(decoder.kind, .touchscreen, name)
            XCTAssertEqual(decoder.contactSlots, 1, name)
            XCTAssertEqual(decoder.maxInputReportLength, reportBytes, name)
            let report = oneFingerReport(x: 2048, y: 1024, extra: [UInt8](repeating: 0xFF, count: reportBytes - 8))
            XCTAssertEqual(decoder.decode(report), oneFingerAt(CGPoint(x: 2048.0 / 4095, y: 1024.0 / 4095)), name)
        }
    }

    /// A HID descriptor's length is a 16-bit number, so one longer than 65,535 bytes isn't one.
    func testADescriptorLongerThan65535BytesIsRefused() {
        let descriptor = oneFingerDescriptor()
        // 0x00 is a main item with no data and no meaning, which the parser passes over.
        let longest = descriptor + [UInt8](repeating: 0x00, count: 65_535 - descriptor.count)
        XCTAssertNotNil(InterfaceDecoder(descriptor: longest))
        let tooLong = descriptor + [UInt8](repeating: 0x00, count: 70_000 - descriptor.count)
        XCTAssertNil(InterfaceDecoder(descriptor: tooLong))
        XCTAssertNil(InterfaceDecoder(descriptor: descriptor + [UInt8](repeating: 0x00, count: 65_536 - descriptor.count)))
    }

    /// A glass point is 0…1 on each axis. A value beyond its field's logical range is at the range's
    /// nearer end: X = 0xFFFF over 100…4095 would otherwise be 16 glass widths across.
    func testAGlassPointOutsideItsLogicalRangeIsAtTheEdge() throws {
        let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: oneFingerDescriptor(logical: (100, 4095))))
        XCTAssertEqual(decoder.decode(oneFingerReport(x: 0xFFFF, y: 4096)), oneFingerAt(CGPoint(x: 1, y: 1)), "above")
        XCTAssertEqual(decoder.decode(oneFingerReport(x: 0, y: 99)), oneFingerAt(CGPoint(x: 0, y: 0)), "below")
        // At the ends and between them, as ever.
        XCTAssertEqual(decoder.decode(oneFingerReport(x: 100, y: 4095)), oneFingerAt(CGPoint(x: 0, y: 1)))
        XCTAssertEqual(
            decoder.decode(oneFingerReport(x: 2097, y: 1000)), oneFingerAt(CGPoint(x: 1997.0 / 3995, y: 900.0 / 3995)))
    }

    /// A field with a Null State says it has no value by giving one outside its logical range. A
    /// finger with such an X or Y has no position, and the builder gives no contact for it.
    func testAValueOutsideANullStateRangeIsNoPosition() throws {
        let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: oneFingerDescriptor(logical: (100, 4095), axisFlags: 0x42)))
        for (x, y) in [(0xFFFF, 2048), (2048, 99), (0, 0xFFFF)] as [(UInt16, UInt16)] {
            let decoded = decoder.decode(oneFingerReport(x: x, y: y))
            XCTAssertEqual(decoded, oneFingerAt(nil), "\(x), \(y)")
            guard case .touch(let touch)? = decoded else { continue }
            var builder = TouchFrameBuilder()
            XCTAssertEqual(builder.add(touch, at: 1), ContactFrame(time: 1, contacts: []), "\(x), \(y)")
        }
        // Inside the range, a Null State changes nothing.
        XCTAssertEqual(decoder.decode(oneFingerReport(x: 100, y: 4095)), oneFingerAt(CGPoint(x: 0, y: 1)))
    }

    /// The same for a pointer's absolute position: beyond the logical range it is at the nearer end,
    /// and with a Null State it is no position, which the reader gives no contact for.
    func testAPointerPositionOutsideItsLogicalRangeIsAtTheEdgeOrNone() throws {
        let plain = try XCTUnwrap(InterfaceDecoder(descriptor: mouseDescriptor(logical: (100, 4095))))
        XCTAssertEqual(plain.decode(mouseReport(x: 0xFFFF, y: 4096)), pressedAt(CGPoint(x: 1, y: 1)), "above")
        XCTAssertEqual(plain.decode(mouseReport(x: 0, y: 99)), pressedAt(CGPoint(x: 0, y: 0)), "below")
        XCTAssertEqual(plain.decode(mouseReport(x: 100, y: 4095)), pressedAt(CGPoint(x: 0, y: 1)))

        let nullState = try XCTUnwrap(InterfaceDecoder(descriptor: mouseDescriptor(logical: (100, 4095), axisFlags: 0x42)))
        for (x, y) in [(0xFFFF, 2048), (2048, 99)] as [(UInt16, UInt16)] {
            let decoded = nullState.decode(mouseReport(x: x, y: y))
            XCTAssertEqual(decoded, pressedAt(nil), "\(x), \(y)")
            guard case .pointer(let pointer)? = decoded else { continue }
            var reader = PointerFingerReader()
            XCTAssertNil(reader.add(pointer, at: 1), "\(x), \(y)")
        }
        XCTAssertEqual(nullState.decode(mouseReport(x: 100, y: 4095)), pressedAt(CGPoint(x: 0, y: 1)))
    }

    /// The surface's size comes from the physical ranges of the X and Y fields, and is a size only
    /// when both its sides are above zero and neither axis is relative: a relative axis measures
    /// movement, not the surface.
    func testASurfaceSizeHasTwoSidesAboveZeroFromAbsoluteAxes() throws {
        XCTAssertEqual(InterfaceDecoder(descriptor: oneFingerDescriptor())?.surfaceSizeMM, CGSize(width: 100, height: 50))
        XCTAssertEqual(InterfaceDecoder(descriptor: mouseDescriptor())?.surfaceSizeMM, CGSize(width: 100, height: 100))

        let noSize: [(String, [UInt8])] = [
            ("X from 1000 down to 0", oneFingerDescriptor(physicalX: (1000, 0))),
            ("Y from 500 down to 0", oneFingerDescriptor(physicalY: (500, 0))),
            ("X from 0 to 0", oneFingerDescriptor(physicalX: (0, 0))),
            ("relative finger axes", oneFingerDescriptor(axisFlags: 0x06)),
            ("a relative mouse", mouseDescriptor(axisFlags: 0x06)),
        ]
        for (name, descriptor) in noSize {
            let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: descriptor), name)
            XCTAssertNil(decoder.surfaceSizeMM, name)
        }
    }

    /// Each report declaring Contact Count Maximum or the certification blob is listed once, in
    /// descriptor order (as Linux reads them), with its declared length. A report declaring neither, or an input field
    /// with one of those usages, is no reason to read. A constant field is, as in Linux: a read
    /// too many does no harm, and one too few leaves a panel emulating a mouse.
    func testTheFeatureReportsToReadComeFromTheDescriptor() throws {
        let features: [UInt8] = [
            0x85, 0x03, 0x09, 0x55, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02,  // 0x03: Contact Count Maximum
            0x85, 0x02, 0x06, 0x00, 0xFF, 0x09, 0xC5, 0x15, 0x00, 0x26, 0xFF, 0x00,
            0x75, 0x08, 0x96, 0x00, 0x01, 0xB1, 0x02,  // 0x02: the 256-byte certification blob
            0x85, 0x04, 0x05, 0x0D, 0x09, 0x52, 0x09, 0x53, 0x25, 0x0A, 0x95, 0x02, 0xB1, 0x02,  // 0x04: Input Mode, Device Index
            0x85, 0x05, 0x09, 0x55, 0x95, 0x01, 0x81, 0x02,  // 0x05: Contact Count Maximum as an input field
            0x85, 0x06, 0x09, 0x55, 0xB1, 0x03,  // 0x06: Contact Count Maximum as a constant
        ]
        let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: oneFingerDescriptor(extra: features)))
        XCTAssertEqual(decoder.featureReportsToRead, [
            FeatureReportToRead(reportID: 0x03, length: 2, contents: [.contactCountMaximum]),
            FeatureReportToRead(reportID: 0x02, length: 257, contents: [.certificationBlob]),
            FeatureReportToRead(reportID: 0x06, length: 2, contents: [.contactCountMaximum]),
        ], "0x03 comes before 0x02 in the descriptor")
        XCTAssertEqual(InterfaceDecoder(descriptor: oneFingerDescriptor())?.featureReportsToRead, [], "it declares no feature")

        // Without report IDs, the report is 0 and its length has no ID byte.
        var withoutIDs = oneFingerDescriptor(extra: [0x09, 0x55, 0x25, 0x0A, 0x75, 0x08, 0x95, 0x01, 0xB1, 0x02])
        withoutIDs.removeSubrange(6..<8)  // the application's Report ID 1
        XCTAssertEqual(InterfaceDecoder(descriptor: withoutIDs)?.featureReportsToRead, [
            FeatureReportToRead(reportID: 0, length: 1, contents: [.contactCountMaximum]),
        ])
    }

    func testTheFeatureReportContentsNameThemselves() {
        XCTAssertEqual(FeatureReportToRead(reportID: 6, length: 258, contents: [.contactCountMaximum, .certificationBlob]).describedContents,
                       "Contact Count Maximum, certification blob")
        XCTAssertEqual(FeatureReportToRead(reportID: 10, length: 2, contents: [.contactCountMaximum]).describedContents,
                       "Contact Count Maximum")
    }
}
