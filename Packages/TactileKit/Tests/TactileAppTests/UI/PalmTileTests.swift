import AppKit
import Observation
import SwiftUI
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The gesture tester's palm tile: what it says this touchscreen can recognise, held to the contact
/// filter's own rule; how its line follows the fingers on the glass and what the feed says was
/// ignored; and that the line, not the tile, is drawn again, and only when a finger lands or lifts or
/// something is ignored.
@MainActor
final class PalmTileTests: XCTestCase {

    private let ilitek = UIFixtures.ilitek

    private func entry(_ id: Int, _ summary: String, fingers: Int = 5) -> RecognisedGesture {
        RecognisedGesture(id: id, kind: .ignored, fingers: fingers, summary: summary, at: 0)
    }

    private func feedback(
        _ kind: PalmTileKind, palmIsOn: Bool = true, edge: Double = 0, fingers: Int = 0,
        _ reading: PalmTileReading = PalmTileReading()
    ) -> PalmTileFeedback {
        PalmTileFeedback(kind, palmIsOn: palmIsOn, edgeMarginMM: edge, fingersDown: fingers, reading: reading)
    }

    // MARK: - The contact filter's rule

    /// What the tile says is the filter's own rule: five contacts landing within a fifth of a second
    /// of the first are a whole hand, and every one of them is refused; four are not a hand; five
    /// landing over longer are not either.
    func testTheTileSaysWhatTheContactFilterDoes() {
        XCTAssertEqual(PalmTileKind.handFingers, 5)
        XCTAssertEqual(GestureConstants.standard.handContactCount, PalmTileKind.handFingers)

        func counted(_ landings: [TimeInterval]) -> Int {
            var filter = ContactFilter(rules: RejectionRules(palm: true))
            var down: [Finger] = []
            var last: [Finger] = []
            for (index, time) in landings.enumerated() {
                down.append(Finger(id: index + 1, location: CGPoint(x: 0.2 + 0.1 * Double(index), y: 0.5)))
                last = filter.live(down, at: time, surfaceSize: CGSize(width: 476, height: 268))
            }
            return last.count
        }
        XCTAssertEqual(counted([0, 0.02, 0.04, 0.06, 0.08]), 0, "a whole hand, all at once: every finger ignored")
        XCTAssertEqual(counted([0, 0.02, 0.04, 0.06]), 4, "four fingers: not a hand")
        XCTAssertEqual(counted([0, 0.1, 0.2, 0.3, 0.4]), 5, "five, not all at once: not a hand")
        XCTAssertEqual(Wording.practicePalmRule(.wholeHand, edgeMarginMM: 0), "5 fingers or more landing at once are ignored")
    }

    /// The feed's words read back to the reason the narrator worded them from.
    func testTheFeedsWordsReadBackToTheirReason() {
        for reason in IgnoredBecause.allCases {
            XCTAssertEqual(PalmTileReading.Ignored(entry(1, GestureNarrator.ignored(reason))), .reason(reason), "\(reason)")
        }
        XCTAssertEqual(PalmTileReading.Ignored(entry(1, "something new")), .words("something new"))
        let recent = [
            RecognisedGesture(id: 3, kind: .tap, fingers: 1, summary: "on Tap Me", at: 0),
            entry(2, GestureNarrator.ignored(.hand)), entry(1, GestureNarrator.ignored(.edge)),
        ]
        XCTAssertEqual(PalmTileReading.newestIgnored(in: recent)?.id, 2)
        XCTAssertNil(PalmTileReading.newestIgnored(in: [recent[0]]))
    }

    // MARK: - Following a touch

    /// A hand laid down: the fingers climb, the hand is ignored, it lifts; the result stays until
    /// the next touch, and goes when the feed is cleared. The feed's entries are read only when the
    /// count of ignored ones rises.
    func testTheReadingFollowsATouch() {
        typealias Inputs = PalmTileReading.Inputs
        var reads = 0
        var newest: RecognisedGesture? = nil
        let read = { () -> RecognisedGesture? in
            reads += 1
            return newest
        }
        var reading = PalmTileReading()
        var inputs = Inputs(fingers: 0, ignored: 0)
        func move(fingers: Int, ignored: Int? = nil) {
            let next = Inputs(fingers: fingers, ignored: ignored ?? inputs.ignored)
            reading.follow(from: inputs, to: next, newest: read)
            inputs = next
        }

        move(fingers: 1)
        move(fingers: 3)
        XCTAssertEqual(reading.mostFingers, 3)
        XCTAssertNil(reading.ignored)
        newest = entry(9, GestureNarrator.ignored(.hand))
        move(fingers: 5, ignored: 1)
        XCTAssertEqual(reading.ignored, .reason(.hand))
        XCTAssertEqual(reads, 1, "the entries are read once, when the count rose")
        move(fingers: 2)
        move(fingers: 0)
        XCTAssertEqual(reading.ignored, .reason(.hand), "the result stays after the hand lifts")
        XCTAssertEqual(reading.mostFingers, 5)

        move(fingers: 1)
        XCTAssertNil(reading.ignored, "a new touch: nothing ignored of it yet")
        XCTAssertEqual(reading.mostFingers, 1)
        move(fingers: 0)

        // All five landing in one frame: the touch begins and the hand is ignored in the same change.
        newest = entry(10, GestureNarrator.ignored(.hand))
        move(fingers: 5, ignored: 2)
        XCTAssertEqual(reading.ignored, .reason(.hand))
        XCTAssertEqual(reading.mostFingers, 5)

        move(fingers: 5, ignored: 0)
        XCTAssertNil(reading.ignored, "the feed cleared")
        XCTAssertEqual(reads, 2)

        // As the tile appears, mid-touch, with something ignored before.
        let appearing = PalmTileReading(Inputs(fingers: 2, ignored: 3), newest: entry(4, GestureNarrator.ignored(.edge)))
        XCTAssertEqual(appearing.mostFingers, 2)
        XCTAssertEqual(appearing.ignored, .reason(.edge))
        XCTAssertNil(PalmTileReading(Inputs(fingers: 0, ignored: 0), newest: entry(4, "a palm")).ignored,
                     "nothing counted: nothing shown")
    }

    // MARK: - What the line says

    /// A multi-touch touchscreen without contact sizes: the rule; the fingers, short of a hand; a
    /// whole hand ignored; five that didn't land at once; palm rejection off.
    func testTheLineForAWholeHand() {
        typealias Inputs = PalmTileReading.Inputs
        XCTAssertEqual(feedback(.wholeHand), .init(text: "5 fingers or more landing at once are ignored", tone: .rule))
        XCTAssertEqual(feedback(.wholeHand, fingers: 1).tone, .rule, "one finger: a tap anywhere says nothing here")
        XCTAssertEqual(feedback(.wholeHand, fingers: 3, PalmTileReading(Inputs(fingers: 3, ignored: 0))),
                       .init(text: "3 fingers: not a whole hand yet", tone: .notYet))
        let hand = PalmTileReading(Inputs(fingers: 5, ignored: 1), newest: entry(1, GestureNarrator.ignored(.hand)))
        XCTAssertEqual(feedback(.wholeHand, fingers: 5, hand), .init(text: "Whole hand: ignored ✓", tone: .ignored))
        XCTAssertEqual(feedback(.wholeHand, fingers: 0, hand).text, "Whole hand: ignored ✓", "after it lifts")
        let slow = PalmTileReading(Inputs(fingers: 5, ignored: 0))
        XCTAssertEqual(feedback(.wholeHand, fingers: 5, slow),
                       .init(text: "5 fingers, not all at once: lift, then lay the hand down in one go", tone: .notYet))
        XCTAssertEqual(feedback(.wholeHand, fingers: 0, slow).tone, .notYet, "said again after it lifts")
        XCTAssertEqual(feedback(.wholeHand, palmIsOn: false, fingers: 5, hand),
                       .init(text: "Palm rejection is off: switch it on in the list", tone: .off))
        let edge = PalmTileReading(Inputs(fingers: 1, ignored: 1), newest: entry(1, GestureNarrator.ignored(.edge), fingers: 1))
        XCTAssertEqual(feedback(.wholeHand, edge: 4, fingers: 1, edge).text, "A touch at the edge: ignored ✓")
    }

    /// A touchscreen that reports the size of a touch: a palm; the fingers say nothing.
    func testTheLineForAPalm() {
        XCTAssertEqual(feedback(.palm), .init(text: "A resting palm, or a whole hand, is ignored", tone: .rule))
        XCTAssertEqual(feedback(.palm, fingers: 3).tone, .rule)
        let palm = PalmTileReading(.init(fingers: 1, ignored: 1), newest: entry(1, GestureNarrator.ignored(.palm), fingers: 1))
        XCTAssertEqual(feedback(.palm, fingers: 1, palm), .init(text: "A palm: ignored ✓", tone: .ignored))
        XCTAssertEqual(feedback(.palm, palmIsOn: false).tone, .off)
    }

    /// The one-finger strip: the edge, in millimetres from its margin; off without one, whatever the
    /// palm switch says.
    func testTheLineForTheEdge() {
        XCTAssertEqual(feedback(.edge, edge: 4), .init(text: "Touches that start within 4 mm of an edge are ignored", tone: .rule))
        let edge = PalmTileReading(.init(fingers: 1, ignored: 1), newest: entry(1, GestureNarrator.ignored(.edge), fingers: 1))
        XCTAssertEqual(feedback(.edge, palmIsOn: false, edge: 4, fingers: 1, edge),
                       .init(text: "A touch at the edge: ignored ✓", tone: .ignored))
        let second = PalmTileReading(
            .init(fingers: 2, ignored: 1), newest: entry(1, GestureNarrator.ignored(.beyondOneFinger), fingers: 2))
        XCTAssertEqual(feedback(.edge, edge: 4, second).text, "A second finger: ignored ✓")
        XCTAssertEqual(feedback(.edge, edge: 0, fingers: 1, edge),
                       .init(text: "Edge rejection is off: its margin is under Accidental touches in Settings", tone: .off))
    }

    // MARK: - What is drawn again

    /// While a gesture goes on, the palm tile and its drawing are never drawn again; its line is
    /// drawn again only when the fingers on the glass change (here every fifth update), never with
    /// the feed's entries. A whole hand ignored draws the line again, and not the tile.
    func testTheLineFollowsTheFingersAndNotTheFeed() async throws {
        _ = NSApplication.shared
        let preview = PreviewModel(.desk)
        preview.perform(.openGestureTester(ilitek))
        var snapshot = preview.snapshot
        let model = FeedModel(snapshot)
        let display = CGSize(width: 2560, height: 1440)
        let visible = CGRect(x: 0, y: 0, width: display.width, height: display.height - 25)
        let content = NSWindow.contentRect(
            forFrameRect: GestureTesterWindowFrame.frame(in: visible), styleMask: GestureTesterNSWindow.style
        ).size
        let store = GestureTesterStore(
            touchscreen: ilitek, layout: GestureTesterLayout(displaySize: display), snapshot: snapshot, perform: { _ in })
        let follower = GestureTesterFollower(model: model, tell: { _ in }, show: { store.update($0) })
        follower.start()
        let lines = PalmFeedbackBodies()
        let host = hosted(store, size: content, counting: lines)
        func publish(_ next: AppSnapshot) async {
            model.snapshot = next
            for _ in 0..<10 { await Task.yield() }
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(lines.count, 0, "the line is in the window")
        store.bodies.reset()
        lines.reset()

        var fingerChanges = 0
        for index in 1...100 {
            var tester = try XCTUnwrap(snapshot.gestureTester)
            tester.recent[0].summary = "\(index * 7) pt down"
            if index % 5 == 0 {
                tester.fingersDown = tester.fingersDown == 2 ? 3 : 2
                fingerChanges += 1
            }
            snapshot.gestureTester = tester
            await publish(snapshot)
        }
        print("PalmTileTests: 100 feed-only updates, \(fingerChanges) of the fingers: line \(lines.count), tile \(store.bodies[.palm])")
        XCTAssertEqual(store.bodies[.palm], 0, "the tile and its drawing: never")
        XCTAssertEqual(store.bodies[.practice], 0)
        XCTAssertGreaterThanOrEqual(lines.count, fingerChanges, "the line follows the fingers")
        XCTAssertLessThanOrEqual(lines.count, fingerChanges + 1, "and nothing else: \(lines.count)")

        // A whole hand lands and is ignored.
        store.bodies.reset()
        lines.reset()
        var tester = try XCTUnwrap(snapshot.gestureTester)
        let id = (tester.recent.map(\.id).max() ?? 0) + 1
        tester.recent.insert(entry(id, GestureNarrator.ignored(.hand)), at: 0)
        let ignored = try XCTUnwrap(tester.seen.firstIndex { $0.id == .ignored })
        tester.seen[ignored].count += 1
        tester.fingersDown = 5
        snapshot.gestureTester = tester
        await publish(snapshot)
        print("PalmTileTests: a whole hand: line \(lines.count), tile \(store.bodies[.palm])")
        XCTAssertEqual(store.bodies[.palm], 0)
        XCTAssertGreaterThan(lines.count, 0)
        XCTAssertLessThanOrEqual(lines.count, 2, "once for the change, once for what it read")
        follower.stop()
    }
}

extension PalmTileTests {
    /// The window's content, as the window hosts it, with the palm tile's line counted; laid out.
    fileprivate func hosted(_ store: GestureTesterStore, size: CGSize, counting lines: PalmFeedbackBodies) -> NSView {
        let host = NSHostingView(rootView: GestureTesterRoot(store: store).environment(\.palmFeedbackBodies, lines))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return host
    }
}

/// A model whose snapshot the test sets, as the live model publishes it.
@MainActor
@Observable
private final class FeedModel: AppModel {
    var snapshot: AppSnapshot
    init(_ snapshot: AppSnapshot) { self.snapshot = snapshot }
    func perform(_ command: AppCommand) {}
}
