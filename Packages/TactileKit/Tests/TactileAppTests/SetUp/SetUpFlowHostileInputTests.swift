// The set-up flow fed what a device, a clock or a caller can get wrong: frames that repeat, go
// back in time or aren't timed at all; contacts off the glass or not numbers; ten fingers; displays
// coming and going; calls in any order. None of it may trap, store a guess, or move the flow on.

import CoreGraphics
import Foundation
import TactileApp
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = SetUpDesk
private typealias Driver = FlowDriver

final class SetUpFlowHostileInputTests: XCTestCase {

    func testRepeatedFramesMakeTheSameSetUp() throws {
        let orientation = Orientation(quarterTurns: 3, isFlipped: true)
        let taps = Desk.cornerTaps(on: Desk.hdmi, orientation: orientation, rect: Desk.offCentre)
        var once = try XCTUnwrap(SetUpFlow(Desk.calibrating(), at: Driver.t0))
        var twice = once
        for (i, tap) in taps.enumerated() {
            let t = Driver.time(1 + Double(i))
            let frames = [
                ContactFrame(time: t, contacts: [Contact(id: 3, position: tap)]),
                ContactFrame(time: t + 0.05, contacts: [Contact(id: 3, position: tap)]),
                ContactFrame(time: t + 0.1, contacts: []),
            ]
            for frame in frames {
                _ = once.handle(frame)
                _ = twice.handle(frame)
                _ = twice.handle(frame)  // the same frame again, same time and all
            }
        }
        XCTAssertEqual(once.snapshot.step, .check(display: 3))
        XCTAssertEqual(twice.snapshot, once.snapshot)
        _ = once.tick(at: Driver.time(6))
        _ = twice.tick(at: Driver.time(6))
        let outcome = once.done()
        guard case .finished(.some) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(twice.done(), outcome)
    }

    func testTouchesThatAreNoTapNeverMakeOne() throws {
        let p = Desk.cornerTaps(on: Desk.hdmi)[0]
        var flow = try XCTUnwrap(SetUpFlow(Desk.calibrating(), at: Driver.t0))
        var generator = Seeded(state: 7)
        var t = Driver.time(1)
        let bad: [CGFloat] = [.nan, .infinity, -.infinity, .signalingNaN]
        for _ in 0..<500 {
            // One touch: a few frames, then the glass clears.
            var frames: [[Contact]] = []
            let length = Int.random(in: 1...6, using: &generator)
            switch Int.random(in: 0..<3, using: &generator) {
            case 0:  // a hand: two to ten fingers
                let count = Int.random(in: 2...10, using: &generator)
                let hand = (0..<count).map { Contact(id: $0, position: CGPoint(x: Double($0) / 10, y: p.y)) }
                frames = Array(repeating: hand, count: length)
            case 1:  // one finger, somewhere along it not where a number is
                let spoilt = Int.random(in: 0..<length, using: &generator)
                frames = (0..<length).map { i in
                    let broken = CGPoint(x: bad.randomElement(using: &generator)!, y: p.y)
                    return [Contact(id: 1, position: i == spoilt ? broken : p)]
                }
            default:  // one finger sliding more than 3% of the glass
                let far = CGFloat.random(in: 0.031...2, using: &generator) * (Bool.random(using: &generator) ? 1 : -1)
                frames = [[Contact(id: 1, position: p)]] + (1..<max(2, length)).map { i in
                    [Contact(id: 1, position: CGPoint(x: p.x, y: p.y + far * CGFloat(i) / CGFloat(max(1, length - 1))))]
                }
            }
            for contacts in frames + [[]] {
                t += 0.05
                _ = flow.handle(ContactFrame(time: t, contacts: contacts))
            }
            t += 0.5
            guard case .corners(_, _, let index, _) = flow.snapshot.step else {
                return XCTFail("\(flow.snapshot.step)")
            }
            XCTAssertEqual(index, 0)
        }
    }

    /// Thousands of random calls, from a fixed seed, against what must always hold: nothing traps;
    /// the snapshot is always one the interface can draw and survives JSON; only `done` ever gives
    /// an outcome, and every number in it is sound; once ended, a flow stays as it ended.
    func testAnythingInAnyOrder() throws {
        let turned = Desk.hdmiTurned
        let lists: [[DisplayFacts]] = [
            Desk.all, [], [Desk.builtIn], [Desk.hdmi], Desk.all.filter { $0.displayID != 3 },
            Desk.all.map { $0.displayID == 3 ? turned : $0 }, Desk.all + Desk.all,
            Desk.all.map { $0.displayID == 4 ? changed(Desk.strip) { $0.mirrors = 3 } : $0 },
        ]
        let numbers: [CGFloat] = [0, 0.12, 0.5, 0.88, 1, -0.01, 1.01, 7, -1e300, 1e300, .nan, .infinity]
        let sizes: [Double?] = [nil, 23.8, 3, 200, 0, -5, 1000, .nan, .infinity]
        let starts = [
            Desk.start(), Desk.start(candidates: [Desk.hdmi]), Desk.start(glass: nil, diagonal: .nan),
            Desk.start(candidates: [Desk.strip], glass: CGSize(width: CGFloat.nan, height: 0), diagonal: 1e9),
            Desk.start(.calibrate, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi), diagonal: 23.8),
            Desk.start(.test, candidates: [Desk.hdmi], current: Desk.pairing(Desk.hdmi, .asFitted, Desk.offCentre)),
        ]
        var generator = Seeded(state: 2026)
        var outcomes = 0
        for round in 0..<300 {
            let start = starts[round % starts.count]
            var flow = try XCTUnwrap(SetUpFlow(start, at: Driver.t0))
            var clock = Driver.t0
            var ended: (event: SetUpFlow.Event, flow: SetUpFlow)?
            for _ in 0..<300 {
                clock += .random(in: -0.3...1.5, using: &generator)
                let time: TimeInterval = Int.random(in: 0..<50, using: &generator) == 0 ? .nan : clock
                let before = flow
                let event: SetUpFlow.Event
                var calledDone = false
                // Where the target is shown: on an unturned display fitted straight, a target's
                // place on the glass is the target itself. Without taps there, no round would fit.
                var target: CGPoint?
                if case .corners(_, let shown, _, _) = flow.snapshot.step { target = shown }
                switch Int.random(in: 0..<100, using: &generator) {
                case 0..<20 where target != nil:
                    // A clean tap on the target: it lands, and lifts.
                    _ = flow.handle(ContactFrame(time: time, contacts: [Contact(id: 1, position: target!)]))
                    event = flow.handle(ContactFrame(time: time + 0.05, contacts: []))
                case 0..<55:
                    let count = [0, 0, 1, 1, 1, 2, 10].randomElement(using: &generator)!
                    let contacts = (0..<count).map { _ in
                        let position: CGPoint
                        switch Int.random(in: 0..<3, using: &generator) {
                        case 0:
                            position = target ?? CGPoint(x: 0.5, y: 0.5)
                        case 1:
                            position = CGPoint(
                                x: .random(in: 0...1, using: &generator), y: .random(in: 0...1, using: &generator))
                        default:
                            position = CGPoint(
                                x: numbers.randomElement(using: &generator)!,
                                y: numbers.randomElement(using: &generator)!)
                        }
                        return Contact(id: Int.random(in: 0...2, using: &generator), position: position)
                    }
                    event = flow.handle(ContactFrame(time: time, contacts: contacts))
                case 55..<80:
                    event = flow.tick(at: time)
                case 80..<86:
                    event = flow.confirmSize(inches: sizes.randomElement(using: &generator)!)
                case 86..<90:
                    event = flow.redo()
                case 90..<95:
                    event = flow.displaysChanged(lists.randomElement(using: &generator)!, at: time)
                case 95..<99:
                    calledDone = true
                    event = flow.done()
                default:
                    event = flow.cancel()
                }

                if let ended {
                    XCTAssertEqual(event, ended.event)
                    XCTAssertEqual(flow, ended.flow)
                    continue
                }
                if case .finished(let outcome) = event {
                    ended = (event, flow)
                    XCTAssertNil(flow.checkMapping)
                    if let outcome {
                        outcomes += 1
                        XCTAssertTrue(calledDone, "an outcome from anything but Done")
                        let shown = before.checkMapping?.display.displayID ?? 0
                        XCTAssertEqual(before.snapshot.step, .check(display: shown), "Done from the check step")
                        assertSound(outcome, from: start)
                    }
                    continue
                }
                assertDrawable(flow)
            }
        }
        XCTAssertGreaterThan(outcomes, 0, "the random calls reached Done in the check step at least once")
    }

    // MARK: - Helpers

    /// The snapshot is one the interface can draw, and survives JSON (which refuses a number that
    /// isn't finite).
    private func assertDrawable(_ flow: SetUpFlow, file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = flow.snapshot
        do {
            let decoded = try JSONDecoder().decode(SetUpSnapshot.self, from: JSONEncoder().encode(snapshot))
            XCTAssertEqual(decoded, snapshot, file: file, line: line)
        } catch {
            XCTFail("\(snapshot): \(error)", file: file, line: line)
        }
        switch snapshot.step {
        case .corners(_, let target, let index, _):
            XCTAssertTrue((0..<4).contains(index), file: file, line: line)
            XCTAssertEqual(target, Calibration.targets[max(0, min(3, index))], file: file, line: line)
            XCTAssertNil(flow.checkMapping, file: file, line: line)
        case .size(_, let display, let glass, let current):
            for inches in [display, glass, current].compactMap({ $0 }) {
                XCTAssertTrue(SurfaceSize.plausibleDiagonals.contains(inches), "\(inches)", file: file, line: line)
            }
            XCTAssertNil(flow.checkMapping, file: file, line: line)
        case .check(let display):
            XCTAssertEqual(flow.checkMapping?.display.displayID, display, file: file, line: line)
        }
    }

    /// Every number in `outcome` is sound, and it names the display the flow could have been on.
    private func assertSound(
        _ outcome: SetUpFlow.Outcome, from start: SetUpFlow.Start, file: StaticString = #filePath, line: UInt = #line
    ) {
        let rect = outcome.alignment.pictureRect
        let numbers = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        XCTAssertTrue(numbers.allSatisfy(\.isFinite), "\(rect)", file: file, line: line)
        let believable = (0.5...1.5).contains(rect.size.width) && (0.5...1.5).contains(rect.size.height)
        XCTAssertTrue(believable, "\(rect)", file: file, line: line)
        switch start.purpose {
        case .full:
            let named = start.candidates.contains { DisplayIdentity($0) == outcome.display && !$0.isBuiltIn }
            XCTAssertTrue(named, "\(outcome.display)", file: file, line: line)
            if let inches = outcome.diagonalInches {
                XCTAssertTrue(SurfaceSize.plausibleDiagonals.contains(inches), "\(inches)", file: file, line: line)
            }
        case .calibrate:
            XCTAssertEqual(outcome.display, start.current?.display, file: file, line: line)
            XCTAssertEqual(outcome.diagonalInches, start.currentDiagonal, file: file, line: line)
        case .test:
            XCTFail("a test stores nothing", file: file, line: line)
        }
    }
}
