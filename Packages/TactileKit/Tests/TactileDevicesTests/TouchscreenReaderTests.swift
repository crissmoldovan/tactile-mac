import CoreGraphics
import TactileDevices
import TactileReading
import TactileTestSupport
import XCTest

final class TouchscreenReaderTests: XCTestCase {

    // MARK: - The recorded takes

    /// Every report of every wch.cn take, fed by the interface it arrived on, makes the strip one
    /// finger from its mouse interface: exactly the frames `PointerFingerReader` gives on its own.
    func testTheStripIsOneFingerFromItsMouseInterface() throws {
        let strip = try Panels.wch()
        let touch = try Panels.decoder(strip, "touchscreen")
        let mouse = try Panels.decoder(strip, "mouse")
        for number in 1...20 {
            let take = try Panels.take(strip, number)
            var reader = TouchscreenReader(touch: touch, mouse: mouse)
            var expected = PointerFingerReader(guardInterval: 0.05)
            var frames: [ContactFrame] = []
            var expectedFrames: [ContactFrame] = []
            for report in take.reports {
                let interface: TouchscreenReader.Interface = report.interfaceKey == "touchscreen" ? .touch : .mouse
                XCTAssertEqual(report.interfaceKey, "mouse", "take \(number): the strip only ever sent mouse reports")
                frames += reader.add(report.bytes, from: interface, at: report.hostTime)
                if case .pointer(let pointer)? = mouse.decode(report.bytes),
                   let frame = expected.add(pointer, at: report.hostTime) {
                    expectedFrames.append(frame)
                }
            }
            XCTAssertEqual(reader.origin, .mouseInterface, "take \(number)")
            XCTAssertFalse(expectedFrames.isEmpty, "take \(number) gave no frame to compare")
            XCTAssertEqual(frames, expectedFrames, "take \(number)")
        }
    }

    /// Every ILITEK take reads from its touch interface: exactly the frames `TouchFrameBuilder` gives.
    func testTheILITEKReadsFromItsTouchInterface() throws {
        let ilitek = try Panels.ilitek()
        let touch = try Panels.decoder(ilitek, "touchscreen")
        let mouse = try Panels.decoder(ilitek, "mouse")
        for number in 1...15 {
            let take = try Panels.take(ilitek, number)
            var reader = TouchscreenReader(touch: touch, mouse: mouse)
            var expected = TouchFrameBuilder()
            var frames: [ContactFrame] = []
            var expectedFrames: [ContactFrame] = []
            for report in take.reports {
                let interface: TouchscreenReader.Interface = report.interfaceKey == "touchscreen" ? .touch : .mouse
                XCTAssertEqual(report.interfaceKey, "touchscreen", "take \(number): the ILITEK only ever sent touch reports")
                frames += reader.add(report.bytes, from: interface, at: report.hostTime)
                if case .touch(let touchReport)? = touch.decode(report.bytes),
                   let frame = expected.add(touchReport, at: report.hostTime) {
                    expectedFrames.append(frame)
                }
            }
            XCTAssertEqual(reader.origin, .touchInterface, "take \(number)")
            XCTAssertFalse(expectedFrames.isEmpty, "take \(number) gave no frame to compare")
            XCTAssertEqual(frames, expectedFrames, "take \(number)")
        }
    }

    // MARK: - A touch report always wins

    /// Review Focus 5: a panel that starts on its mouse interface and later sends touches. The
    /// mouse finger is ended first, and from then on only the touch interface counts.
    func testATouchReportEndsTheMouseFinger() throws {
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))

        let press = reader.add(Panels.ilitekMouse(buttons: 1, x: 0.25, y: 0.5), from: .mouse, at: 10.00)
        XCTAssertEqual(reader.origin, .mouseInterface)
        XCTAssertEqual(press.count, 1)
        XCTAssertEqual(press.first?.contacts.map(\.id), [0], "the mouse is one finger")

        let touchBytes = try firstTouchReport(of: ilitek)
        let switched = reader.add(touchBytes, from: .touch, at: 10.05)
        XCTAssertEqual(reader.origin, .touchInterface)
        XCTAssertEqual(switched.count, 2, "an empty frame, then the touch frame")
        XCTAssertEqual(switched.first, ContactFrame(time: 10.05, contacts: []), "the mouse finger ends at the touch report's time")
        var builder = TouchFrameBuilder()
        guard case .touch(let touch)? = try Panels.decoder(ilitek, "touchscreen").decode(touchBytes) else {
            return XCTFail("the ILITEK's first touch report did not decode as touch")
        }
        XCTAssertEqual(switched.last, builder.add(touch, at: 10.05))
        XCTAssertFalse(switched.last?.contacts.isEmpty ?? true, "the touch frame has the finger")

        // The mouse interface no longer counts: neither a move, a release, nor a new press.
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.3, y: 0.5), from: .mouse, at: 10.06), [])
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 0, x: 0.3, y: 0.5), from: .mouse, at: 10.07), [])
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.6, y: 0.5), from: .mouse, at: 10.30), [])
        XCTAssertEqual(reader.origin, .touchInterface)
    }

    func testAMouseFingerThatHasLiftedIsNotEndedTwice() throws {
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        _ = reader.add(Panels.ilitekMouse(buttons: 1, x: 0.25, y: 0.5), from: .mouse, at: 1.00)
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 0, x: 0.25, y: 0.5), from: .mouse, at: 1.10),
                       [ContactFrame(time: 1.10, contacts: [])])
        let switched = reader.add(try firstTouchReport(of: ilitek), from: .touch, at: 2.00)
        XCTAssertEqual(switched.count, 1, "no finger was down on the mouse interface, so only the touch frame")
        XCTAssertFalse(switched.first?.contacts.isEmpty ?? true)
    }

    func testATouchReportBeforeAnyMouseReport() throws {
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        XCTAssertEqual(reader.origin, .undetermined)
        let frames = reader.add(try firstTouchReport(of: ilitek), from: .touch, at: 5.0)
        XCTAssertEqual(reader.origin, .touchInterface)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .mouse, at: 5.1), [])
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 0, x: 0.5, y: 0.5), from: .mouse, at: 5.2), [])
        XCTAssertEqual(reader.origin, .touchInterface)
    }

    // MARK: - What is ignored

    /// A touch report arriving on the mouse interface is not a touch: it gives nothing and changes
    /// nothing.
    ///
    /// The plan's example, the ILITEK's touch bytes fed as `.mouse`, can't show this: its mouse
    /// interface uses report ID 4 too, and reads the first six bytes of every touch report as a
    /// valid absolute pointer report. Only routing reports by the interface they arrive on tells
    /// those apart, and the device layer does route them so. The last assertion records that.
    func testTouchReportsOnTheMouseInterfaceAreIgnored() throws {
        // A mouse interface whose descriptor also has finger collections reads the strip's touch
        // report as touch. Arriving on the mouse interface, it is ignored.
        let strip = try Panels.wch()
        let combined = try Panels.combinedDecoder()
        guard case .touch? = combined.decode(Panels.wchTouch(id: 0, x: 0.5, y: 0.5)) else {
            return XCTFail("the combined interface does not read report 0x0D as touch")
        }
        var reader = TouchscreenReader(touch: try Panels.decoder(strip, "touchscreen"), mouse: combined)
        XCTAssertEqual(reader.add(Panels.wchTouch(id: 0, x: 0.5, y: 0.5), from: .mouse, at: 1.0), [])
        XCTAssertEqual(reader.origin, .undetermined)

        // The strip's own touch bytes on its own mouse interface: report 0x0D is unknown there.
        var plain = TouchscreenReader(touch: try Panels.decoder(strip, "touchscreen"), mouse: try Panels.decoder(strip, "mouse"))
        XCTAssertEqual(plain.add(Panels.wchTouch(id: 0, x: 0.5, y: 0.5), from: .mouse, at: 1.0), [])
        XCTAssertEqual(plain.origin, .undetermined)

        // The ILITEK's mouse report on its touch interface: report 4 there is a 64-byte touch
        // report, so the 6 bytes are short and read as nothing.
        let ilitek = try Panels.ilitek()
        var both = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        XCTAssertEqual(both.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .touch, at: 1.0), [])
        XCTAssertEqual(both.origin, .undetermined)

        // Why the ILITEK's touch bytes can't be the example.
        guard case .pointer(let pointer)? = try Panels.decoder(ilitek, "mouse").decode(try firstTouchReport(of: ilitek)) else {
            return XCTFail("the ILITEK's mouse interface no longer reads its touch bytes as a pointer: use them in this test")
        }
        XCTAssertNotNil(pointer.position, "an absolute pointer, as far as the mouse interface can tell")
    }

    /// A touch report with every tip off is not a finger: it decides nothing, and doesn't end a
    /// mouse finger.
    func testAnEmptyTouchReportDecidesNothing() throws {
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        let empty = try emptyTouchReport(of: ilitek)
        XCTAssertEqual(reader.add(empty, from: .touch, at: 1.0), [])
        XCTAssertEqual(reader.origin, .undetermined)

        let press = reader.add(Panels.ilitekMouse(buttons: 1, x: 0.4, y: 0.6), from: .mouse, at: 1.1)
        XCTAssertEqual(reader.origin, .mouseInterface)
        XCTAssertEqual(press.count, 1)
        XCTAssertEqual(press.first?.contacts.count, 1, "one finger")

        XCTAssertEqual(reader.add(empty, from: .touch, at: 1.2), [], "an empty touch report doesn't take over")
        XCTAssertEqual(reader.origin, .mouseInterface)
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 0, x: 0.4, y: 0.6), from: .mouse, at: 1.3),
                       [ContactFrame(time: 1.3, contacts: [])], "the mouse finger is still the one down")

        // A tip left on in a slot the Contact Count doesn't cover is not a contact either.
        let strip = try Panels.wch()
        var uncounted = Panels.wchTouch(id: 0, x: 0.5, y: 0.5)
        uncounted[53] = 0
        guard case .touch(let report)? = try Panels.decoder(strip, "touchscreen").decode(uncounted), report.slots.first?.tip == true else {
            return XCTFail("the hand-made report does not decode as a tip in slot 0 with a count of 0")
        }
        var stripReader = TouchscreenReader(touch: try Panels.decoder(strip, "touchscreen"), mouse: try Panels.decoder(strip, "mouse"))
        XCTAssertEqual(stripReader.add(uncounted, from: .touch, at: 2.0), [])
        XCTAssertEqual(stripReader.origin, .undetermined)
    }

    /// Some panels put their Mouse collection on the touchscreen interface itself. Its pointer
    /// reports are the finger, as they would be from a mouse interface: every strip take, its
    /// pointer bytes fed as `.touch` to such an interface, gives exactly the frames
    /// `PointerFingerReader` gives.
    func testAPointerOnTheTouchInterfaceIsAFinger() throws {
        let strip = try Panels.wch()
        let combined = try Panels.combinedDecoder()
        let mouse = try Panels.decoder(strip, "mouse")
        for number in 1...20 {
            var reader = TouchscreenReader(touch: combined, mouse: nil)
            var expected = PointerFingerReader(guardInterval: 0.05)
            var frames: [ContactFrame] = []
            var expectedFrames: [ContactFrame] = []
            for report in try Panels.take(strip, number).reports {
                frames += reader.add(report.bytes, from: .touch, at: report.hostTime)
                if case .pointer(let pointer)? = mouse.decode(report.bytes), let frame = expected.add(pointer, at: report.hostTime) {
                    expectedFrames.append(frame)
                }
            }
            XCTAssertEqual(reader.origin, .mouseInterface, "take \(number)")
            XCTAssertFalse(expectedFrames.isEmpty, "take \(number) gave no frame to compare")
            XCTAssertEqual(frames, expectedFrames, "take \(number)")
        }

        // On one interface too, a touch report wins, and pointer reports are ignored afterwards.
        var reader = TouchscreenReader(touch: combined, mouse: nil)
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 1, x: 0.2, y: 0.2), from: .touch, at: 5.00).count, 1)
        let switched = reader.add(Panels.wchTouch(id: 3, x: 0.6, y: 0.6), from: .touch, at: 5.01)
        XCTAssertEqual(reader.origin, .touchInterface)
        XCTAssertEqual(switched.first, ContactFrame(time: 5.01, contacts: []))
        XCTAssertEqual(switched.last?.contacts.map(\.id), [3])
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 1, x: 0.2, y: 0.2), from: .touch, at: 5.02), [])
    }

    func testARelativeMouseIsNeverAFinger() throws {
        // A relative mouse: the wch.cn's mouse descriptor with X and Y marked relative (Input 0x06).
        var bytes = try Panels.descriptor(Panels.wch(), "mouse")
        let absoluteX: [UInt8] = [0x26, 0xFF, 0x3F, 0x81, 0x02]
        let absoluteY: [UInt8] = [0x26, 0x7F, 0x25, 0x81, 0x02]
        for pattern in [absoluteX, absoluteY] {
            let at = try XCTUnwrap(range(of: pattern, in: bytes), "pattern not found in the wch.cn mouse descriptor")
            bytes[at + 4] = 0x06
        }
        let relative = try XCTUnwrap(InterfaceDecoder(descriptor: bytes))
        guard case .pointer(let pointer)? = relative.decode(Panels.wchMouse(buttons: 1, x: 0.01, y: 0.01)) else {
            return XCTFail("the relative mouse does not decode as a pointer")
        }
        XCTAssertNil(pointer.position, "the modified descriptor is relative")

        var reader = TouchscreenReader(touch: nil, mouse: relative)
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 1, x: 0.01, y: 0.01), from: .mouse, at: 1.0), [])
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 0, x: 0.01, y: 0.01), from: .mouse, at: 1.1), [])
        XCTAssertEqual(reader.origin, .undetermined, "a relative pointer decides nothing")
    }

    func testGarbageChangesNothing() throws {
        let garbage: [[UInt8]] = [[], [0x04], [0x07], [0x0D], [UInt8](repeating: 0, count: 4096)]
        for panel in [try Panels.wch(), try Panels.ilitek()] {
            var reader = TouchscreenReader(touch: try Panels.decoder(panel, "touchscreen"), mouse: try Panels.decoder(panel, "mouse"))
            for bytes in garbage {
                XCTAssertEqual(reader.add(bytes, from: .touch, at: 1.0), [], "\(bytes.count) bytes on the touch interface")
                XCTAssertEqual(reader.add(bytes, from: .mouse, at: 1.0), [], "\(bytes.count) bytes on the mouse interface")
            }
            XCTAssertEqual(reader.origin, .undetermined)
        }

        // Garbage changes nothing once the origin is decided either.
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        _ = reader.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .mouse, at: 1.0)
        for bytes in garbage {
            XCTAssertEqual(reader.add(bytes, from: .touch, at: 1.01), [])
            XCTAssertEqual(reader.add(bytes, from: .mouse, at: 1.01), [])
        }
        XCTAssertEqual(reader.origin, .mouseInterface)
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 0, x: 0.5, y: 0.5), from: .mouse, at: 1.02),
                       [ContactFrame(time: 1.02, contacts: [])], "the finger is still the one that was down")
    }

    // MARK: - Reset

    func testResetForgets() throws {
        let strip = try Panels.wch()
        var reader = TouchscreenReader(touch: try Panels.decoder(strip, "touchscreen"), mouse: try Panels.decoder(strip, "mouse"))
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 1, x: 0.2, y: 0.2), from: .mouse, at: 1.00).count, 1)
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 0, x: 0.2, y: 0.2), from: .mouse, at: 1.10),
                       [ContactFrame(time: 1.10, contacts: [])])
        XCTAssertEqual(reader.origin, .mouseInterface)

        // Without a reset, a press 10 ms after the release is refused by the 50 ms guard.
        var unreset = reader
        XCTAssertEqual(unreset.add(Panels.wchMouse(buttons: 1, x: 0.8, y: 0.8), from: .mouse, at: 1.11), [])

        reader.reset()
        XCTAssertEqual(reader.origin, .undetermined)
        let next = reader.add(Panels.wchMouse(buttons: 1, x: 0.8, y: 0.8), from: .mouse, at: 1.11)
        XCTAssertEqual(next.count, 1, "the next press is a new finger, and the guard doesn't refuse it")
        XCTAssertEqual(next.first?.contacts.first?.position.x ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(reader.origin, .mouseInterface)
    }

    func testResetWhileAFingerIsDownEndsNothingAndStartsClean() throws {
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: try Panels.decoder(ilitek, "mouse"))
        _ = reader.add(Panels.ilitekMouse(buttons: 1, x: 0.2, y: 0.2), from: .mouse, at: 1.0)
        reader.reset()
        // The mouse finger is forgotten: a touch report now gives only its own frame.
        let frames = reader.add(try firstTouchReport(of: ilitek), from: .touch, at: 1.5)
        XCTAssertEqual(frames.count, 1)
        XCTAssertFalse(frames.first?.contacts.isEmpty ?? true)
        XCTAssertEqual(reader.origin, .touchInterface)
        // A touch reader that was reset may read from the mouse again.
        reader.reset()
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.2, y: 0.2), from: .mouse, at: 2.0).count, 1)
        XCTAssertEqual(reader.origin, .mouseInterface)
    }

    // MARK: - Unreadable, and a mouse that comes later

    func testNoUsableInterfaceIsUnreadable() throws {
        var reader = TouchscreenReader(touch: nil, mouse: nil)
        XCTAssertEqual(reader.origin, .unreadable)
        let ilitek = try Panels.ilitek()
        XCTAssertEqual(reader.add(try firstTouchReport(of: ilitek), from: .touch, at: 1), [])
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .mouse, at: 1), [])
        XCTAssertEqual(reader.origin, .unreadable)
        reader.reset()
        XCTAssertEqual(reader.origin, .unreadable, "a reset doesn't make it readable")
    }

    /// A touchscreen interface with no finger collections may still carry a pointer: it is read.
    func testATouchInterfaceWithOnlyAPointerStillFeeds() throws {
        // The ILITEK's mouse descriptor, standing in for a touchscreen interface without fingers.
        let ilitek = try Panels.ilitek()
        var reader = TouchscreenReader(touch: try Panels.decoder(ilitek, "mouse"), mouse: nil)
        XCTAssertEqual(reader.origin, .undetermined)
        XCTAssertEqual(reader.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .touch, at: 1).count, 1)
        XCTAssertEqual(reader.origin, .mouseInterface)
    }

    func testAMouseInterfaceAddedLater() throws {
        let strip = try Panels.wch()
        var reader = TouchscreenReader(touch: nil, mouse: nil)
        XCTAssertEqual(reader.origin, .unreadable)
        reader.setMouse(try Panels.decoder(strip, "mouse"))
        XCTAssertEqual(reader.origin, .undetermined)
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 1, x: 0.4, y: 0.4), from: .mouse, at: 1).count, 1)
        XCTAssertEqual(reader.origin, .mouseInterface)

        // A touch reader whose origin is decided keeps it when a mouse is added.
        let ilitek = try Panels.ilitek()
        var touchFirst = TouchscreenReader(touch: try Panels.decoder(ilitek, "touchscreen"), mouse: nil)
        _ = touchFirst.add(try firstTouchReport(of: ilitek), from: .touch, at: 1)
        touchFirst.setMouse(try Panels.decoder(ilitek, "mouse"))
        XCTAssertEqual(touchFirst.origin, .touchInterface)
        XCTAssertEqual(touchFirst.add(Panels.ilitekMouse(buttons: 1, x: 0.5, y: 0.5), from: .mouse, at: 2), [])
    }

    func testAMouseInterfaceThatGoesAwayEndsNothingByItself() throws {
        let strip = try Panels.wch()
        var reader = TouchscreenReader(touch: nil, mouse: try Panels.decoder(strip, "mouse"))
        _ = reader.add(Panels.wchMouse(buttons: 1, x: 0.4, y: 0.4), from: .mouse, at: 1)
        reader.setMouse(nil)
        XCTAssertEqual(reader.origin, .mouseInterface, "the origin stays what it was until the next take")
        XCTAssertEqual(reader.add(Panels.wchMouse(buttons: 0, x: 0.4, y: 0.4), from: .mouse, at: 2), [],
                       "nothing is read from an interface the reader no longer has")
    }

    // MARK: - Helpers

    /// The first report of the ILITEK's first take: one finger down.
    private func firstTouchReport(of ilitek: SurveyFixtures.Touchscreen) throws -> [UInt8] {
        let take = try Panels.take(ilitek, 1)
        let bytes = try XCTUnwrap(take.reports.first?.bytes)
        let touch = try Panels.decoder(ilitek, "touchscreen")
        guard case .touch(let report)? = touch.decode(bytes), report.slots.contains(where: \.tip) else {
            return try XCTUnwrap(nil, "the ILITEK's first report has no finger down")
        }
        return bytes
    }

    /// A report of the ILITEK's first take with every tip off: the lift at its end.
    private func emptyTouchReport(of ilitek: SurveyFixtures.Touchscreen) throws -> [UInt8] {
        let touch = try Panels.decoder(ilitek, "touchscreen")
        let lift = try Panels.take(ilitek, 1).reports.last { report in
            guard case .touch(let decoded)? = touch.decode(report.bytes) else { return false }
            return !decoded.slots.contains(where: \.tip)
        }
        return try XCTUnwrap(lift?.bytes, "the ILITEK's first take has no report with every tip off")
    }

    private func range(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= pattern.count else { return nil }
        return (0...(bytes.count - pattern.count)).first { Array(bytes[$0..<($0 + pattern.count)]) == pattern }
    }
}
