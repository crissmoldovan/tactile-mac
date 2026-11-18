// Delivery 5, Part T1: the gesture tester's narrator, driven through a real pipeline and its real
// `GestureEngine`, on the ILITEK (full touch) and on the strip (one finger), with the survey's takes
// where they show the gesture and touches built in millimetres where they don't. Nothing is posted.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture
private typealias Kind = RecognisedGesture.Kind

@MainActor
final class GestureNarratorTests: XCTestCase {
    /// The ILITEK on "HDMI": 2560 × 1440 points, full touch.
    private let ilitek = Desk.driving(on: Desk.hdmi, diagonal: 23.8)
    /// The strip on "12.3FHD": 1600 × 600 points, one finger.
    private let strip = Desk.driving(on: Desk.strip, diagonal: 12.3, options: Desk.noGestures)

    private func observed(_ driving: Driving, id: TouchscreenID = Desk.ilitekID, holdsSwipes: Bool = true,
                          _ change: (inout Driving) -> Void = { _ in }) -> ObservedPipeline {
        ObservedPipeline(id, with(driving, change), holdsSwipes: holdsSwipes)
    }

    /// Both touchscreens, each with what it is called in messages.
    private var both: [(name: String, id: TouchscreenID, driving: Driving)] {
        [("ILITEK", Desk.ilitekID, ilitek), ("strip", Desk.stripID, strip)]
    }

    // MARK: - Tap, double tap, triple tap

    func testTapsByTheirClickCountOnBoth() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id)
            var glass = Glass(screen.driving.surfaceSizeMM)
            for tap in 0..<3 {
                glass.land([(tap, 50, 40)], after: 0.15)
                glass.rest(0.05)
                glass.lift()
            }
            tested.play(glass.frames)
            XCTAssertEqual(tested.observer.kinds, [.tap, .doubleTap, .tripleTap], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, ["a click", "a double-click", "a triple-click"], screen.name)
            XCTAssertEqual(tested.observer.fingers, [1, 1, 1], screen.name)
            XCTAssertEqual(tested.outputs.events(.down).map(\.clickState), [1, 2, 3], "\(screen.name): the taps clicked")
        }
    }

    func testTheSurveysTapsAndDoubleTaps() throws {
        let tap = observed(ilitek)
        tap.play(try SurveyTakes.ilitek(take: 9))
        XCTAssertEqual(tap.observer.kinds, [.tap], tap.observer.described)

        for (name, id, driving, frames) in [("ILITEK", Desk.ilitekID, ilitek, try SurveyTakes.ilitek(take: 10)),
                                            ("strip", Desk.stripID, strip, try SurveyTakes.strip(take: 10))] {
            let tested = observed(driving, id: id)
            tested.play(frames)
            XCTAssertEqual(tested.observer.kinds, [.tap, .doubleTap], "\(name): \(tested.observer.described)")
        }
    }

    func testAFourthTapInARowSaysSo() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        for tap in 0..<4 {
            glass.land([(tap, 50, 40)], after: 0.15)
            glass.rest(0.05)
            glass.lift()
        }
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.tap, .doubleTap, .tripleTap, .tripleTap])
        XCTAssertEqual(tested.observer.summaries.last, "4 clicks in a row")
    }

    // MARK: - Drag, and hold then drag

    func testADragOnBoth() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysDrag }
            var glass = Glass(screen.driving.surfaceSizeMM)
            glass.land([(0, screen.driving.surfaceSizeMM.width * 0.3, screen.driving.surfaceSizeMM.height * 0.5)])
            glass.move(screen.driving.surfaceSizeMM.width * 0.1, 0)
            glass.lift()
            tested.play(glass.frames)
            let points = Int(screen.driving.displayFrame.width * 0.1)
            XCTAssertEqual(tested.observer.kinds, [.drag], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, ["\(points) pt right"], screen.name)
            XCTAssertEqual(tested.outputs.count(.down), 1, screen.name)
            XCTAssertEqual(tested.outputs.count(.up), 1, screen.name)
        }
    }

    func testADragIsOneEntryUpdatedInPlace() {
        let tested = observed(ilitek) { $0.oneFinger = .alwaysDrag }
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 100, 100)])
        glass.move(ilitek.surfaceSizeMM.width * 0.05, ilitek.surfaceSizeMM.height * 0.05)
        let halfWay = glass.frames.count
        glass.move(ilitek.surfaceSizeMM.width * 0.05, ilitek.surfaceSizeMM.height * 0.05)
        glass.lift()
        tested.play(Array(glass.frames.prefix(halfWay)), settle: 0)
        XCTAssertEqual(tested.observer.feed.count, 1)
        XCTAssertEqual(tested.observer.summaries, ["128 pt right, 72 pt down"], "half way: 5% of 2560 and of 1440")
        let id = tested.observer.feed.first?.id
        tested.play(Array(glass.frames.dropFirst(halfWay)))
        XCTAssertEqual(tested.observer.feed.map(\.id), [id].compactMap { $0 }, "the same entry")
        XCTAssertEqual(tested.observer.summaries, ["256 pt right, 144 pt down"])
        XCTAssertEqual(tested.observer.finished.map(\.kind), [.drag], "finished once, at the release")
    }

    /// The survey's drags: ILITEK take 11 rested 0.585 s, past the engine's hold time, and was
    /// forced to drag before the ring (hold, then drag); take 12 rested 1.56 s, past the ring (hold,
    /// then drag). The strip's take 11 moved at 0.316 s (a drag); its take 12 and take 14 (which
    /// rested 0.98 s) hold, then drag.
    func testTheSurveysDragsAndHoldsThenDrags() throws {
        let takes: [(String, TouchscreenID, Driving, [ContactFrame], Kind)] = [
            ("ILITEK 11", Desk.ilitekID, ilitek, try SurveyTakes.ilitek(take: 11), .holdThenDrag),
            ("ILITEK 12", Desk.ilitekID, ilitek, try SurveyTakes.ilitek(take: 12), .holdThenDrag),
            ("strip 11", Desk.stripID, strip, try SurveyTakes.strip(take: 11), .drag),
            ("strip 12", Desk.stripID, strip, try SurveyTakes.strip(take: 12), .holdThenDrag),
            ("strip 14", Desk.stripID, strip, try SurveyTakes.strip(take: 14), .holdThenDrag),
        ]
        for (name, id, driving, frames, kind) in takes {
            let tested = observed(driving, id: id)
            tested.play(frames)
            XCTAssertEqual(tested.observer.kinds, [kind], "\(name): \(tested.observer.described)")
            XCTAssertTrue(tested.observer.summaries.first?.contains(" pt ") == true, name)
        }
    }

    /// Part S's one-finger default on the strip: with Always scroll, a finger that rests past the
    /// ring and then moves drags (hold, then drag), and one that moves at once scrolls.
    func testHoldThenDragWithAlwaysScrollOnBoth() {
        for screen in both {
            let held = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysScroll }
            var glass = Glass(screen.driving.surfaceSizeMM)
            glass.land([(0, 60, 40)])
            glass.rest(0.7)
            glass.move(30, 0)
            glass.lift()
            held.play(glass.frames)
            XCTAssertEqual(held.observer.kinds, [.holdThenDrag], "\(screen.name): \(held.observer.described)")
            XCTAssertEqual(held.outputs.count(.down), 1, "\(screen.name): it pressed")

            let moved = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysScroll }
            var atOnce = Glass(screen.driving.surfaceSizeMM)
            atOnce.land([(0, 60, 40)])
            atOnce.move(30, 0)
            atOnce.rest(0.2)
            atOnce.lift()
            moved.play(atOnce.frames)
            XCTAssertEqual(moved.observer.kinds, [.scroll], "\(screen.name): \(moved.observer.described)")
        }
    }

    /// The ruling of fix round 1: a finger that rests at least the engine's hold time and then moves
    /// is forced to drag, whatever the one-finger setting: hold, then drag, before the ring too. One
    /// that moves sooner drags or scrolls as the setting says. On both kinds of touchscreen, under
    /// Automatic (over something to drag, and over something to scroll), Always drag and Always scroll.
    func testHoldThenDragIsAnyRestOfTheHoldTimeUnderEveryOneFingerSetting() {
        let hold = GestureConstants.standard.holdTime
        let longPress = GestureConstants.standard.longPressDuration
        let settings: [(String, OneFingerMode, OneFingerIntent, Kind)] = [
            ("Automatic over a drag", .automatic, .drag, .drag), ("Automatic over a scroll", .automatic, .scroll, .scroll),
            ("Always drag", .alwaysDrag, .drag, .drag), ("Always scroll", .alwaysScroll, .drag, .scroll),
        ]
        for screen in both {
            for (name, mode, intent, quick) in settings {
                for (rest, expected) in [(hold, Kind.holdThenDrag), ((hold + longPress) / 2, .holdThenDrag),
                                         (hold - 0.15, quick), (0, quick)] {
                    let outputs = RecordingOutputs()
                    outputs.intentAnswer = intent
                    let tested = ObservedPipeline(screen.id, with(screen.driving) { $0.oneFinger = mode }, outputs: outputs)
                    var glass = Glass(screen.driving.surfaceSizeMM)
                    glass.land([(0, 60, 40)])
                    glass.rest(rest)
                    glass.move(40, 0, steps: 4)  // 10 mm a frame: past the slop in the first
                    glass.rest(0.2)
                    glass.lift()
                    tested.play(glass.frames)
                    let label = "\(screen.name), \(name), rested \(rest) s"
                    XCTAssertEqual(tested.observer.kinds, [expected], "\(label): \(tested.observer.described)")
                    if expected == .holdThenDrag { XCTAssertEqual(outputs.count(.down), 1, "\(label): the engine pressed") }
                }
            }
        }
    }

    // MARK: - Scroll and flick

    func testAOneFingerScrollOnBothWithItsDistanceInPoints() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysScroll }
            let size = screen.driving.surfaceSizeMM
            var glass = Glass(size)
            glass.land([(0, size.width * 0.5, size.height * 0.2)])
            glass.move(0, size.height * 0.1)
            glass.rest(0.3)  // still before lifting: no flick
            glass.lift()
            tested.play(glass.frames)
            let points = Int((screen.driving.displayFrame.height * 0.1).rounded())
            XCTAssertEqual(tested.observer.kinds, [.scroll], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, ["\(points) pt down"], screen.name)
            XCTAssertEqual(tested.observer.fingers, [1], screen.name)
            // The events carried the same distance, in whole points (the sender carries the fraction).
            let posted = tested.outputs.events(.scroll).map(\.scrollY).reduce(0, +)
            XCTAssertLessThanOrEqual(abs(abs(Int(posted)) - points), 1, screen.name)
        }
    }

    func testAScrollIsOneEntryUpdatedInPlace() {
        let tested = observed(ilitek) { $0.oneFinger = .alwaysScroll }
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 200)])
        glass.move(0, -ilitek.surfaceSizeMM.height * 0.05)
        let first = glass.frames.count
        glass.move(0, -ilitek.surfaceSizeMM.height * 0.05)
        glass.rest(0.3)
        glass.lift()
        tested.play(Array(glass.frames.prefix(first)), settle: 0)
        XCTAssertEqual(tested.observer.summaries, ["72 pt up"])
        tested.play(Array(glass.frames.dropFirst(first)))
        XCTAssertEqual(tested.observer.summaries, ["144 pt up"], "the same entry, further")
        XCTAssertEqual(tested.observer.feed.count, 1)
    }

    func testATwoFingerScrollFromTheSurvey() throws {
        let tested = observed(ilitek)
        tested.play(try SurveyTakes.ilitek(take: 14))
        XCTAssertEqual(tested.observer.kinds, [.scroll], "no flick: the fingers were still before they lifted. \(tested.observer.described)")
        XCTAssertEqual(tested.observer.fingers, [2])
        XCTAssertTrue(tested.observer.summaries.first?.hasSuffix(" pt up") == true, tested.observer.described)
    }

    func testAFlickAfterAScrollOnBoth() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysScroll }
            let size = screen.driving.surfaceSizeMM
            var glass = Glass(size)
            glass.land([(0, size.width * 0.5, size.height * 0.8)])
            glass.move(0, -size.height * 0.5)  // fast: half the glass in 0.1 s
            glass.lift()
            tested.play(glass.frames, settle: 3)
            XCTAssertEqual(tested.observer.kinds, [.scroll, .flick], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.fingers, [1, 1], screen.name)
            let flick = tested.observer.summaries.last ?? ""
            XCTAssertTrue(flick.hasPrefix("coasted ") && flick.hasSuffix(" pt up"), "\(screen.name): \(flick)")
            XCTAssertEqual(tested.observer.finished.map(\.kind), [.scroll, .flick], screen.name)
        }
    }

    func testATwoFingerFlickHasTwoFingers() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 200), (1, 240, 200)])
        glass.move(0, -120)
        glass.lift()
        tested.play(glass.frames, settle: 3)
        XCTAssertEqual(tested.observer.kinds, [.scroll, .flick], tested.observer.described)
        XCTAssertEqual(tested.observer.fingers, [2, 2])
    }

    func testAFlickStoppedByATouch() {
        let tested = observed(ilitek) { $0.oneFinger = .alwaysScroll }
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 250)])
        glass.move(0, -150)
        glass.lift()
        glass.wait(0.1)
        glass.land([(1, 200, 100)], after: 0)
        glass.rest(0.05)
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.scroll, .flick], "the stopping touch doesn't click. \(tested.observer.described)")
        XCTAssertTrue(tested.observer.summaries.last?.hasSuffix(", stopped by a touch") == true, tested.observer.described)
    }

    // MARK: - Pinch and rotate

    func testZoomWords() {
        XCTAssertEqual(GestureNarrator.zoom(1.4), "zoom in, 1.4\u{00D7}")
        XCTAssertEqual(GestureNarrator.zoom(0.7), "zoom out, 0.7\u{00D7}")
        XCTAssertEqual(GestureNarrator.zoom(1.1), "zoom in, 1.1\u{00D7}")
        XCTAssertEqual(GestureNarrator.zoom(0.9), "zoom out, 0.9\u{00D7}")
        // Near 1×: two decimals, so a small zoom doesn't read as none at all.
        XCTAssertEqual(GestureNarrator.zoom(1.04), "zoom in, 1.04\u{00D7}")
        XCTAssertEqual(GestureNarrator.zoom(1.0951), "zoom in, 1.10\u{00D7}")
        XCTAssertEqual(GestureNarrator.zoom(0.95), "zoom out, 0.95\u{00D7}")
        // Back where it began.
        XCTAssertEqual(GestureNarrator.zoom(1.0), "zoom unchanged")
        XCTAssertEqual(GestureNarrator.zoom(1.004), "zoom unchanged")
        XCTAssertEqual(GestureNarrator.zoom(0.996), "zoom unchanged")
    }

    func testAPinchThatEndsNearItsStart() {
        for (end, words) in [(42.0, "zoom in, 1.05\u{00D7}"), (40.0, "zoom unchanged"), (36.8, "zoom out, 0.92\u{00D7}")] {
            let tested = observed(ilitek)
            var glass = Glass(ilitek.surfaceSizeMM)
            glass.land([(0, 240, 150), (1, 280, 150)])  // 40 mm apart
            glass.trace(steps: 10) { id, step in (260 + (id == 0 ? -1 : 1) * (20 + 1.5 * Double(step)), 150) }  // to 70
            glass.trace(steps: 10) { id, step in
                let half = 35 - (35 - end / 2) * Double(step) / 10  // back to `end`
                return (260 + (id == 0 ? -half : half), 150)
            }
            glass.lift()
            tested.play(glass.frames)
            XCTAssertEqual(tested.observer.kinds, [.pinch], tested.observer.described)
            XCTAssertEqual(tested.observer.summaries, [words], "ended \(end) mm apart")
        }
    }

    func testPinchingInAndOut() {
        let out = observed(ilitek)
        var spread = Glass(ilitek.surfaceSizeMM)
        spread.land([(0, 240, 150), (1, 280, 150)])
        spread.trace(steps: 20) { id, step in
            let half = 20 + 40 * Double(step) / 20  // 40 mm apart, then 120: three times
            return (260 + (id == 0 ? -half : half), 150)
        }
        spread.lift()
        out.play(spread.frames)
        XCTAssertEqual(out.observer.kinds, [.pinch], out.observer.described)
        XCTAssertEqual(out.observer.summaries, ["zoom in, 3.0\u{00D7}"])
        XCTAssertEqual(out.observer.fingers, [2])

        let into = observed(ilitek)
        var close = Glass(ilitek.surfaceSizeMM)
        close.land([(0, 200, 150), (1, 320, 150)])
        close.trace(steps: 20) { id, step in
            let half = 60 - 30 * Double(step) / 20  // 120 mm apart, then 60: half
            return (260 + (id == 0 ? -half : half), 150)
        }
        close.lift()
        into.play(close.frames)
        XCTAssertEqual(into.observer.kinds, [.pinch], into.observer.described)
        XCTAssertEqual(into.observer.summaries, ["zoom out, 0.5\u{00D7}"])
    }

    func testThePinchFromTheSurvey() throws {
        let tested = observed(ilitek)
        tested.play(try SurveyTakes.ilitek(take: 15))
        XCTAssertEqual(tested.observer.kinds, [.pinch], tested.observer.described)
        XCTAssertTrue(tested.observer.summaries.first?.hasPrefix("zoom in, ") == true)
    }

    /// Two fingers 60 mm apart going round their middle by `degrees` (positive anticlockwise, as the
    /// person sees the display), in 20 steps.
    private func turn(_ degrees: Double) -> [ContactFrame] {
        var glass = Glass(ilitek.surfaceSizeMM)
        let centre = (x: 260.0, y: 150.0), radius = 30.0
        func place(_ id: Int, _ angle: Double) -> (Double, Double) {
            let a = (angle + (id == 0 ? 180 : 0)) * .pi / 180
            return (centre.x + radius * cos(a), centre.y - radius * sin(a))
        }
        glass.land([(0, place(0, 0).0, place(0, 0).1), (1, place(1, 0).0, place(1, 0).1)])
        glass.trace(steps: 20) { id, step in place(id, degrees * Double(step) / 20) }
        glass.lift()
        return glass.frames
    }

    func testRotatingBothWays() {
        for (degrees, words) in [(60.0, "60\u{00B0} anticlockwise"), (-45, "45\u{00B0} clockwise")] {
            let tested = observed(ilitek)
            tested.play(turn(degrees))
            XCTAssertEqual(tested.observer.kinds, [.rotate], "\(degrees): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, [words])
            XCTAssertEqual(tested.observer.fingers, [2])
            XCTAssertEqual(tested.outputs.events(.gesture).filter(\.isRotation).isEmpty, false, "it rotated for real")
        }
    }

    // MARK: - Right-click

    func testALongPressRightClicksOnBoth() throws {
        for (name, id, driving, frames) in [("ILITEK", Desk.ilitekID, ilitek, try SurveyTakes.ilitek(take: 13)),
                                            ("strip", Desk.stripID, strip, try SurveyTakes.strip(take: 13))] {
            let tested = observed(driving, id: id)
            tested.play(frames)
            XCTAssertEqual(tested.observer.kinds, [.rightClick], "\(name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, ["from a long press"], name)
            XCTAssertEqual(tested.observer.fingers, [1], name)
            XCTAssertEqual(tested.outputs.count(.rightDown), 1, name)
        }
    }

    func testATwoFingerTapRightClicks() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 150), (1, 240, 150)])
        glass.rest(0.1)
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.rightClick], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["from a two-finger tap"])
        XCTAssertEqual(tested.observer.fingers, [2])
    }

    // MARK: - Swipes

    /// `fingers` fingers 25 mm apart moving `dx`, `dy` mm together, then lifting.
    private func swipe(_ fingers: Int, _ dx: Double, _ dy: Double, surface: CGSize) -> [ContactFrame] {
        var glass = Glass(surface)
        glass.land((0..<fingers).map { ($0, 180 + 25 * Double($0), 150) })
        glass.move(dx, dy, steps: 20)
        glass.lift()
        return glass.frames
    }

    func testSwipesAreHeldByDefaultAndSaySo() {
        let cases: [(Int, Double, Double, String)] = [
            (3, -60, 0, "left: next Desktop"), (3, 60, 0, "right: previous Desktop"),
            (4, 0, -60, "up: Mission Control"), (4, 0, 60, "down: App Expos\u{00E9}"),
        ]
        for (fingers, dx, dy, does) in cases {
            let tested = observed(ilitek)
            tested.play(swipe(fingers, dx, dy, surface: ilitek.surfaceSizeMM))
            XCTAssertEqual(tested.observer.kinds, [.swipe], "\(does): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries, ["\(does); not done: the tester holds swipes"])
            XCTAssertEqual(tested.observer.fingers, [fingers])
            XCTAssertEqual(tested.outputs.shortcuts, 0, "\(does): no shortcut")
            XCTAssertEqual(tested.outputs.record.dockEvents, [])
        }
    }

    func testSwipesLetThroughAreDone() {
        let tested = observed(ilitek, holdsSwipes: false)
        tested.play(swipe(3, -60, 0, surface: ilitek.surfaceSizeMM))
        XCTAssertEqual(tested.observer.summaries, ["left: next Desktop"])
        XCTAssertEqual(tested.outputs.shortcuts, 1, "the shortcut was posted")
    }

    func testFollowedSwipesHeldAndLetThrough() {
        let following = with(ilitek) { $0.swipesFollowFingers = true }
        let surface = ilitek.surfaceSizeMM

        let held = observed(following)
        held.play(swipe(3, -60, 0, surface: surface))
        XCTAssertEqual(held.observer.kinds, [.followedSwipe], held.observer.described)
        XCTAssertEqual(held.observer.summaries, ["left: next Desktop; not done: the tester holds swipes"])
        XCTAssertEqual(held.observer.fingers, [3])
        XCTAssertEqual(held.outputs.record.dockEvents, [], "no Dock swipe")
        XCTAssertEqual(held.outputs.shortcuts, 0, "no shortcut")

        let through = observed(following, holdsSwipes: false)
        through.play(swipe(3, -60, 0, surface: surface))
        XCTAssertEqual(through.observer.summaries, ["left: next Desktop"])
        XCTAssertEqual(through.outputs.dockPhases.filter { $0 != .changed }, [.began, .ended], "followed by the Dock")
        XCTAssertEqual(through.outputs.shortcuts, 0)

        // Slid back: 40 mm left, then 25 back, lifting while moving back.
        let back = observed(following, holdsSwipes: false)
        var glass = Glass(surface)
        glass.land((0..<3).map { ($0, 180 + 25 * Double($0), 150) })
        glass.move(-40, 0, steps: 15)
        glass.move(25, 0, steps: 10)
        glass.lift()
        back.play(glass.frames)
        XCTAssertEqual(back.observer.kinds, [.followedSwipe], back.observer.described)
        XCTAssertEqual(back.observer.summaries, ["left, slid back"])
        XCTAssertEqual(back.outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase), [.cancelled])
    }

    func testAFollowedSwipeIsOneEntryWhileItGoes() {
        let tested = observed(with(ilitek) { $0.swipesFollowFingers = true })
        let frames = swipe(3, -60, 0, surface: ilitek.surfaceSizeMM)
        tested.play(Array(frames.dropLast()), settle: 0)
        XCTAssertEqual(tested.observer.summaries, ["left, following the fingers"])
        tested.play(Array(frames.suffix(1)))
        XCTAssertEqual(tested.observer.summaries, ["left: next Desktop; not done: the tester holds swipes"])
        XCTAssertEqual(tested.observer.feed.count, 1)
    }

    // MARK: - What can't happen on one finger

    /// On the strip a second finger is refused, so a pinch, a two-finger scroll or tap, a rotation
    /// and a swipe never happen: the feed says the second finger was ignored.
    func testMultiFingerGesturesCannotHappenOnOneFinger() {
        let attempts: [(String, [ContactFrame])] = [
            ("pinch", {
                var glass = Glass(strip.surfaceSizeMM)
                glass.land([(0, 100, 50)])
                glass.land([(1, 140, 50)])
                glass.move(20, 0, only: [1])
                glass.lift()
                return glass.frames
            }()),
            ("swipe", swipe(3, -60, 0, surface: strip.surfaceSizeMM)),
            ("two-finger tap", {
                var glass = Glass(strip.surfaceSizeMM)
                glass.land([(0, 100, 50), (1, 140, 50)])
                glass.rest(0.1)
                glass.lift()
                return glass.frames
            }()),
        ]
        for (name, frames) in attempts {
            let tested = observed(strip, id: Desk.stripID)
            tested.play(frames)
            let kinds = Set(tested.observer.kinds)
            XCTAssertTrue(kinds.isDisjoint(with: [.pinch, .rotate, .swipe, .followedSwipe, .rightClick]),
                          "\(name): \(tested.observer.described)")
            XCTAssertTrue(tested.observer.feed.contains { $0.kind == .ignored && $0.summary == "a second finger on a one-finger touchscreen" },
                          "\(name): \(tested.observer.described)")
        }
    }

    // MARK: - Ignored

    /// `contact` reported in six frames 10 ms apart from `time`, then lifted.
    private func resting(_ contact: Contact, at time: TimeInterval = 100) -> [ContactFrame] {
        (0..<6).map { ContactFrame(time: time + Double($0) * 0.01, contacts: [contact]) }
            + [ContactFrame(time: time + 0.06, contacts: [])]
    }

    func testAPalmIsIgnoredOnceUntilItLifts() {
        let tested = observed(ilitek)
        tested.play(resting(Contact(id: 0, position: CGPoint(x: 0.4, y: 0.5), isConfident: false)))
        XCTAssertEqual(tested.observer.kinds, [.ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["a palm"])
        XCTAssertEqual(tested.observer.fingers, [1])
        XCTAssertEqual(tested.outputs.count(.down), 0, "it didn't click")
    }

    func testAWideContactIsAPalm() {
        let tested = observed(ilitek)
        // A share of the glass: about 42 × 30 mm.
        tested.play(resting(Contact(id: 0, position: CGPoint(x: 0.4, y: 0.5), size: CGSize(width: 0.08, height: 0.1))))
        XCTAssertEqual(tested.observer.summaries, ["a palm"], tested.observer.described)
    }

    /// A finger that counted and then widened: the touch is cut short, and the palm said once.
    func testAFingerThatBecomesAPalmCutsItsTouchShort() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 150)])
        for _ in 0..<5 { glass.report { $0.size = CGSize(width: 0.08, height: 0.1) } }
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.cancelled, .ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["the touch cut short: a palm or a hand landed", "a palm"])
        XCTAssertEqual(tested.outputs.count(.down), 0)
    }

    func testAWholeHand() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land((0..<5).map { ($0, 150 + 20 * Double($0), 150) })
        glass.rest(0.1)
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["a whole hand"])
        XCTAssertEqual(tested.observer.fingers, [5])
    }

    func testATouchAtTheEdgeOnBoth() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id) { $0.rejection = RejectionRules(palm: true, edgeMarginMM: 5) }
            var glass = Glass(screen.driving.surfaceSizeMM)
            glass.land([(0, 2, 30)])
            glass.rest(0.05)
            glass.lift()
            glass.land([(1, 30, 30)], after: 0.5)
            glass.rest(0.05)
            glass.lift()
            tested.play(glass.frames)
            XCTAssertEqual(tested.observer.kinds, [.ignored, .tap], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries.first, "a touch at the edge", screen.name)
        }
    }

    func testASecondFingerOnTheStrip() {
        let tested = observed(strip, id: Desk.stripID) { $0.oneFinger = .alwaysDrag }
        var glass = Glass(strip.surfaceSizeMM)
        glass.land([(0, 60, 40)])
        glass.land([(1, 120, 40)])
        glass.move(30, 0, only: [0])
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.ignored, .drag], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries.first, "a second finger on a one-finger touchscreen")
        XCTAssertEqual(tested.observer.fingers, [2, 1], "ignored: the two down then; the drag: one")
        XCTAssertEqual(tested.observer.narrator.fingersOnGlass, 0)
    }

    func testATouchWhileTheOtherTouchscreenHasThePointer() {
        let outputs = RecordingOutputs()
        let tested = ObservedPipeline(Desk.ilitekID, ilitek, outputs: outputs)
        let other = TouchPipeline(id: Desk.stripID, driving: strip, outputs: outputs, cancelOther: { _, _ in })
        other.handle(glassFrame(100, (0, 0.5, 0.5)))
        tested.pipeline.handle(glassFrame(100.02, (0, 0.3, 0.3)))
        tested.pipeline.handle(glassFrame(100.04, (0, 0.3, 0.3)))
        tested.pipeline.handle(glassFrame(100.06))
        XCTAssertEqual(tested.observer.kinds, [.ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["the other touchscreen has the pointer"])
    }

    func testATouchFromBefore() {
        let tested = ObservedPipeline(Desk.ilitekID, ilitek, fingersAlreadyDown: true)
        tested.play([glassFrame(100, (0, 0.5, 0.5)), glassFrame(100.05, (0, 0.5, 0.5)), glassFrame(100.1)])
        XCTAssertEqual(tested.observer.kinds, [.ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["a touch from before: lift and touch again"])
    }

    // MARK: - Cancelled

    func testAPalmCutsADragShort() {
        let tested = observed(ilitek) { $0.oneFinger = .alwaysDrag }
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 150)])
        glass.move(40, 0)
        glass.report { $0.isConfident = false }
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.drag, .cancelled, .ignored], tested.observer.described)
        XCTAssertTrue(tested.observer.summaries[0].hasSuffix(", cut short"), tested.observer.described)
        XCTAssertEqual(tested.observer.summaries[1], "the drag cut short: a palm or a hand landed")
        XCTAssertEqual(tested.observer.summaries[2], "a palm")
        XCTAssertEqual(tested.observer.fingers, [1, 1, 1])
        XCTAssertEqual(tested.outputs.count(.down), tested.outputs.count(.up))
    }

    func testALostLiftOnBoth() {
        for screen in both {
            let tested = observed(screen.driving, id: screen.id) { $0.oneFinger = .alwaysDrag }
            var glass = Glass(screen.driving.surfaceSizeMM)
            glass.land([(0, 60, 40)])
            glass.move(30, 0)
            tested.play(glass.frames, settle: TouchPipeline.silenceLimit + 0.2)
            XCTAssertEqual(tested.observer.kinds, [.drag, .cancelled], "\(screen.name): \(tested.observer.described)")
            XCTAssertEqual(tested.observer.summaries.last, "the drag cut short: the touchscreen went quiet", screen.name)
            XCTAssertEqual(tested.observer.fingers, [1, 1], "\(screen.name): the finger down when it went quiet")
            XCTAssertEqual(tested.observer.narrator.fingersOnGlass, 0, "\(screen.name): the glass is taken as clear")
        }
    }

    func testTakenOverDuringAFlick() {
        let outputs = RecordingOutputs()
        let tested = ObservedPipeline(Desk.ilitekID, with(ilitek) { $0.oneFinger = .alwaysScroll }, outputs: outputs)
        let other = TouchPipeline(id: Desk.stripID, driving: strip, outputs: outputs, cancelOther: { id, time in
            if id == Desk.ilitekID { tested.pipeline.cancel(at: time, reason: .takenOver) }
        })
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 250)])
        glass.move(0, -150)
        glass.lift()
        tested.play(glass.frames, settle: 0.05)
        XCTAssertEqual(tested.observer.kinds, [.scroll, .flick], "coasting. \(tested.observer.described)")
        other.handle(glassFrame(glass.time + 0.1, (0, 0.5, 0.5)))
        XCTAssertEqual(tested.observer.kinds, [.scroll, .flick, .cancelled], tested.observer.described)
        XCTAssertTrue(tested.observer.summaries[1].hasSuffix(", cut short"))
        XCTAssertEqual(tested.observer.summaries[2], "the flick cut short: the other touchscreen took the pointer")
        XCTAssertEqual(tested.observer.fingers, [1, 1, 0], "no finger down when the flick was cut")
    }

    func testTakenOverWithNothingUnderWaySaysNothing() {
        let outputs = RecordingOutputs()
        let tested = ObservedPipeline(Desk.ilitekID, ilitek, outputs: outputs)
        let other = TouchPipeline(id: Desk.stripID, driving: strip, outputs: outputs, cancelOther: { id, time in
            if id == Desk.ilitekID { tested.pipeline.cancel(at: time, reason: .takenOver) }
        })
        tested.play([glassFrame(100, (0, 0.5, 0.5)), glassFrame(100.05)], settle: 0.1)  // a tap, then the double-tap wait
        other.handle(glassFrame(100.2, (0, 0.5, 0.5)))
        XCTAssertEqual(tested.observer.kinds, [.tap], tested.observer.described)
        XCTAssertTrue(tested.observer.observations.contains(.cutShort(.takenOver)), "the session was cut")
    }

    func testStoppedWithAFingerResting() {
        let tested = observed(ilitek)
        tested.play([glassFrame(100, (0, 0.5, 0.5)), glassFrame(100.1, (0, 0.5, 0.5))], settle: 0)
        tested.pipeline.cancel(at: 100.2, reason: .stoppedDriving)
        XCTAssertEqual(tested.observer.kinds, [.cancelled], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries, ["the touch cut short: Tactile stopped following this touch"])
        XCTAssertEqual(tested.observer.fingers, [1])

        let ringed = observed(ilitek)
        ringed.play([glassFrame(100, (0, 0.5, 0.5)), glassFrame(100.7, (0, 0.5, 0.5))], settle: 0)
        ringed.pipeline.cancel(at: 100.8, reason: .stoppedDriving)
        XCTAssertEqual(ringed.observer.summaries, ["the long press cut short: Tactile stopped following this touch"])
    }

    func testAPinchCutShortByAPalm() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 240, 150), (1, 280, 150)])
        glass.trace(steps: 10) { id, step in (260 + (id == 0 ? -1 : 1) * (20 + 3 * Double(step)), 150) }
        glass.report { if $0.id == 1 { $0.isConfident = false } }
        glass.lift()
        tested.play(glass.frames)
        XCTAssertEqual(tested.observer.kinds, [.pinch, .cancelled, .ignored], tested.observer.described)
        XCTAssertEqual(tested.observer.summaries[1], "the pinch cut short: a palm or a hand landed")
        XCTAssertEqual(tested.observer.fingers, [2, 2, 2], "both fingers down: the pinch's, the cut's, the palm's")
    }

    // MARK: - Fingers on the glass

    func testFingersOnTheGlassFollowEveryFrame() {
        let tested = observed(ilitek)
        var counts: [Int] = []
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 150)])
        glass.land([(1, 240, 150)])
        glass.land([(2, 280, 150)])
        glass.lift([2])
        glass.lift([0])
        glass.lift()
        for frame in glass.frames {
            tested.pipeline.handle(frame)
            counts.append(tested.observer.narrator.fingersOnGlass)
        }
        XCTAssertEqual(counts, [1, 2, 3, 2, 1, 0])
    }

    // MARK: - The feed itself

    func testTheFeedKeepsTheNewestFortyAndCountsEveryKindSeen() {
        let tested = observed(ilitek)
        var glass = Glass(ilitek.surfaceSizeMM)
        for tap in 0..<45 {
            glass.land([(0, 50 + Double(tap % 2) * 100, 40)], after: 0.5)  // far apart: each a lone tap
            glass.rest(0.05)
            glass.lift()
        }
        glass.land([(0, 200, 150), (1, 240, 150)], after: 0.5)
        glass.rest(0.1)
        glass.lift()
        tested.play(glass.frames)
        let recent = tested.observer.narrator.recent
        XCTAssertEqual(recent.count, GestureNarrator.mostRecent)
        XCTAssertEqual(recent.first?.kind, .rightClick, "newest first")
        XCTAssertEqual(recent.map(\.id), recent.map(\.id).sorted(by: >), "IDs rise")
        XCTAssertEqual(tested.observer.narrator.seen, [GestureSeenCount(id: .tap, count: 45),
                                                       GestureSeenCount(id: .rightClick, count: 1)])
    }

    func testClearingEmptiesTheFeedAndTheCountsAndIDsGoOnRising() {
        let tested = observed(ilitek)
        tested.play([glassFrame(100, (0, 0.5, 0.5)), glassFrame(100.05)])
        let first = tested.observer.feed.first?.id ?? 0
        tested.observer.clear()
        XCTAssertEqual(tested.observer.narrator.recent, [])
        XCTAssertEqual(tested.observer.narrator.seen, [])
        tested.play([glassFrame(102, (0, 0.5, 0.5)), glassFrame(102.05)])
        XCTAssertEqual(tested.observer.kinds, [.tap])
        XCTAssertGreaterThan(tested.observer.feed.first?.id ?? 0, first)
        XCTAssertEqual(tested.observer.narrator.seen, [GestureSeenCount(id: .tap, count: 1)])
    }

    func testClearedMidScrollTheScrollGoesOnInANewEntry() {
        let tested = observed(ilitek) { $0.oneFinger = .alwaysScroll }
        var glass = Glass(ilitek.surfaceSizeMM)
        glass.land([(0, 200, 200)])
        glass.move(0, 40)
        let half = glass.frames.count
        glass.move(0, 40)
        glass.rest(0.3)
        glass.lift()
        tested.play(Array(glass.frames.prefix(half)), settle: 0)
        tested.observer.clear()
        tested.play(Array(glass.frames.dropFirst(half)))
        XCTAssertEqual(tested.observer.kinds, [.scroll], tested.observer.described)
    }

    /// Every kind the contract names comes out of a real engine on the ILITEK, and every one-finger
    /// kind on the strip too.
    func testEveryKindHappens() throws {
        var seenOnILITEK = Set<Kind>(), seenOnStrip = Set<Kind>()
        func note(_ tested: ObservedPipeline, into seen: inout Set<Kind>) { seen.formUnion(tested.observer.kinds) }

        for (id, driving) in [(Desk.ilitekID, ilitek), (Desk.stripID, strip)] {
            var seen = Set<Kind>()
            let size = driving.surfaceSizeMM
            let taps = observed(driving, id: id)
            var glass = Glass(size)
            for tap in 0..<3 { glass.land([(tap, 50, 40)], after: 0.15); glass.rest(0.05); glass.lift() }
            taps.play(glass.frames)
            note(taps, into: &seen)

            let drags = observed(driving, id: id) { $0.oneFinger = .alwaysDrag }
            var drag = Glass(size)
            drag.land([(0, 60, 40)]); drag.move(30, 0); drag.lift()
            drag.land([(1, 60, 40)], after: 0.5); drag.rest(0.7); drag.move(30, 0); drag.lift()
            drags.play(drag.frames)
            note(drags, into: &seen)

            let scrolls = observed(driving, id: id) { $0.oneFinger = .alwaysScroll }
            var scroll = Glass(size)
            scroll.land([(0, size.width / 2, size.height * 0.8)]); scroll.move(0, -size.height / 2); scroll.lift()
            scrolls.play(scroll.frames, settle: 3)
            note(scrolls, into: &seen)

            let presses = observed(driving, id: id)
            presses.play(id == Desk.ilitekID ? try SurveyTakes.ilitek(take: 13) : try SurveyTakes.strip(take: 13))
            note(presses, into: &seen)

            let edges = observed(driving, id: id) { $0.rejection = RejectionRules(palm: true, edgeMarginMM: 5) }
            edges.play([glassFrame(100, (0, 0.001, 0.5)), glassFrame(100.05)])
            note(edges, into: &seen)

            let lost = observed(driving, id: id)
            lost.play([glassFrame(100, (0, 0.5, 0.5))], settle: 2)
            note(lost, into: &seen)

            if id == Desk.ilitekID { seenOnILITEK = seen } else { seenOnStrip = seen }
        }
        // The multi-finger kinds, on the ILITEK.
        let pinch = observed(ilitek)
        pinch.play(try SurveyTakes.ilitek(take: 15))
        note(pinch, into: &seenOnILITEK)
        let rotate = observed(ilitek)
        rotate.play(turn(60))
        note(rotate, into: &seenOnILITEK)
        let swipe = observed(ilitek)
        swipe.play(self.swipe(3, -60, 0, surface: ilitek.surfaceSizeMM))
        note(swipe, into: &seenOnILITEK)
        let followed = observed(with(ilitek) { $0.swipesFollowFingers = true })
        followed.play(self.swipe(3, -60, 0, surface: ilitek.surfaceSizeMM))
        note(followed, into: &seenOnILITEK)

        XCTAssertEqual(seenOnILITEK, Set(Kind.allCases))
        XCTAssertEqual(seenOnStrip, Set(Kind.allCases).subtracting([.pinch, .rotate, .swipe, .followedSwipe]))
    }

    /// What the window's checklist reads: each kind's `fingers`.
    func testEachKindsFingers() throws {
        var entries: [RecognisedGesture] = []
        func run(_ driving: Driving, id: TouchscreenID = Desk.ilitekID, _ frames: [ContactFrame], settle: TimeInterval = 1,
                 _ change: (inout Driving) -> Void = { _ in }) {
            let tested = observed(driving, id: id, change)
            tested.play(frames, settle: settle)
            entries += tested.observer.feed
        }
        for (id, driving) in [(Desk.ilitekID, ilitek), (Desk.stripID, strip)] {
            let size = driving.surfaceSizeMM
            var taps = Glass(size)
            for tap in 0..<3 { taps.land([(tap, 50, 40)], after: 0.15); taps.rest(0.05); taps.lift() }
            run(driving, id: id, taps.frames)
            var drags = Glass(size)
            drags.land([(0, 60, 40)]); drags.move(30, 0); drags.lift()
            drags.land([(1, 60, 40)], after: 0.5); drags.rest(0.7); drags.move(30, 0); drags.lift()
            run(driving, id: id, drags.frames) { $0.oneFinger = .alwaysDrag }
            var flick = Glass(size)
            flick.land([(0, size.width / 2, size.height * 0.8)]); flick.move(0, -size.height / 2); flick.lift()
            run(driving, id: id, flick.frames, settle: 3) { $0.oneFinger = .alwaysScroll }
            run(driving, id: id, id == Desk.ilitekID ? try SurveyTakes.ilitek(take: 13) : try SurveyTakes.strip(take: 13))
        }
        var twoFlick = Glass(ilitek.surfaceSizeMM)
        twoFlick.land([(0, 200, 250), (1, 240, 250)]); twoFlick.move(0, -150); twoFlick.lift()
        run(ilitek, twoFlick.frames, settle: 3)
        var twoTap = Glass(ilitek.surfaceSizeMM)
        twoTap.land([(0, 200, 150), (1, 240, 150)]); twoTap.rest(0.1); twoTap.lift()
        run(ilitek, twoTap.frames)
        run(ilitek, try SurveyTakes.ilitek(take: 15))
        run(ilitek, turn(60))
        for count in 3...5 {
            // Five fingers with palm rejection off: a swipe still says four.
            run(ilitek, swipe(count, -60, 0, surface: ilitek.surfaceSizeMM)) { $0.rejection = .none }
            run(ilitek, swipe(count, 60, 0, surface: ilitek.surfaceSizeMM)) { $0.rejection = .none; $0.swipesFollowFingers = true }
        }

        func fingers(_ kind: Kind) -> Set<Int> { Set(entries.filter { $0.kind == kind }.map(\.fingers)) }
        for kind in [Kind.tap, .doubleTap, .tripleTap, .drag, .holdThenDrag] {
            XCTAssertEqual(fingers(kind), [1], "\(kind)")
        }
        XCTAssertEqual(fingers(.scroll), [1, 2])
        XCTAssertEqual(fingers(.flick), [1, 2])
        // A flick has the fingers of the scroll it follows.
        for (index, entry) in entries.enumerated() where entry.kind == .flick {
            XCTAssertEqual(entries[index - 1].kind, .scroll)
            XCTAssertEqual(entry.fingers, entries[index - 1].fingers)
        }
        XCTAssertEqual(Set(entries.filter { $0.kind == .rightClick && $0.summary == "from a long press" }.map(\.fingers)), [1])
        XCTAssertEqual(Set(entries.filter { $0.kind == .rightClick && $0.summary == "from a two-finger tap" }.map(\.fingers)), [2])
        XCTAssertEqual(fingers(.pinch), [2])
        XCTAssertEqual(fingers(.rotate), [2])
        XCTAssertEqual(fingers(.swipe), [3, 4])
        XCTAssertEqual(fingers(.followedSwipe), [3, 4])
    }
}

/// The reasons the pipeline gives for what its contact filter refused, against the filter itself.
final class WhyRefusedTests: XCTestCase {
    private let surface = CGSize(width: 300, height: 200)

    /// Runs `frames` through a filter with `rules` and `limit`, and gives the reason for each contact
    /// refused in the last frame.
    private func reasons(_ frames: [[Finger]], rules: RejectionRules, limit: Int? = nil) -> [Int: IgnoredBecause] {
        var filter = ContactFilter(fingerLimit: limit, rules: rules)
        var last: [Finger] = []
        for (index, fingers) in frames.enumerated() {
            _ = filter.live(fingers, at: Double(index) * 0.01, surfaceSize: surface)
            last = fingers
        }
        var reasons: [Int: IgnoredBecause] = [:]
        for finger in last where filter.refused.contains(finger.id) {
            reasons[finger.id] = TouchPipeline.whyRefused(finger, rules: filter.rules, fingerLimit: filter.fingerLimit,
                                                          contactsOnGlass: last.count, surface: surface)
        }
        return reasons
    }

    private func at(_ id: Int, _ x: Double, _ y: Double, size: CGSize? = nil, confident: Bool? = nil) -> Finger {
        Finger(id: id, location: CGPoint(x: x / 300, y: y / 200), size: size, isConfident: confident)
    }

    func testEachRuleGivesItsReason() {
        let palmOn = RejectionRules(palm: true, edgeMarginMM: 5)
        XCTAssertEqual(reasons([[at(0, 100, 100, confident: false)]], rules: palmOn), [0: .palm])
        XCTAssertEqual(reasons([[at(0, 100, 100, size: CGSize(width: 30, height: 10))]], rules: palmOn), [0: .palm])
        XCTAssertEqual(reasons([(0..<5).map { at($0, 50 + 30 * Double($0), 100) }], rules: palmOn),
                       Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, IgnoredBecause.hand) }))
        XCTAssertEqual(reasons([[at(0, 2, 100)]], rules: palmOn), [0: .edge])
        XCTAssertEqual(reasons([[at(0, 100, 100)], [at(0, 100, 100), at(1, 150, 100)]], rules: palmOn, limit: 1),
                       [1: .beyondOneFinger])
        // At the edge on a one-finger touchscreen: the edge decides first, as in the filter.
        XCTAssertEqual(reasons([[at(0, 100, 100)], [at(0, 100, 100), at(1, 298, 100)]], rules: palmOn, limit: 1),
                       [1: .edge])
        // A palm that widens after landing is still a palm.
        XCTAssertEqual(reasons([[at(0, 100, 100)], [at(0, 100, 100, size: CGSize(width: 40, height: 40))]], rules: palmOn),
                       [0: .palm])
    }
}
