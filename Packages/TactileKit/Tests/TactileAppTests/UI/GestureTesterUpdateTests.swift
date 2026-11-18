import AppKit
import Observation
import SwiftUI
import XCTest

@testable import TactileApp

/// The tester's window as a gesture goes on: the model publishes the tester up to ten times a
/// second, and each time the fingers on the glass change, and only the feed and the fingers change
/// then. Its content is hosted as the window hosts it (`GestureTesterRoot` on the window's store, fed
/// by the window's observer), at the size the window has on a 2560 × 1440 display, in an
/// `NSHostingView` that is never put in a window; each part counts the times it works out its body
/// (`GestureTesterBodies`).
@MainActor
final class GestureTesterUpdateTests: XCTestCase {

    private struct Window {
        var model: FeedModel
        var store: GestureTesterStore
        var follower: GestureTesterFollower
        var host: NSHostingView<GestureTesterRoot>
    }

    private let ilitek = UIFixtures.ilitek

    override func setUp() async throws {
        _ = NSApplication.shared
    }

    /// The ILITEK's tester as the preview desk opens it: a feed of every kind, two fingers down.
    private func openTester() throws -> AppSnapshot {
        let preview = PreviewModel(.desk)
        preview.perform(.openGestureTester(ilitek))
        let snapshot = preview.snapshot
        let tester = try XCTUnwrap(snapshot.gestureTester)
        XCTAssertEqual(tester.recent.first?.kind, .ignored)
        return snapshot
    }

    private func window(_ snapshot: AppSnapshot) -> Window {
        let display = CGSize(width: 2560, height: 1440)
        let visible = CGRect(x: 0, y: 0, width: display.width, height: display.height - 25)
        let frame = GestureTesterWindowFrame.frame(in: visible)
        let content = NSWindow.contentRect(forFrameRect: frame, styleMask: GestureTesterNSWindow.style).size
        let model = FeedModel(snapshot)
        let store = GestureTesterStore(
            touchscreen: ilitek, layout: GestureTesterLayout(displaySize: display), snapshot: snapshot,
            perform: { _ in })
        let follower = GestureTesterFollower(model: model, tell: { _ in }, show: { store.update($0) })
        follower.start()
        let host = NSHostingView(rootView: GestureTesterRoot(store: store))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: content)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return Window(model: model, store: store, follower: follower, host: host)
    }

    /// The model publishes `next`; the window's observer hands it to the store on the main actor's
    /// next turn, and the hosting view updates and lays out.
    private func publish(_ next: AppSnapshot, to window: Window) async {
        window.model.snapshot = next
        for _ in 0..<10 { await Task.yield() }
        window.host.layoutSubtreeIfNeeded()
    }

    /// The `index`th of a run of feed-only updates: the scroll at the top of the feed goes on (its
    /// entry updated in place), and every fifth the fingers on the glass change.
    private func feedOnly(_ snapshot: AppSnapshot, _ index: Int) -> AppSnapshot {
        var next = snapshot
        guard var tester = next.gestureTester else { return next }
        tester.recent[0].summary = "\(index * 7) pt down"
        if index % 5 == 0 {
            tester.fingersDown = tester.fingersDown == 2 ? 3 : 2
        }
        next.gestureTester = tester
        return next
    }

    /// Every AppKit view in the window: the switches, the pickers, the button, the slider, the text,
    /// the scroll views, the photo's event catcher.
    private func appKitViews(_ view: NSView) -> Set<ObjectIdentifier> {
        view.subviews.reduce(into: [ObjectIdentifier(view)]) { found, subview in
            found.formUnion(appKitViews(subview))
        }
    }

    private func counts(_ store: GestureTesterStore) -> String {
        GestureTesterBodies.Part.allCases.map { "\($0): \(store.bodies[$0])" }.joined(separator: ", ")
    }

    // MARK: - Which parts are drawn again

    /// While a gesture goes on, its updates draw the feed's entries and the fingers on the glass
    /// again, each only when its own part changed, and nothing else: not the checklist or any of its
    /// rows, not the practice area or any tile, not the header, not the feed's panel with its Clear.
    /// No AppKit view in the window is made again.
    func testAGesturesUpdatesDrawOnlyTheFeedAndTheFingers() async throws {
        var snapshot = try openTester()
        let window = window(snapshot)
        let views = appKitViews(window.host)
        XCTAssertGreaterThan(views.count, 10, "the switches, pickers, buttons, text and scroll views")
        window.store.bodies.reset()

        for index in 1...100 {
            snapshot = feedOnly(snapshot, index)
            await publish(snapshot, to: window)
            XCTAssertEqual(window.store.recent.first?.summary, "\(index * 7) pt down")
        }

        let bodies = window.store.bodies
        print("GestureTesterUpdateTests: 100 feed-only updates: \(counts(window.store))")
        XCTAssertEqual(bodies[.feedList], 100, "the entries, once for each change: \(counts(window.store))")
        XCTAssertEqual(bodies[.fingers], 20, "the fingers, once for each of their changes")
        for part: GestureTesterBodies.Part in [
            .root, .content, .header, .checklist, .row, .practice, .swipes, .palm, .feed,
        ] {
            XCTAssertEqual(bodies[part], 0, "\(part) is drawn again by the feed: \(counts(window.store))")
        }
        XCTAssertEqual(appKitViews(window.host), views, "every AppKit view is the one there was")
        window.follower.stop()
    }

    /// A change the tester doesn't show: another touchscreen renamed and switched off, a General
    /// setting. Nothing in the window is drawn again.
    func testAChangeElsewhereDrawsNothing() async throws {
        let snapshot = try openTester()
        let window = window(snapshot)
        let views = appKitViews(window.host)
        window.store.bodies.reset()

        var elsewhere = snapshot
        let strip = try XCTUnwrap(elsewhere.touchscreens.firstIndex { $0.id == UIFixtures.strip })
        elsewhere.touchscreens[strip].name += " (2)"
        elsewhere.touchscreens[strip].isOn.toggle()
        await publish(elsewhere, to: window)
        elsewhere.recordsFrames.toggle()
        await publish(elsewhere, to: window)

        print("GestureTesterUpdateTests: a change elsewhere: \(counts(window.store))")
        XCTAssertEqual(window.store.bodies.all, [:], "nothing drawn again: \(counts(window.store))")
        XCTAssertEqual(appKitViews(window.host), views)
        window.follower.stop()
    }

    /// A gesture seen for the first time adds an entry and counts it on its row: the entries and that
    /// one row are drawn again, and no other row.
    func testAGestureSeenDrawsItsOwnRowAgain() async throws {
        var snapshot = try openTester()
        let window = window(snapshot)
        let tapRow = window.store.count(.tap).value
        window.store.bodies.reset()

        var tester = try XCTUnwrap(snapshot.gestureTester)
        let id = (tester.recent.map(\.id).max() ?? 0) + 1
        tester.recent.insert(RecognisedGesture(id: id, kind: .tap, fingers: 1, summary: "on Tap Me", at: 1), at: 0)
        let tap = try XCTUnwrap(tester.seen.firstIndex { $0.id == .tap })
        tester.seen[tap].count += 1
        snapshot.gestureTester = tester
        await publish(snapshot, to: window)

        print("GestureTesterUpdateTests: a tap seen: \(counts(window.store))")
        XCTAssertEqual(window.store.count(.tap).value, tapRow + 1)
        XCTAssertEqual(window.store.bodies[.row], 1, "the tap's row alone: \(counts(window.store))")
        XCTAssertEqual(window.store.bodies[.feedList], 1)
        for part: GestureTesterBodies.Part in [.root, .content, .header, .checklist, .practice, .swipes, .palm, .feed] {
            XCTAssertEqual(window.store.bodies[part], 0, "\(part): \(counts(window.store))")
        }
        window.follower.stop()
    }

    // MARK: - How long an update takes

    /// The main thread's time for each of 100 feed-only updates, from the snapshot reaching the
    /// window's store to its content laid out again, at 2560 × 1440. Reported, not asserted: the
    /// machine's load varies.
    func testTheTimeAFeedUpdateTakes() throws {
        var snapshot = try openTester()
        let window = window(snapshot)
        window.follower.stop()
        var times: [Double] = []
        for index in 1...100 {
            snapshot = feedOnly(snapshot, index)
            let start = DispatchTime.now().uptimeNanoseconds
            window.store.update(snapshot)
            window.host.layoutSubtreeIfNeeded()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            RunLoop.current.run(mode: .default, before: Date())
        }
        let sorted = times.sorted()
        print(String(
            format: "GestureTesterUpdateTests: a feed-only update at 2560 × 1440: median %.2f ms, worst %.2f ms, mean %.2f ms",
            sorted[sorted.count / 2], sorted.last ?? 0, times.reduce(0, +) / Double(times.count)))
        XCTAssertEqual(window.store.recent.first?.summary, "700 pt down")
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
