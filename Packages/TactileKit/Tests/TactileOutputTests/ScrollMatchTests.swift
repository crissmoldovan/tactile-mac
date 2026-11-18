import CoreGraphics
import Foundation
import TactileGestures
import XCTest
@testable import TactileOutput

/// A seeded generator, so a "random" test fails the same way every time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func vector(_ dx: CGFloat, _ dy: CGFloat) -> CGVector {
    CGVector(dx: dx, dy: dy)
}

final class ScrollMatchTests: XCTestCase {

    /// Runs `deltas` through one quantiser as one scroll, the last its end (`ended`, or `cancelled`
    /// when it comes with no movement): what is posted for each, and what is carried after each.
    private func run(_ match: ScrollMatch, _ deltas: [CGVector]) -> (posted: [CGVector], carried: [CGVector]) {
        var quantiser = ScrollQuantiser(match)
        var posted: [CGVector] = []
        var carried: [CGVector] = []
        for (index, delta) in deltas.enumerated() {
            posted.append(quantiser.post(delta, isLast: index == deltas.count - 1))
            carried.append(quantiser.remainder)
        }
        return (posted, carried)
    }

    // The deltas below are multiples of 1.25 points wherever a value is compared exactly: 0.8 times
    // each is a whole number in floating point too.

    // MARK: - The quantiser, matched to Monaco

    func testItPostsFourFifthsInWholeStepsOfFourCarryingTheRest() {
        // 2.5 points a frame is 2 to post: nothing, then 4, nothing, 4.
        let (posted, carried) = run(.monaco, Array(repeating: vector(0, 2.5), count: 4) + [.zero])
        XCTAssertEqual(posted.map(\.dy), [0, 4, 0, 4, 0])
        XCTAssertEqual(carried.map(\.dy), [2, 0, 2, 0, 0])
        XCTAssertEqual(posted.map(\.dx), [0, 0, 0, 0, 0])
    }

    func testBothAxesAndBothSignsStepOnTheirOwn() {
        let deltas = [vector(-3.75, 6.25), vector(-3.75, 6.25), vector(10, -1.25), vector(-1.25, 0), .zero]
        let (posted, carried) = run(.monaco, deltas)
        // x: −3 → 0 (−3), −6 → −4 (−2), +6 → 4 (2), +1 → 0 (1).
        // y: 5 → 4 (1), 6 → 4 (2), 1 → 0 (1), 1 → 0 (1).
        XCTAssertEqual(posted, [vector(0, 4), vector(-4, 4), vector(4, 0), vector(0, 0), vector(0, 0)])
        XCTAssertEqual(carried, [vector(-3, 1), vector(-2, 2), vector(2, 1), vector(1, 1), .zero])
    }

    func testTheEndPostsWhatRemainsInWholeStepsAndCarriesNothing() {
        // An end that moves: 3 carried and 1.25 more (1) make one step of 4, posted with the end.
        let ended = run(.monaco, [vector(3.75, -3.75), vector(1.25, -1.25)])
        XCTAssertEqual(ended.posted, [.zero, vector(4, -4)])
        XCTAssertEqual(ended.carried.last, .zero)
        // A short one: less than a step remains, and it goes with the end.
        let short = run(.monaco, [vector(2.5, 0), vector(1.25, 0)])
        XCTAssertEqual(short.posted, [.zero, .zero])
        XCTAssertEqual(short.carried.last, .zero)
    }

    func testACancelledScrollEndsWithNothingAndCarriesNothing() {
        // Cut short mid-scroll: the engine ends it with no movement. 3 is carried; nothing is posted.
        let (posted, carried) = run(.monaco, [vector(0, 3.75), vector(0, 5), .zero])
        XCTAssertEqual(posted.map(\.dy), [0, 4, 0])
        XCTAssertEqual(carried.map(\.dy), [3, 3, 0])
    }

    /// Hundreds of scrolls of random movements, each a few hundred frames, with fractions, both axes
    /// and both signs, some cut short: every delta posted is a whole multiple of 4, never against
    /// that frame's movement, and each scroll's total is four fifths of the fingers' within 4 px.
    func testEveryScrollPostsWholeStepsWithTheFingersAndFourFifthsOfTheirDistance() {
        var generator = SeededGenerator(seed: 0x5C80_11ED)
        for scroll in 0..<300 {
            let frames = Int.random(in: 1...300, using: &generator)
            let bias = vector(.random(in: -8...8, using: &generator), .random(in: -8...8, using: &generator))
            var deltas = (0..<frames).map { _ in
                vector(bias.dx + .random(in: -6...6, using: &generator), bias.dy + .random(in: -6...6, using: &generator))
            }
            if Bool.random(using: &generator) { deltas.append(.zero) }  // ended or cancelled with no movement
            let (posted, _) = run(.monaco, deltas)
            for (delta, step) in zip(deltas, posted) {
                for (moved, sent) in [(delta.dx, step.dx), (delta.dy, step.dy)] {
                    XCTAssertEqual(sent.truncatingRemainder(dividingBy: 4), 0, "scroll \(scroll): \(sent)")
                    XCTAssertGreaterThanOrEqual(moved * sent, 0, "scroll \(scroll): \(sent) posted for \(moved)")
                }
            }
            let fingers = deltas.reduce(CGVector.zero) { vector($0.dx + $1.dx, $0.dy + $1.dy) }
            let sent = posted.reduce(CGVector.zero) { vector($0.dx + $1.dx, $0.dy + $1.dy) }
            XCTAssertLessThan(abs(sent.dx - 0.8 * fingers.dx), 4, "scroll \(scroll)")
            XCTAssertLessThan(abs(sent.dy - 0.8 * fingers.dy), 4, "scroll \(scroll)")
        }
    }

    // MARK: - The quantiser, as moved (today's)

    func testAsMovedSlowScrollsCarryFractionsUntilTheyMakeAPixel() {
        let (posted, carried) = run(.asMoved, Array(repeating: vector(0, 0.4), count: 4) + [vector(0, 0.5)])
        XCTAssertEqual(posted.map(\.dy), [0, 0, 1, 0, 1])
        XCTAssertEqual(carried[3].dy, 0.6, accuracy: 1e-9)
        XCTAssertEqual(carried[4].dy, 0)
    }

    func testAsMovedNegativeMovementRoundsTowardZero() {
        var quantiser = ScrollQuantiser(.asMoved)
        XCTAssertEqual(quantiser.post(vector(-2.7, 0), isLast: false).dx, -2)
        XCTAssertEqual(quantiser.remainder.dx, -0.7, accuracy: 1e-9)
    }

    // MARK: - Which apps

    func testTheEditorsBuiltOnMonacoAreMatchedAndNoOtherApp() {
        XCTAssertEqual(ScrollMatch.monacoEditors, [
            "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
            "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        ])
        for app in ScrollMatch.monacoEditors {
            XCTAssertEqual(ScrollMatch.forApp(app), .monaco, app)
        }
        for app in [nil, "", "com.apple.finder", "com.apple.Safari", "com.google.Chrome", "com.github.Electron",
                    "com.microsoft.VSCode.helper", "com.microsoft.vscode", "com.visualstudio.code.oss"] {
            XCTAssertEqual(ScrollMatch.forApp(app), .asMoved, app ?? "no answer")
        }
    }

    func testTheValuesAreFourFifthsInStepsOfFourAndAsMovedIsOneToOne() {
        XCTAssertEqual(ScrollMatch.monaco.scale, 0.8)
        XCTAssertEqual(ScrollMatch.monaco.step, 4)
        XCTAssertEqual(ScrollMatch.asMoved.scale, 1)
        XCTAssertEqual(ScrollMatch.asMoved.step, 1)
    }

    func testOnlyAMatchedScrollHasALogLine() {
        XCTAssertEqual(ScrollMatch.monaco.logLine(forApp: "com.microsoft.VSCode"),
                       "scroll in com.microsoft.VSCode: matched to VS Code's scrolling (x0.8, steps of 4 px)")
        XCTAssertNil(ScrollMatch.asMoved.logLine(forApp: "com.apple.finder"))
        XCTAssertNil(ScrollMatch.asMoved.logLine(forApp: nil))
    }
}

// MARK: - The sender

/// Today's scroll posting, as `EventSender` had it at d69e358, before scrolls were matched to
/// apps, copied line for line: the oracle the sender's own events are compared with.
@MainActor
private final class TodaysScrolls {
    private(set) var events: [CGEvent] = []
    private var scrollRemainder = CGVector.zero

    func scroll(by delta: CGVector, phase: GesturePhase) {
        postScroll(delta, scrollPhase: EventSender.scrollPhase(phase), momentumPhase: 0)
    }

    func momentum(by delta: CGVector, phase: GesturePhase) {
        postScroll(delta, scrollPhase: 0, momentumPhase: EventSender.momentumPhase(phase))
    }

    private static func wholePixels(of delta: CGVector, carrying remainder: CGVector) -> (CGVector, CGVector) {
        let total = CGVector(dx: delta.dx + remainder.dx, dy: delta.dy + remainder.dy)
        let whole = CGVector(dx: total.dx.rounded(.towardZero), dy: total.dy.rounded(.towardZero))
        return (whole, CGVector(dx: total.dx - whole.dx, dy: total.dy - whole.dy))
    }

    private func postScroll(_ delta: CGVector, scrollPhase: Int64, momentumPhase: Int64) {
        let (whole, remainder) = Self.wholePixels(of: delta, carrying: scrollRemainder)
        let isLast = scrollPhase == EventSender.scrollPhase(.ended) || momentumPhase == EventSender.momentumPhase(.ended)
        scrollRemainder = isLast ? .zero : remainder

        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(whole.dy), wheel2: Int32(whole.dx), wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: scrollPhase)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event.setIntegerValueField(.eventSourceUserData, value: EventSender.tag)
        events.append(event)
    }
}

@MainActor
final class EventSenderScrollMatchTests: XCTestCase {

    /// Every sender here hands its events to an array instead of posting them.
    private var events: [CGEvent] = []
    private lazy var sender = EventSender(deliver: { [unowned self] in events.append($0) })

    private var posted: [(phase: Int64, momentum: Int64, x: Int64, y: Int64)] {
        events.map {
            ($0.getIntegerValueField(.scrollWheelEventScrollPhase), $0.getIntegerValueField(.scrollWheelEventMomentumPhase),
             $0.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
             $0.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        }
    }

    /// An event's bytes, with what the system fills in when it is made (when, where the real
    /// pointer is, the keys held) the same for every event.
    private static func bytes(_ event: CGEvent) -> Data {
        event.timestamp = 0
        event.location = .zero
        event.flags = []
        return event.data.map { $0 as Data } ?? Data()
    }

    func testAMatchedScrollAndItsMomentumPostWholeStepsOfFour() {
        sender.scroll(by: vector(0, 3.75), phase: .began, match: .monaco)  // 3: nothing yet
        sender.scroll(by: vector(0, 5), phase: .changed)                   // 7: 4, 3 carried
        sender.scroll(by: vector(-6.25, 2.5), phase: .changed)             // x −5: −4; y 5: 4
        sender.scroll(by: .zero, phase: .ended)                            // 1 and −1 go with the end
        sender.momentum(by: .zero, phase: .began)
        sender.momentum(by: vector(0, 10), phase: .changed)                // 8
        sender.momentum(by: vector(0, 3.75), phase: .changed)              // 3: nothing yet
        sender.momentum(by: vector(0, 1.25), phase: .changed)              // 4
        sender.momentum(by: .zero, phase: .ended)

        XCTAssertEqual(posted.map { $0.phase }, [1, 2, 2, 4, 0, 0, 0, 0, 0])
        XCTAssertEqual(posted.map { $0.momentum }, [0, 0, 0, 0, 1, 2, 2, 2, 3])
        XCTAssertEqual(posted.map { $0.y }, [0, 4, 4, 0, 0, 8, 0, 4, 0])
        XCTAssertEqual(posted.map { $0.x }, [0, 0, -4, 0, 0, 0, 0, 0, 0])
    }

    func testTheEndPostsWhatRemainsInWholeStepsAsItsPhaseAlwaysHas() {
        sender.scroll(by: vector(0, -3.75), phase: .began, match: .monaco)  // −3 carried
        sender.scroll(by: vector(0, -1.25), phase: .ended)                  // −4, with the end
        sender.momentum(by: .zero, phase: .began)
        sender.momentum(by: vector(0, -3.75), phase: .changed)              // −3 carried
        sender.momentum(by: vector(0, -1.25), phase: .ended)                // −4, with the end

        XCTAssertEqual(posted.map { $0.phase }, [1, 4, 0, 0, 0])
        XCTAssertEqual(posted.map { $0.momentum }, [0, 0, 1, 2, 3])
        XCTAssertEqual(posted.map { $0.y }, [0, -4, 0, 0, -4])
    }

    func testEachScrollStartsAfreshWithTheMatchItBeganWith() {
        sender.scroll(by: vector(0, 3.75), phase: .began, match: .monaco)  // 3 carried
        sender.scroll(by: .zero, phase: .ended)                            // dropped with the end
        sender.scroll(by: vector(0, 3.75), phase: .began)                  // as moved: 3.75 → 3
        sender.scroll(by: vector(0, 0.5), phase: .changed)                 // 1.25 → 1
        sender.scroll(by: .zero, phase: .ended)
        sender.momentum(by: .zero, phase: .began)
        sender.momentum(by: vector(0, 2.5), phase: .changed)               // as its scroll was: 2
        sender.momentum(by: .zero, phase: .ended)
        sender.scroll(by: vector(0, 5), phase: .began, match: .monaco)     // matched again: 4
        sender.scroll(by: .zero, phase: .ended)

        XCTAssertEqual(posted.map { $0.y }, [0, 0, 3, 1, 0, 0, 2, 0, 4, 0])
    }

    /// The same scrolls and momentum, with fractions, both axes, both signs and ends cut short,
    /// through the sender as moved and through today's posting: the same events, byte for byte.
    func testAsMovedTheEventsAreTodaysByteForByte() {
        var generator = SeededGenerator(seed: 0x70DA_7500)
        let today = TodaysScrolls()
        func random() -> CGVector {
            vector(.random(in: -9...9, using: &generator), .random(in: -9...9, using: &generator))
        }
        for _ in 0..<40 {
            let first = random()
            sender.scroll(by: first, phase: .began)
            today.scroll(by: first, phase: .began)
            for _ in 0..<Int.random(in: 0...60, using: &generator) {
                let delta = random()
                sender.scroll(by: delta, phase: .changed)
                today.scroll(by: delta, phase: .changed)
            }
            let end = Bool.random(using: &generator) ? random() : .zero
            sender.scroll(by: end, phase: .ended)
            today.scroll(by: end, phase: .ended)
            guard Bool.random(using: &generator) else { continue }
            sender.momentum(by: .zero, phase: .began)
            today.momentum(by: .zero, phase: .began)
            for _ in 0..<Int.random(in: 0...60, using: &generator) {
                let delta = random()
                sender.momentum(by: delta, phase: .changed)
                today.momentum(by: delta, phase: .changed)
            }
            sender.momentum(by: .zero, phase: .ended)
            today.momentum(by: .zero, phase: .ended)
        }
        XCTAssertGreaterThan(events.count, 1000)
        XCTAssertEqual(events.count, today.events.count)
        XCTAssertEqual(events.map(Self.bytes), today.events.map(Self.bytes))
    }
}
