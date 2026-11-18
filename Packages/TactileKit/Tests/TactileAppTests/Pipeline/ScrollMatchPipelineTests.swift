// How a scroll is posted, decided once as it begins, from the app under the pointer: matched to
// VS Code's scrolling in the editors built on Monaco, today's everywhere else; and Automatic's
// question, put to the app whose window is under the finger. Nothing here reads the window list or
// asks Accessibility: the app under a point is the fake's answer.

import CoreGraphics
import CryptoKit
import Foundation
import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class ScrollMatchPipelineTests: XCTestCase {

    /// The ILITEK and the strip, one finger always scrolling.
    private var ilitekScrolling: Driving { Desk.driving(on: Desk.hdmi, diagonal: 23.8, oneFinger: .alwaysScroll) }
    private var stripScrolling: Driving {
        Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures, oneFinger: .alwaysScroll)
    }

    private func pipeline(_ driving: Driving, _ outputs: RecordingOutputs, id: TouchscreenID = Desk.ilitekID) -> TouchPipeline {
        TouchPipeline(id: id, driving: driving, outputs: outputs, cancelOther: { other, _ in
            XCTFail("nothing to take over from \(other)")
        })
    }

    /// Feeds `frames` at their own times, ticking 60 times a second in between as the model's clock
    /// does, then lets `settle` seconds pass, ticking, so momentum and the session can end.
    private func play(_ frames: [ContactFrame], into pipeline: TouchPipeline, settle: TimeInterval = 2) {
        guard var time = frames.first?.time else { return }
        for frame in frames {
            while time + 1.0 / 60 < frame.time {
                time += 1.0 / 60
                pipeline.tick(at: time)
            }
            time = frame.time
            pipeline.handle(frame)
        }
        let end = time + settle
        while time < end {
            time = min(end, time + 1.0 / 60)
            pipeline.tick(at: time)
        }
    }

    /// A one-finger flick upwards from the middle of the glass, 10 ms a frame, lifting while it
    /// moves fast: it coasts.
    private func flick(at t0: TimeInterval = 100, x: CGFloat = 0.5) -> [ContactFrame] {
        (0...15).map { glassFrame(t0 + Double($0) * 0.01, (0, x, 0.8 - CGFloat($0) * 0.02)) }
            + [glassFrame(t0 + 0.16)]
    }

    /// Every event posted, field by field, as one digest.
    private func digest(_ events: [PostedEvent]) -> String {
        let text = events.map {
            "\($0.kind.rawValue) \($0.location.x),\($0.location.y) \($0.clickState) \($0.scrollPhase) "
                + "\($0.momentumPhase) \($0.scrollY) \($0.scrollX) \($0.gesturePhase)"
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Any other app: today's events

    /// Strip take 11 (a one-finger drag at about 120 Hz, scrolled here) and a flick that coasts,
    /// as the pipeline at d69e358, before scrolls were matched to any app, posted them: digests of
    /// every event's fields, recorded then. With no app's window under the finger, with an app that
    /// isn't an editor on Monaco (or has no identifier), and with VS Code open elsewhere but not
    /// under the finger, the same events, field by field. (`EventSenderScrollMatchTests` compares the sender's events with today's byte for
    /// byte.)
    func testWithNoAppAnsweringOrAnyOtherAppTheEventsAreTodays() throws {
        let cases: [(String, Driving, TouchscreenID, [ContactFrame], count: Int, digest: String)] = [
            ("strip take 11", stripScrolling, Desk.stripID, try SurveyTakes.strip(take: 11), 106,
             "7d43000cdc34e462b7dca4599a49eda7d89cfe6b0c455c36bc239f5f5acc3771"),
            ("flick", ilitekScrolling, Desk.ilitekID, flick(), 85,
             "be295aa2d5ac8f61e572b458b0b563467bff168975140b8fd052b60d690b4f3a"),
        ]
        let elsewhere = CGRect(x: -2048, y: 24, width: 2048, height: 1280)  // the display on the left
        let answers: [(String, (CGPoint) -> AppUnderPoint?)] = [
            ("no app", { _ in nil }),
            ("Finder", { _ in Self.app("com.apple.finder") }),
            ("no identifier", { _ in Self.app(nil) }),
            ("an empty identifier", { _ in Self.app("") }),
            ("VS Code elsewhere", { Self.app(elsewhere.contains($0) ? Self.vsCode : "com.apple.Terminal") }),
        ]
        for (label, driving, id, frames, count, expected) in cases {
            for (answer, app) in answers {
                let outputs = RecordingOutputs()
                outputs.appAnswer = app
                play(frames, into: pipeline(driving, outputs, id: id))
                XCTAssertEqual(outputs.record.appQuestions.count, 1, "\(label), \(answer): asked once, as the scroll began")
                XCTAssertEqual(outputs.events.count, count, "\(label), \(answer)")
                XCTAssertEqual(digest(outputs.events), expected, "\(label), \(answer)")
            }
        }
    }

    // MARK: - Deciding once per scroll

    private static let vsCode = "com.microsoft.VSCode"

    /// An app with a window under a point, by its bundle identifier.
    private static func app(_ bundleIdentifier: String?) -> AppUnderPoint {
        AppUnderPoint(pid: 321, bundleIdentifier: bundleIdentifier)
    }

    /// Where `driving` puts the glass point (`x`, `y`), fractions of the glass, on the desktop.
    private func desktop(_ x: CGFloat, _ y: CGFloat, _ driving: Driving) -> CGPoint {
        driving.mapping.desktopPoint(forDisplay: driving.mapping.displayPoint(forGlass: CGPoint(x: x, y: y)))
    }

    /// One finger landing at (`x`, `y`) on the glass and moving right and down at 120 Hz for half a
    /// second, then resting a fifth of a second before it lifts, so nothing coasts.
    private func slowScroll(from x: CGFloat, _ y: CGFloat, at t0: TimeInterval) -> [ContactFrame] {
        (0...60).map { glassFrame(t0 + Double($0) / 120, (0, x + CGFloat($0) * 0.007, y + CGFloat($0) * 0.003)) }
            + [glassFrame(t0 + 0.7, (0, x + 0.42, y + 0.18)), glassFrame(t0 + 0.71)]
    }

    private func isWholeSteps(_ event: PostedEvent) -> Bool {
        event.scrollX % 4 == 0 && event.scrollY % 4 == 0
    }

    func testAScrollIsMatchedOnceAsItBeginsAndKeepsItWhereverTheFingerGoes() {
        let driving = ilitekScrolling
        let outputs = RecordingOutputs()
        // VS Code on the left half of the ILITEK's display, Finder on the right.
        let middle = desktop(0.5, 0.5, driving).x
        outputs.appAnswer = { Self.app($0.x < middle ? Self.vsCode : "com.apple.finder") }
        let ilitek = pipeline(driving, outputs)

        // It lands in VS Code and scrolls on across into Finder's half.
        play(slowScroll(from: 0.2, 0.3, at: 100), into: ilitek)
        XCTAssertEqual(outputs.record.appQuestions, [desktop(0.2, 0.3, driving)], "asked once, where it landed")
        let first = outputs.events(.scroll)
        XCTAssertEqual(first.map(\.scrollPhase).first, 1)
        XCTAssertEqual(first.map(\.scrollPhase).last, 4)
        XCTAssertTrue(first.allSatisfy(isWholeSteps), "matched to its end, in Finder's half too")
        XCTAssertGreaterThan(first.filter { $0.scrollX != 0 }.count, 10)

        // The next scroll lands in Finder: asked again, and posted as moved, as on its own.
        let before = outputs.events.count
        play(slowScroll(from: 0.55, 0.3, at: 110), into: ilitek)
        XCTAssertEqual(outputs.record.appQuestions, [desktop(0.2, 0.3, driving), desktop(0.55, 0.3, driving)])
        let second = outputs.events.dropFirst(before).filter { $0.kind == .scroll }
        let finder = RecordingOutputs()
        finder.appAnswer = { _ in Self.app("com.apple.finder") }
        play(slowScroll(from: 0.55, 0.3, at: 110), into: pipeline(driving, finder))
        XCTAssertEqual(second, finder.events(.scroll), "nothing carried over from the matched scroll")
        XCTAssertFalse(second.allSatisfy(isWholeSteps))

        // Back in VS Code: matched again.
        let third = outputs.events.count
        play(slowScroll(from: 0.1, 0.5, at: 120), into: ilitek)
        XCTAssertEqual(outputs.record.appQuestions.count, 3)
        XCTAssertTrue(outputs.events.dropFirst(third).filter { $0.kind == .scroll }.allSatisfy(isWholeSteps))
    }

    func testATwoFingerScrollIsMatchedFromWhereItBegins() {
        let driving = Desk.driving(on: Desk.hdmi, diagonal: 23.8)
        let outputs = RecordingOutputs()
        outputs.appAnswer = { _ in Self.app(Self.vsCode) }
        let frames = (0...60).map {
            glassFrame(100 + Double($0) / 120, (0, 0.4, 0.3 + CGFloat($0) * 0.004), (1, 0.5, 0.3 + CGFloat($0) * 0.004))
        } + [glassFrame(100.7, (0, 0.4, 0.54), (1, 0.5, 0.54)), glassFrame(100.71)]
        play(frames, into: pipeline(driving, outputs))

        let began = outputs.events.firstIndex { $0.kind == .scroll && $0.scrollPhase == 1 }
        let pointer = began.flatMap { index in outputs.events[..<index].last(where: { $0.kind == .move }) }?.location
        XCTAssertNotNil(pointer)
        XCTAssertEqual(outputs.record.appQuestions, pointer.map { [$0] }, "asked once, where the pointer went as it began")
        let scrolls = outputs.events(.scroll)
        XCTAssertGreaterThan(scrolls.count, 30)
        XCTAssertTrue(scrolls.allSatisfy(isWholeSteps))
    }

    func testMomentumIsMatchedWithItsScroll() {
        let matched = RecordingOutputs()
        matched.appAnswer = { _ in Self.app(Self.vsCode) }
        play(flick(), into: pipeline(ilitekScrolling, matched))
        let plain = RecordingOutputs()
        plain.appAnswer = { _ in Self.app("com.apple.finder") }
        play(flick(), into: pipeline(ilitekScrolling, plain))

        XCTAssertEqual(matched.record.appQuestions.count, 1, "asked as the scroll began, not again as it coasts")
        let coasting = matched.events(.scroll).filter { $0.momentumPhase != 0 }
        XCTAssertGreaterThan(coasting.count, 20)
        XCTAssertTrue(coasting.allSatisfy(isWholeSteps))
        // The same events, phase for phase; only the distances differ: four fifths, within a step of
        // 4 (and the fraction of a pixel the plain one drops at each end).
        XCTAssertEqual(matched.events.map { [$0.kind.rawValue, "\($0.scrollPhase)", "\($0.momentumPhase)"] },
                       plain.events.map { [$0.kind.rawValue, "\($0.scrollPhase)", "\($0.momentumPhase)"] })
        for (part, isPart) in [("scroll", { (event: PostedEvent) in event.scrollPhase != 0 }),
                               ("momentum", { (event: PostedEvent) in event.momentumPhase != 0 })] {
            let distance = { (outputs: RecordingOutputs) in outputs.events(.scroll).filter(isPart).map(\.scrollY).reduce(0, +) }
            XCTAssertLessThan(abs(Double(distance(matched)) - 0.8 * Double(distance(plain))), 4.8, part)
            XCTAssertGreaterThan(abs(distance(plain)), 100, part)
        }
    }

    // MARK: - Automatic asks the app beneath, never the circles

    /// The ILITEK in Automatic.
    private var ilitekAutomatic: Driving { Desk.driving(on: Desk.hdmi, diagonal: 23.8) }

    func testAutomaticAsksTheAppWhoseWindowIsUnderTheFinger() {
        let outputs = RecordingOutputs()
        outputs.appAnswer = { _ in AppUnderPoint(pid: 654, bundleIdentifier: "com.apple.Safari") }
        outputs.intentAnswer = .scroll
        play(slowScroll(from: 0.2, 0.3, at: 100), into: pipeline(ilitekAutomatic, outputs))

        let landing = desktop(0.2, 0.3, ilitekAutomatic)
        XCTAssertEqual(outputs.record.intentQuestions, [landing])
        XCTAssertEqual(outputs.record.intentApps, [654], "asked of the app beneath, not of the whole screen")
        XCTAssertEqual(outputs.record.appQuestions, [landing, landing], "for drag or scroll, then as the scroll began")
        XCTAssertGreaterThan(outputs.count(.scroll), 30)
        XCTAssertEqual(outputs.count(.down), 0)
    }

    func testAutomaticDragsWhereNoAppHasAWindowAndAsksNothingMore() {
        let outputs = RecordingOutputs()
        outputs.appAnswer = { _ in nil }
        outputs.intentAnswer = .scroll
        play(slowScroll(from: 0.2, 0.3, at: 100), into: pipeline(ilitekAutomatic, outputs))

        XCTAssertEqual(outputs.record.appQuestions, [desktop(0.2, 0.3, ilitekAutomatic)])
        XCTAssertEqual(outputs.record.intentQuestions, [], "no Accessibility question")
        XCTAssertEqual(outputs.count(.scroll), 0)
        XCTAssertEqual(outputs.count(.down), 1)
        XCTAssertEqual(outputs.count(.up), 1)
    }

    func testAutomaticInVSCodeScrollsMatched() {
        let outputs = RecordingOutputs()
        outputs.appAnswer = { _ in Self.app(Self.vsCode) }
        outputs.intentAnswer = .scroll
        play(slowScroll(from: 0.2, 0.3, at: 100), into: pipeline(ilitekAutomatic, outputs))

        XCTAssertEqual(outputs.record.intentApps, [321])
        let scrolls = outputs.events(.scroll)
        XCTAssertGreaterThan(scrolls.count, 30)
        XCTAssertTrue(scrolls.allSatisfy(isWholeSteps))
    }

    // MARK: - What VS Code does with it

    /// What VS Code moves its content by, in CSS pixels (points, at zoom 1), for one continuous
    /// scroll event of `d` points, traced through the open-source code of Chromium, Blink and VS
    /// Code (the files are named below). Chromium reads the point delta as a float, makes it
    /// ticks of 40 (`web_input_event_builders_mac.mm`); Blink makes `wheelDeltaY` an int of
    /// ticks × 120 ÷ devicePixelRatio (`wheel_event.cc`, 1 here: a Retina scale cancels out);
    /// VS Code divides by 120 (`mouseEvent.ts`), multiplies by its sensitivity (1) and by 50, and
    /// rounds away from zero (`scrollableElement.ts`, `_onMouseWheel`). About ceil(1.25 × d).
    static func monacoPixels(_ d: Int64) -> Int64 {
        let ticks = Float(Double(Float(d)) / 40)
        let wheelDelta = Double(ticks * 120).rounded(.towardZero)
        let scroll = 50 * (wheelDelta / 120 * 1)
        return Int64(scroll < 0 ? scroll.rounded(.down) : scroll.rounded(.up))
    }

    func testMonacoMovesFiveForEveryFourPostedAndMoreForSmallEvents() {
        // 1.25 × d, rounded up, so the smaller the event the more it overshoots.
        XCTAssertEqual([1, 2, 3, 4, 5, 10, 20, 40].map(Self.monacoPixels), [2, 3, 4, 5, 7, 13, 25, 50])
        for k: Int64 in 1...10 {
            XCTAssertEqual(Self.monacoPixels(4 * k), 5 * k)
            XCTAssertEqual(Self.monacoPixels(-4 * k), -5 * k)
        }
        // Not every multiple of 4: VS Code's own floating point (132 ÷ 120 × 50 is
        // 55.00000000000001 in JavaScript) moves one pixel more for 44 and 88. A 120 Hz scroll's
        // steps are far smaller; a fast flick's momentum can reach them.
        XCTAssertEqual(Self.monacoPixels(44), 56)
        XCTAssertEqual(Self.monacoPixels(88), 111)
        XCTAssertEqual((1...25).filter { Self.monacoPixels(4 * $0) != 5 * $0 }, [11, 22])
    }

    /// A one-finger scroll at 120 Hz, made up (on the ILITEK, a quarter of the display's height in
    /// 1.5 s, easing in and out, then resting before the lift) and recorded (strip take 11, the
    /// strip at about 120 Hz), posted with no app answering (today's events) and in VS Code; then
    /// what VS Code moves its content by for each. In VS Code the content ends within 5 px of the
    /// finger; with today's events it overshoots, by 43% and 34% along the scroll.
    ///
    /// | | finger (points) | today | in VS Code |
    /// |---|---|---|---|
    /// | made-up, down | 360 | 515 | 360 |
    /// | strip take 11, right; and up | 515.9; −21.6 | 690; −43 | 515; −25 |
    func testInVSCodeTheContentEndsUnderTheFinger() throws {
        let eased = (0...180).map { (step: Int) -> ContactFrame in
            let progress = Double(step) / 180
            let along = progress * progress * (3 - 2 * progress)
            return glassFrame(100 + Double(step) / 120, (0, 0.5, 0.3 + 0.25 * CGFloat(along)))
        } + (1...36).map { glassFrame(101.5 + Double($0) / 120, (0, 0.5, 0.55)) } + [glassFrame(101.81)]
        let cases: [(String, Driving, TouchscreenID, [ContactFrame], today: CGVector, matched: CGVector)] = [
            ("made-up scroll", ilitekScrolling, Desk.ilitekID, eased, CGVector(dx: 0, dy: 515), CGVector(dx: 0, dy: 360)),
            ("strip take 11", stripScrolling, Desk.stripID, try SurveyTakes.strip(take: 11),
             CGVector(dx: 690, dy: -43), CGVector(dx: 515, dy: -25)),
        ]
        for (label, driving, id, frames, expectedToday, expectedMatched) in cases {
            // The finger's movement, in points of the display, from where it landed to where it lifted.
            let touched = frames.compactMap { $0.contacts.first?.position }
            let start = try XCTUnwrap(touched.first), end = try XCTUnwrap(touched.last)
            let (a, b) = (driving.mapping.displayPoint(forGlass: start), driving.mapping.displayPoint(forGlass: end))
            let finger = CGVector(dx: (b.x - a.x) * driving.displayFrame.width, dy: (b.y - a.y) * driving.displayFrame.height)

            var content: [String: CGVector] = [:]
            for (run, app) in [("today", nil), ("VS Code", Self.vsCode)] as [(String, String?)] {
                let outputs = RecordingOutputs()
                outputs.appAnswer = { _ in app.map { Self.app($0) } }
                play(frames, into: pipeline(driving, outputs, id: id))
                let scrolls = outputs.events(.scroll)
                XCTAssertFalse(scrolls.contains { $0.momentumPhase != 0 }, "\(label): no momentum")
                XCTAssertGreaterThan(scrolls.count, 50, label)
                content[run] = CGVector(dx: Double(scrolls.map { Self.monacoPixels($0.scrollX) }.reduce(0, +)),
                                        dy: Double(scrolls.map { Self.monacoPixels($0.scrollY) }.reduce(0, +)))
            }
            let today = try XCTUnwrap(content["today"]), matched = try XCTUnwrap(content["VS Code"])
            let numbers = "\(label): finger \(finger), today \(today), VS Code \(matched)"
            XCTAssertLessThanOrEqual(abs(matched.dx - finger.dx), 5, numbers)
            XCTAssertLessThanOrEqual(abs(matched.dy - finger.dy), 5, numbers)
            let along = abs(finger.dx) > abs(finger.dy) ? (today.dx, finger.dx) : (today.dy, finger.dy)
            XCTAssertGreaterThan(abs(along.0), 1.25 * abs(along.1), numbers)
            XCTAssertEqual(today, expectedToday, numbers)
            XCTAssertEqual(matched, expectedMatched, numbers)
        }
    }
}
