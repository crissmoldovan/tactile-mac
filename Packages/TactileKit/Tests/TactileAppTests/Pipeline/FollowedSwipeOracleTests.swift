// Delivery 4b, Part S2, the review's P2: the same scripts through two pipelines, one following
// swipes and one whose sender refuses every swipe (so its shortcuts are exactly the engine's
// completions). Every Dock swipe goes to the recording outputs' capturing delivery.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class FollowedSwipeOracleTests: XCTestCase {
    private let following = Desk.driving(on: Desk.hdmi, diagonal: 23.8, swipesFollowFingers: true)
    private var surface: CGSize { following.surfaceSizeMM }

    private enum Step {
        case frame(ContactFrame)
        case tick(TimeInterval)
    }

    private enum Stop: Int, CaseIterable {
        case none, stoppedDriving, silence, palm, closedFromOutside
    }

    /// One or two touches of three or four fingers, each moving one to four times, now and then
    /// vertically, sometimes one finger lifting first; ticks between the touches and after them.
    private func script(_ generator: inout SplitMix64) -> [Step] {
        var steps: [Step] = []
        var time: TimeInterval = 10
        let touches = Int.random(in: 1...2, using: &generator)
        let spacing = 25 / surface.width
        for touch in 0..<touches {
            let count = Int.random(in: 3...4, using: &generator)
            var fingers: [(id: Int, x: CGFloat, y: CGFloat)] = (0..<count).map {
                (id: touch * 10 + $0, x: 0.4 + CGFloat($0) * spacing, y: 0.5)
            }
            func frame() -> ContactFrame {
                ContactFrame(time: time, contacts: fingers.map { Contact(id: $0.id, position: CGPoint(x: $0.x, y: $0.y)) })
            }
            steps.append(.frame(frame()))
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                var dx = Double.random(in: -45...45, using: &generator)
                var dy = Double.random(in: -6...6, using: &generator)
                if Int.random(in: 0..<6, using: &generator) == 0 { swap(&dx, &dy) }
                let n = Int.random(in: 2...15, using: &generator)
                for _ in 0..<n {
                    time += 0.01
                    fingers = fingers.map {
                        ($0.id, $0.x + CGFloat(dx) / CGFloat(n) / surface.width, $0.y + CGFloat(dy) / CGFloat(n) / surface.height)
                    }
                    steps.append(.frame(frame()))
                }
            }
            if Bool.random(using: &generator) {
                time += 0.01
                fingers.removeFirst()
                steps.append(.frame(frame()))
                for _ in 0..<Int.random(in: 0...6, using: &generator) {
                    time += 0.01
                    fingers = fingers.map { ($0.id, $0.x - 0.002, $0.y) }
                    steps.append(.frame(frame()))
                }
            }
            time += 0.01
            steps.append(.frame(ContactFrame(time: time, contacts: [])))
            let gap = touch + 1 < touches ? Double.random(in: 0.05...0.35, using: &generator) : 1.0
            var t = time
            while t < time + gap {
                t += 0.02
                steps.append(.tick(t))
            }
            time = t
        }
        return steps
    }

    /// Never both, never neither: Dock `ended`s plus shortcuts are exactly the twin's shortcuts, the
    /// engine's completions; every `began` has one end; nothing is left open, held, or pressed. Over
    /// 1,500 seeded sessions, each stopped at a random step (in the frame of the lift and during the
    /// hold too) by stopping driving, the silence rule, a palm, or a close from outside (what the
    /// model does on a display change that doesn't move the touches), or not at all. A swipe closed
    /// from outside and then completed by the fingers is exactly one shortcut, as the twin's.
    func testNeverBothNeverNeitherAgainstATwinThatNeverFollows() {
        var generator = SplitMix64(seed: 0xC0FFEE)
        var completions = 0, dockEnded = 0, dockCancelled = 0, stopsWithASwipeOpen = 0, stopsInTheHold = 0
        var closedThenShortcut = 0
        var failures = 0
        for session in 0..<1500 {
            let main = RecordingOutputs()
            let twin = RecordingOutputs()
            twin.dockSurroundings.defaultSpaces = nil
            let mp = TouchPipeline(id: Desk.ilitekID, driving: following, outputs: main, cancelOther: { _, _ in })
            let tp = TouchPipeline(id: Desk.ilitekID, driving: following, outputs: twin, cancelOther: { _, _ in })
            let steps = script(&generator)
            let stopAt = Int.random(in: 0...(steps.count + 3), using: &generator)
            let stop = Stop(rawValue: Int.random(in: 0..<Stop.allCases.count, using: &generator)) ?? .none
            var lastFrame: ContactFrame?
            var lastTime: TimeInterval = 10
            var closedFromOutside = false
            for (index, step) in steps.enumerated() {
                if index == stopAt, stop != .none {
                    if main.dockSwipes.isOpen { stopsWithASwipeOpen += 1 }
                    if !main.dockSwipes.isOpen, main.dockPhases.last == .ended || main.dockPhases.last == .cancelled {
                        stopsInTheHold += 1
                    }
                    switch stop {
                    case .none:
                        break
                    case .stoppedDriving:
                        mp.cancel(at: lastTime, reason: .stoppedDriving)
                        tp.cancel(at: lastTime, reason: .stoppedDriving)
                    case .silence:
                        if let last = lastFrame, !last.contacts.isEmpty {
                            mp.tick(at: last.time + TouchPipeline.silenceLimit + 0.1)
                            tp.tick(at: last.time + TouchPipeline.silenceLimit + 0.1)
                        }
                    case .palm:
                        if let last = lastFrame, !last.contacts.isEmpty {
                            let palm = ContactFrame(time: last.time + 0.005, contacts: last.contacts.enumerated().map {
                                Contact(id: $0.element.id, position: $0.element.position, isConfident: $0.offset != 0)
                            })
                            mp.handle(palm)
                            tp.handle(palm)
                        }
                    case .closedFromOutside:
                        closedFromOutside = main.dockSwipes.isOpen
                        main.dockSwipes.closeIfOpen()
                        twin.dockSwipes.closeIfOpen()
                    }
                }
                switch step {
                case .frame(let frame):
                    mp.handle(frame)
                    tp.handle(frame)
                    lastFrame = frame
                    lastTime = frame.time
                case .tick(let time):
                    mp.tick(at: time)
                    tp.tick(at: time)
                    lastTime = time
                }
            }
            mp.tick(at: lastTime + 2)
            tp.tick(at: lastTime + 2)

            let phases = main.dockPhases
            let ended = phases.filter { $0 == .ended }.count
            let cancelled = phases.filter { $0 == .cancelled }.count
            let began = phases.filter { $0 == .began }.count
            var ok = began == ended + cancelled
                && ended + main.shortcuts == twin.shortcuts
                && !main.dockSwipes.isOpen && main.count(.down) == main.count(.up)
                && twin.record.dockEvents.isEmpty && main.arbiter.owner == nil && twin.arbiter.owner == nil
            var open = false
            for phase in phases {
                switch phase {
                case .began:
                    if open { ok = false }
                    open = true
                case .changed:
                    if !open { ok = false }
                case .ended, .cancelled:
                    if !open { ok = false }
                    open = false
                }
            }
            if !ok {
                failures += 1
                if failures <= 10 {
                    XCTFail("session \(session), stop \(stop)@\(stopAt)/\(steps.count): main \(phases.filter { $0 != .changed }), shortcuts \(main.shortcuts); twin shortcuts \(twin.shortcuts); owner \(String(describing: main.arbiter.owner))")
                }
            }
            if closedFromOutside, main.shortcuts > 0 { closedThenShortcut += 1 }
            completions += twin.shortcuts
            dockEnded += ended
            dockCancelled += cancelled
        }
        XCTAssertEqual(failures, 0)
        // The sessions reach every case worth checking.
        XCTAssertGreaterThan(completions, 300)
        XCTAssertGreaterThan(dockEnded, 150)
        XCTAssertGreaterThan(dockCancelled, 150)
        XCTAssertGreaterThan(stopsWithASwipeOpen, 100)
        XCTAssertGreaterThan(stopsInTheHold, 10)
        XCTAssertGreaterThan(closedThenShortcut, 10, "closed from outside, then completed by the fingers")
    }
}
