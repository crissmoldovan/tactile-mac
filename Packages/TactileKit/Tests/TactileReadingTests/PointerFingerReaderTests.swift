import CoreGraphics
import XCTest
import TactileReading
import TactileTestSupport

/// The wch.cn "TouchScreen" in survey A: a 12.3-inch strip that stayed in mouse mode.
private let wchVendorID = 0x27c0, wchProductID = 0x0859

/// The survey's millimetres for the strip: the size its display, 12.3FHD, reports (240.5 × 90.2 mm),
/// as the survey measured them, and so the spec's figures. On the
/// inferred 12.3-inch glass, 292.5 × 109.7 mm, every distance is about a fifth longer.
private let surveyMillimetres = CGSize(width: 240.5, height: 90.2)

/// A report with the first button down at a glass point.
private func pressed(_ x: CGFloat, _ y: CGFloat) -> PointerReport {
    PointerReport(buttons: 1, position: CGPoint(x: x, y: y))
}

/// A report with every button up. A mouse-mode panel still sends its last point.
private func released(_ x: CGFloat = 0.5, _ y: CGFloat = 0.5) -> PointerReport {
    PointerReport(buttons: 0, position: CGPoint(x: x, y: y))
}

/// The frame of one finger, contact 0, at a glass point.
private func finger(_ x: CGFloat, _ y: CGFloat, at time: TimeInterval) -> ContactFrame {
    ContactFrame(time: time, contacts: [Contact(id: 0, position: CGPoint(x: x, y: y))])
}

/// The frame of a clear glass.
private func clear(at time: TimeInterval) -> ContactFrame {
    ContactFrame(time: time, contacts: [])
}

/// One touch as frames show it: a run of non-empty frames, and the empty frame that ended it.
private struct Run {
    var first: ContactFrame
    var last: ContactFrame
    var endedAt: TimeInterval?
}

private func runs(_ frames: [ContactFrame]) -> [Run] {
    var result: [Run] = []
    var open = false
    for frame in frames {
        if frame.contacts.isEmpty {
            if open { result[result.count - 1].endedAt = frame.time }
            open = false
        } else if open {
            result[result.count - 1].last = frame
        } else {
            result.append(Run(first: frame, last: frame, endedAt: nil))
            open = true
        }
    }
    return result
}

final class PointerFingerReaderTests: XCTestCase {

    // MARK: - Hand-built reports

    func testPressMoveRelease() {
        var reader = PointerFingerReader()
        let frames = [
            reader.add(pressed(0.1, 0.2), at: 10.000),
            reader.add(pressed(0.15, 0.2), at: 10.008),
            reader.add(released(0.15, 0.2), at: 10.016),
        ]
        XCTAssertEqual(frames, [finger(0.1, 0.2, at: 10.000), finger(0.15, 0.2, at: 10.008), clear(at: 10.016)])
    }

    func testReportsWithTheButtonUpGiveNothing() {
        var reader = PointerFingerReader()
        XCTAssertNil(reader.add(released(0.1, 0.1), at: 1.000))
        XCTAssertNil(reader.add(released(0.2, 0.1), at: 1.008))
        XCTAssertNil(reader.add(released(0.3, 0.1), at: 1.016))
    }

    func testARelativeMouseNeverTouches() {
        var reader = PointerFingerReader()
        let relative = PointerReport(buttons: 1, position: nil, delta: CGVector(dx: 3, dy: -2))
        XCTAssertNil(reader.add(relative, at: 1.000))
        XCTAssertNil(reader.add(relative, at: 1.008), "nor does it while the button is held")
        XCTAssertNil(reader.add(PointerReport(buttons: 0, position: nil, delta: .zero), at: 1.016),
                     "and its release gives no empty frame: nothing was touching")
    }

    func testAPressRightAfterAReleaseIsRefusedUntilItLifts() {
        var reader = PointerFingerReader()
        let t = 20.0
        XCTAssertEqual(reader.add(pressed(0.4, 0.7), at: t - 0.100), finger(0.4, 0.7, at: t - 0.100))
        XCTAssertEqual(reader.add(released(0.4, 0.7), at: t), clear(at: t))

        XCTAssertNil(reader.add(pressed(0.65, 0.25), at: t + 0.016), "the press")
        XCTAssertNil(reader.add(pressed(0.66, 0.25), at: t + 0.024), "its movement")
        XCTAssertNil(reader.add(released(0.66, 0.25), at: t + 0.032), "its release")

        XCTAssertEqual(reader.add(pressed(0.5, 0.5), at: t + 0.5), finger(0.5, 0.5, at: t + 0.5))
    }

    func testAPressAfterTheGuardIntervalIsANewTouch() {
        var reader = PointerFingerReader()
        let t = 30.0
        _ = reader.add(pressed(0.63, 0.28), at: t - 0.059)
        XCTAssertEqual(reader.add(released(0.63, 0.28), at: t), clear(at: t))
        XCTAssertEqual(reader.add(pressed(0.63, 0.29), at: t + 0.133), finger(0.63, 0.29, at: t + 0.133))
    }

    // MARK: - The strip's recorded takes

    /// Survey A's wch.cn take `number`, its mouse interface's reports decoded and read as one finger
    /// by a reader of its own.
    private func stripFrames(take number: Int, guardInterval: TimeInterval? = nil) throws -> [ContactFrame] {
        let strip = try XCTUnwrap(SurveyFixtures.surveyA.touchscreen(vendorID: wchVendorID, productID: wchProductID))
        let interface = try XCTUnwrap(strip.interfaces.first { $0.key == "mouse" }, "no mouse interface")
        let decoder = try XCTUnwrap(InterfaceDecoder(descriptor: interface.descriptor), "the descriptor did not parse")
        let take = try XCTUnwrap(strip.takes.first { $0.number == number }, "no take \(number)")
        var reader = guardInterval.map { PointerFingerReader(guardInterval: $0) } ?? PointerFingerReader()
        var frames: [ContactFrame] = []
        for (index, recorded) in take.reports.enumerated() where recorded.interfaceKey == "mouse" {
            guard case .pointer(let pointer)? = decoder.decode(recorded.bytes) else {
                XCTFail("take \(number) report \(index) did not decode as a pointer report")
                continue
            }
            if let frame = reader.add(pointer, at: recorded.hostTime) { frames.append(frame) }
        }
        return frames
    }

    func testTheStripsTapIsOneTouch() throws {
        XCTAssertEqual(runs(try stripFrames(take: 9)).count, 1)
    }

    /// The four fingers lifted, and 16 ms later the strip pressed again, about 60 mm away, for 10 ms.
    /// No finger moves that far that fast: the guard refuses that press, and only that press.
    func testTheStripsFourFingerSwipeLeavesNoPhantomTouch() throws {
        let unguarded = runs(try stripFrames(take: 19, guardInterval: 0))
        let guarded = runs(try stripFrames(take: 19))
        XCTAssertEqual(guarded.count, unguarded.count - 1, "the guard refuses one press")

        let refused = unguarded.filter { run in !guarded.contains { $0.first.time == run.first.time } }
        XCTAssertEqual(refused.count, 1)
        let phantom = try XCTUnwrap(refused.first)
        let index = try XCTUnwrap(unguarded.firstIndex { $0.first.time == phantom.first.time })
        XCTAssertGreaterThan(index, 0, "the refused press follows a touch")
        guard index > 0 else { return }
        let before = unguarded[index - 1]

        let releasedAt = try XCTUnwrap(before.endedAt)
        XCTAssertEqual(phantom.first.time - releasedAt, 0.016, accuracy: 0.001, "it began 16 ms after a release")
        let from = try XCTUnwrap(before.last.contacts.first).position
        let to = try XCTUnwrap(phantom.first.contacts.first).position
        let millimetres = hypot((to.x - from.x) * surveyMillimetres.width, (to.y - from.y) * surveyMillimetres.height)
        XCTAssertEqual(millimetres, 60, accuracy: 2, "about 60 mm from where the swipe lifted")
    }

    /// The known limit: such a panel reports one point however many fingers touch it, and a
    /// two-finger tap arrives as two presses 0.133 s apart, indistinguishable from a quick
    /// double-tap.
    func testTheStripsTwoFingerTapIsTwoTouches() throws {
        XCTAssertEqual(runs(try stripFrames(take: 16)).count, 2)
    }

    // MARK: - Beyond the plan's table: inputs the rules must survive

    /// The strip sends one or two more button-up reports after each release. Every take ends with
    /// one empty frame per touch, and nothing after the last.
    func testEveryStripTakeEndsWithOneEmptyFramePerTouch() throws {
        for take in 1...20 {
            let frames = try stripFrames(take: take)
            XCTAssertFalse(frames.isEmpty, "take \(take) gave no frame")
            XCTAssertEqual(frames.last?.contacts, [], "take \(take) does not end with a clear glass")
            XCTAssertEqual(frames.filter(\.contacts.isEmpty).count, runs(frames).count,
                           "take \(take): one empty frame per touch")
            XCTAssertEqual(Set(frames.flatMap { $0.contacts.map(\.id) }), [0], "take \(take): one finger, contact 0")
        }
    }

    /// The finger is the first button. Other buttons, alone, are no touch; with the first, they
    /// change nothing.
    func testOnlyTheFirstButtonTouches() {
        var reader = PointerFingerReader()
        XCTAssertNil(reader.add(PointerReport(buttons: 0b010, position: CGPoint(x: 0.1, y: 0.1)), at: 1.0))
        XCTAssertNil(reader.add(PointerReport(buttons: 0b100, position: CGPoint(x: 0.1, y: 0.1)), at: 1.1))
        XCTAssertEqual(reader.add(PointerReport(buttons: 0b011, position: CGPoint(x: 0.2, y: 0.1)), at: 1.2), finger(0.2, 0.1, at: 1.2))
        XCTAssertEqual(reader.add(PointerReport(buttons: 0b101, position: CGPoint(x: 0.3, y: 0.1)), at: 1.3), finger(0.3, 0.1, at: 1.3))
        XCTAssertEqual(reader.add(PointerReport(buttons: 0b110, position: CGPoint(x: 0.3, y: 0.1)), at: 1.4), clear(at: 1.4),
                       "the first button going up ends the touch, whatever the others do")
        XCTAssertNil(reader.add(PointerReport(buttons: 0b010, position: CGPoint(x: 0.3, y: 0.1)), at: 1.5))
    }

    /// A press is timed at the report where the button went down, with or without a position, and
    /// becomes a contact at the first report that has one. A report without a position, while the
    /// button is held, gives nothing and ends nothing.
    func testAPressWhoseFirstReportHasNoPosition() {
        var reader = PointerFingerReader()
        XCTAssertNil(reader.add(PointerReport(buttons: 1, position: nil), at: 1.000))
        XCTAssertEqual(reader.add(pressed(0.2, 0.2), at: 1.008), finger(0.2, 0.2, at: 1.008))
        XCTAssertNil(reader.add(PointerReport(buttons: 1, position: nil), at: 1.016))
        XCTAssertEqual(reader.add(pressed(0.25, 0.2), at: 1.024), finger(0.25, 0.2, at: 1.024))
        XCTAssertEqual(reader.add(released(), at: 1.032), clear(at: 1.032))

        // The guard judges the press when the button goes down, not when a position arrives.
        XCTAssertNil(reader.add(PointerReport(buttons: 1, position: nil), at: 1.040))
        XCTAssertNil(reader.add(pressed(0.3, 0.2), at: 1.200), "a press that began 8 ms after the release")
        XCTAssertNil(reader.add(released(), at: 1.208))
    }

    /// The interval runs from the release that ended the last touch. A refused press's release
    /// does not restart it, and neither does the release of a press that never had a position.
    func testOnlyTheEndOfATouchStartsTheInterval() {
        var reader = PointerFingerReader()
        _ = reader.add(pressed(0.1, 0.1), at: 4.900)
        XCTAssertEqual(reader.add(released(), at: 5.000), clear(at: 5.000))
        XCTAssertNil(reader.add(pressed(0.6, 0.1), at: 5.010), "refused")
        XCTAssertNil(reader.add(released(), at: 5.030))
        XCTAssertEqual(reader.add(pressed(0.2, 0.1), at: 5.060), finger(0.2, 0.1, at: 5.060),
                       "60 ms after the touch ended, though 30 ms after the refused press lifted")
        XCTAssertEqual(reader.add(released(), at: 6.000), clear(at: 6.000))

        XCTAssertNil(reader.add(PointerReport(buttons: 1, position: nil), at: 6.100))
        XCTAssertNil(reader.add(PointerReport(buttons: 0, position: nil), at: 6.110))
        XCTAssertEqual(reader.add(pressed(0.3, 0.1), at: 6.120), finger(0.3, 0.1, at: 6.120),
                       "120 ms after the touch ended, though 10 ms after a press that never touched")
    }

    func testTwoReleasesInARowGiveOneEmptyFrame() {
        var reader = PointerFingerReader()
        _ = reader.add(pressed(0.1, 0.1), at: 1.000)
        XCTAssertEqual(reader.add(released(), at: 1.008), clear(at: 1.008))
        XCTAssertNil(reader.add(released(), at: 1.016))
    }

    func testGuardIntervalZeroRefusesNothing() {
        var reader = PointerFingerReader(guardInterval: 0)
        _ = reader.add(pressed(0.1, 0.1), at: 1.0)
        XCTAssertEqual(reader.add(released(), at: 2.0), clear(at: 2.0))
        XCTAssertEqual(reader.add(pressed(0.9, 0.9), at: 2.0), finger(0.9, 0.9, at: 2.0), "not even at the very instant of the release")
    }

    /// Times are the caller's. A press at the very time of the release is refused; a press stamped
    /// earlier than the release can't be shown to have come soon after it, and is a new touch, so a
    /// clock that steps back never leaves the reader refusing every press until it catches up.
    func testTimeStandingStillOrGoingBackwards() {
        var reader = PointerFingerReader()
        XCTAssertEqual(reader.add(pressed(0.1, 0.1), at: 100), finger(0.1, 0.1, at: 100))
        XCTAssertEqual(reader.add(pressed(0.2, 0.1), at: 100), finger(0.2, 0.1, at: 100), "time standing still")
        XCTAssertEqual(reader.add(pressed(0.3, 0.1), at: 99), finger(0.3, 0.1, at: 99), "time going backwards")
        XCTAssertEqual(reader.add(released(), at: 100), clear(at: 100))

        XCTAssertNil(reader.add(pressed(0.4, 0.1), at: 100), "a press at the very time of the release")
        XCTAssertNil(reader.add(released(), at: 100))

        XCTAssertEqual(reader.add(pressed(0.5, 0.1), at: 3), finger(0.5, 0.1, at: 3), "a press stamped before the release")
        XCTAssertEqual(reader.add(released(), at: 3.1), clear(at: 3.1))
        XCTAssertNil(reader.add(pressed(0.6, 0.1), at: 3.12), "the guard measures from that release now")
    }

    /// A refused press that is held gives nothing for as long as it is held, and the reader holds
    /// nothing more for it; its release puts the reader back as it was.
    func testARefusedPressHeldLongGivesNothingUntilItLifts() {
        var reader = PointerFingerReader()
        _ = reader.add(pressed(0.1, 0.1), at: 1.0)
        _ = reader.add(released(), at: 2.0)
        var given = 0
        for step in 0..<10_000 {
            let x = CGFloat(step % 100) / 100
            if reader.add(pressed(x, 0.5), at: 2.01 + TimeInterval(step) * 0.008) != nil { given += 1 }
        }
        XCTAssertEqual(given, 0)
        XCTAssertNil(reader.add(released(), at: 90.0))
        XCTAssertNil(reader.add(released(), at: 90.1))
        XCTAssertEqual(reader.add(pressed(0.7, 0.7), at: 90.2), finger(0.7, 0.7, at: 90.2))
    }

    /// Reports come from whatever is plugged in, and times and the interval from the caller. None
    /// may trap the reader.
    func testNoReportOrTimeCanTrapTheReader() {
        let reports = [
            PointerReport(buttons: Int.max, position: CGPoint(x: CGFloat.nan, y: .infinity)),
            PointerReport(buttons: Int.min, position: CGPoint(x: -3, y: 7)),
            PointerReport(buttons: -1, position: nil, delta: CGVector(dx: CGFloat.infinity, dy: .nan)),
            PointerReport(buttons: 0, position: nil),
            PointerReport(buttons: 1, position: CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: .leastNonzeroMagnitude)),
        ]
        let times: [TimeInterval] = [0, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e-300]
        for interval in [0.05, 0, -1, .nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            var reader = PointerFingerReader(guardInterval: interval)
            for time in times {
                for report in reports + reports.reversed() {
                    _ = reader.add(report, at: time)
                }
            }
        }
        // Bit 0 of a negative mask is the first button.
        var reader = PointerFingerReader()
        XCTAssertEqual(reader.add(PointerReport(buttons: -1, position: CGPoint(x: 0.5, y: 0.5)), at: 1), finger(0.5, 0.5, at: 1))
        XCTAssertEqual(reader.add(PointerReport(buttons: Int.min, position: CGPoint(x: 0.5, y: 0.5)), at: 2), clear(at: 2))
    }
}
