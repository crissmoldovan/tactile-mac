// A long gesture through the whole path, second by second: the touchscreen's frames at the ILITEK's
// rate into the model with its fakes, its pipeline and a real gesture engine, the event sender's
// capture, the model's publishing, and, with the gesture tester open, the tester window's observer,
// its store and its content hosted off screen at the size it has on a 2560 × 1440 display. Nothing
// is posted, no window is opened, and the settings folder is temporary.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI
@testable import TactileApp
import TactileReading
import TactileScreens
import XCTest
import TactileTestSupport

private typealias Desk = DeskFixture

@MainActor
final class LongGestureTests: XCTestCase {

    enum Scenario: String, CaseIterable {
        /// Two fingers scrolling, up and down the glass, without stopping.
        case twoFingerScroll = "two-finger scroll"
        /// One finger resting, perfectly still, as the ILITEK reports a held finger.
        case oneFingerHold = "one-finger hold"
        /// One finger dragging round a circle without stopping.
        case oneFingerDrag = "one-finger drag"
    }

    /// One second of a gesture: how long each frame took on the main thread, with the ticks between
    /// it and the frame before, and what was done meanwhile.
    struct Second {
        var times: [Double] = []
        var events = 0
        var publishes = 0
        var bodies = 0

        var median: Double {
            let sorted = times.sorted()
            return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        }

        var total: Double { times.reduce(0, +) }
        var worst: Double { times.max() ?? 0 }
    }

    /// The tester's window, hosted off screen, as `GestureTesterWindow` hosts it.
    private struct Window {
        var store: GestureTesterStore
        var follower: GestureTesterFollower
        var host: NSHostingView<GestureTesterRoot>
    }

    /// The ILITEK reports a scan every 10 ms (survey B, every take): one frame each.
    static let frameInterval: TimeInterval = 0.01

    private let surface = Desk.driving(on: Desk.hdmi, diagonal: 23.8).surfaceSizeMM

    override func setUp() async throws {
        _ = NSApplication.shared
    }

    // MARK: - The gestures

    /// `seconds` of `scenario` on the ILITEK's glass, a frame every 10 ms, then the lift.
    func frames(_ scenario: Scenario, seconds: TimeInterval, at start: TimeInterval) -> [ContactFrame] {
        var glass = Glass(surface, at: start)
        let steps = Int((seconds / Self.frameInterval).rounded())
        switch scenario {
        case .twoFingerScroll:
            // Down 120 mm and back up in 3 s, again and again: a scroll that never stops.
            glass.land([(0, 220, 80), (1, 250, 80)])
            glass.trace(steps: steps) { id, step in
                let phase = (Double(step) * Self.frameInterval / 3).truncatingRemainder(dividingBy: 1)
                let along = phase < 0.5 ? phase * 2 : 2 - phase * 2
                return (id == 0 ? 220 : 250, 80 + 120 * along)
            }
        case .oneFingerHold:
            glass.land([(0, 240, 140)])
            glass.rest(seconds)
        case .oneFingerDrag:
            // Round a circle 80 mm across every 4 s.
            glass.land([(0, 280, 140)])
            glass.trace(steps: steps) { _, step in
                let angle = Double(step) * Self.frameInterval / 4 * 2 * .pi
                return (240 + 40 * cos(angle), 140 + 40 * sin(angle))
            }
        }
        glass.lift()
        return glass.frames
    }

    // MARK: - The path

    private func openWindow(on harness: ModelHarness) -> Window {
        let display = CGSize(width: 2560, height: 1440)
        let visible = CGRect(x: 0, y: 0, width: display.width, height: display.height - 25)
        let frame = GestureTesterWindowFrame.frame(in: visible)
        let content = NSWindow.contentRect(forFrameRect: frame, styleMask: GestureTesterNSWindow.style).size
        let model = harness.model
        let store = GestureTesterStore(
            touchscreen: Desk.ilitekID, layout: GestureTesterLayout(displaySize: display), snapshot: model.snapshot,
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
        return Window(store: store, follower: follower, host: host)
    }

    private func bodyCount(_ store: GestureTesterStore) -> Int {
        store.bodies.all.values.reduce(0, +)
    }

    /// `scenario` for `seconds` through the whole path, the tester open on the ILITEK or not: each
    /// frame's time on the main thread, by the second of the gesture it came in.
    func measure(_ scenario: Scenario, seconds: TimeInterval, testerOpen: Bool) async throws -> [Second] {
        let harness = try deskHarness(self, writesStateFile: true)
        var window: Window?
        if testerOpen {
            harness.model.perform(.openGestureTester(Desk.ilitekID))
            XCTAssertEqual(harness.model.snapshot.gestureTester?.touchscreen, Desk.ilitekID)
            window = openWindow(on: harness)
            window?.store.bodies.reset()
        }
        let start = harness.clock + 1
        let frames = frames(scenario, seconds: seconds, at: start)
        var buckets = Array(repeating: Second(), count: Int(seconds.rounded(.up)) + 1)
        var tickTime = harness.clock
        for frame in frames {
            let events = harness.outputs.events.count
            let tester = harness.model.snapshot.gestureTester
            let bodies = window.map { bodyCount($0.store) } ?? 0
            let began = DispatchTime.now().uptimeNanoseconds
            // The model's clock ticks 60 times a second in between, as the live ticker does.
            while tickTime + 1.0 / 60 < frame.time {
                tickTime += 1.0 / 60
                harness.clock = tickTime
                harness.model.tickPipelines()
            }
            tickTime = frame.time
            harness.clock = frame.time
            harness.source.send(frame, from: Desk.ilitekHandle)
            if let window {
                // The window's observer hands the snapshot to the store on the main actor's next turn.
                for _ in 0..<3 { await Task.yield() }
                window.host.layoutSubtreeIfNeeded()
            }
            let took = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            let index = min(buckets.count - 1, max(0, Int(frame.time - start)))
            buckets[index].times.append(took)
            buckets[index].events += harness.outputs.events.count - events
            if harness.model.snapshot.gestureTester != tester { buckets[index].publishes += 1 }
            buckets[index].bodies += (window.map { bodyCount($0.store) } ?? 0) - bodies
        }
        if let window {
            XCTAssertEqual(window.store.recent, harness.model.snapshot.gestureTester?.recent, "the window followed")
            window.follower.stop()
        }
        return Array(buckets.prefix(Int(seconds.rounded(.up))))
    }

    static func describe(_ seconds: [Second]) -> String {
        seconds.enumerated().map { index, second in
            String(format: "  s%02d: %4d frames, median %.3f ms, worst %.2f ms, busy %.1f ms/s, %d events, %d publishes, %d bodies",
                   index + 1, second.times.count, second.median, second.worst, second.total, second.events,
                   second.publishes, second.bodies)
        }.joined(separator: "\n")
    }

    // MARK: - The measurement

    /// The median of each second's median frame, over `seconds`: one second the machine was busy
    /// elsewhere moves it little.
    static func typical(_ seconds: ArraySlice<Second>) -> Double {
        let medians = seconds.map(\.median).sorted()
        return medians.isEmpty ? 0 : medians[medians.count / 2]
    }

    /// Each scenario for 30 s, the tester open and closed: a gesture's last second does what its
    /// first whole second did (the first holds the landing), frame for frame: as many events, as
    /// many of the tester's publishes, as many of its parts worked out again. Each second's time is
    /// printed, and a frame in the last ten seconds typically costs at most half as much again as in
    /// the first ten, with 0.03 ms to spare for the clock at these sizes: a cost that grows with the
    /// gesture, such as work over every sample kept since the fingers landed, is several times that.
    /// In CI, on a shared runner, the bound has headroom (`TestTiming.costBound`).
    func testALongGestureCostsTheSameInItsLastSecondAsInItsFirst() async throws {
        for testerOpen in [false, true] {
            for scenario in Scenario.allCases {
                let seconds = try await measure(scenario, seconds: 30, testerOpen: testerOpen)
                let name = "\(scenario.rawValue), tester \(testerOpen ? "open" : "closed")"
                print("LongGestureTests: \(name):\n\(Self.describe(seconds))")
                let first = seconds[1], last = seconds[seconds.count - 1]
                XCTAssertEqual(last.times.count, first.times.count, name)
                XCTAssertEqual(last.events, first.events, accuracy: 1, name)
                XCTAssertEqual(last.publishes, first.publishes, accuracy: 1, name)
                XCTAssertEqual(last.bodies, first.bodies, accuracy: 1, name)
                let early = Self.typical(seconds[1..<11]), late = Self.typical(seconds[(seconds.count - 10)...])
                print(String(format: "LongGestureTests: %@: a frame typically %.3f ms in s02–s11, %.3f ms in s21–s30",
                             name, early, late))
                XCTAssertLessThanOrEqual(late, TestTiming.costBound(early: early, ratio: 1.5, margin: 0.03),
                                         "\(name): frames cost more as the gesture goes on")
            }
        }
    }
}
