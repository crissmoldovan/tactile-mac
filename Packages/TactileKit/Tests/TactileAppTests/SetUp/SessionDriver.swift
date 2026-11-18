// Set-up mode's session fed as the model feeds it, on the set-up desk: the scene the resolver would
// build for it, and a driver that keeps every event the session answered.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileReading
import TactileScreens
import XCTest

enum SessionDesk {

    /// A touchscreen connected and readable that can't be set up: no record of its own.
    static let oddID = TouchscreenID(rawValue: "#9:1111:2222:X")

    /// The cards of the candidate displays, in screen order: every external display.
    static let cards = [
        SetUpDisplayCard(id: 5, name: "Display", detail: "18-inch", touchscreen: nil, touchscreenName: nil),
        SetUpDisplayCard(id: 3, name: "HDMI", detail: "27-inch", touchscreen: nil, touchscreenName: nil),
        SetUpDisplayCard(id: 4, name: "12.3FHD", detail: "10-inch", touchscreen: SetUpDesk.stripID,
                         touchscreenName: "TouchScreen"),
        SetUpDisplayCard(id: 2, name: "LG HDR 4K", detail: "27-inch", touchscreen: nil, touchscreenName: nil),
    ]

    /// The ILITEK, not set up.
    static let ilitek = SetUpSession.Touchscreen(
        line: SetUpTouchscreenLine(id: SetUpDesk.ilitekID, name: "ILITEK-TP", state: .notSetUp, reason: nil),
        reportedSizeMM: SetUpDesk.ilitekGlass, pairing: nil, diagonalInches: 23.8, ownDisplay: nil)

    /// The strip, set up on "12.3FHD".
    static let strip = SetUpSession.Touchscreen(
        line: SetUpTouchscreenLine(id: SetUpDesk.stripID, name: "TouchScreen", state: .setUp(displayName: "12.3FHD"),
                                   reason: nil),
        reportedSizeMM: SetUpDesk.stripGlass, pairing: SetUpDesk.pairing(SetUpDesk.strip), diagonalInches: 12.3,
        ownDisplay: 4)

    /// One that can't be set up.
    static let odd = SetUpSession.Touchscreen(
        line: SetUpTouchscreenLine(id: oddID, name: "Panel", state: .cannotBeSetUp,
                                   reason: "Tactile can’t keep settings for it."),
        reportedSizeMM: nil, pairing: nil, diagonalInches: nil, ownDisplay: nil)

    static var scene: SetUpSession.Scene {
        SetUpSession.Scene(displays: SetUpDesk.all, cards: cards, touchscreens: [ilitek, strip, odd], isReconfiguring: false)
    }

    /// `scene` with `change` made to it.
    static func scene(_ change: (inout SetUpSession.Scene) -> Void) -> SetUpSession.Scene {
        var scene = scene
        change(&scene)
        return scene
    }

    /// The displays reconfiguring: none published, the cards as last known.
    static var reconfiguring: SetUpSession.Scene {
        scene {
            $0.displays = []
            $0.isReconfiguring = true
        }
    }
}

/// A session, fed as the model feeds it. Times are given in seconds since the mode began, `t0` on the
/// host's clock.
struct SessionDriver {
    static let t0: TimeInterval = 1000

    private(set) var session: SetUpSession
    /// Every event the session has answered, in order.
    private(set) var events: [SetUpSession.Event] = []
    /// What the last call answered.
    private(set) var last: [SetUpSession.Event] = []
    /// The latest time given, in seconds since the start.
    private(set) var latest: Double = 0

    init(_ scene: SetUpSession.Scene = SessionDesk.scene, file: StaticString = #filePath, line: UInt = #line) throws {
        session = try XCTUnwrap(SetUpSession(scene, at: Self.t0), "no session", file: file, line: line)
    }

    static func time(_ seconds: Double) -> TimeInterval { t0 + seconds }

    var snapshot: SetUpModeSnapshot { session.snapshot }
    var stage: SetUpModeSnapshot.Stage { session.snapshot.stage }
    var step: SetUpStep? { session.flow?.snapshot.step }

    @discardableResult
    mutating func call(_ action: (inout SetUpSession) -> [SetUpSession.Event]) -> [SetUpSession.Event] {
        last = action(&session)
        events += last
        return last
    }

    @discardableResult
    mutating func tick(_ seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.tick(at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func frame(_ seconds: Double, _ id: TouchscreenID, _ contacts: [Contact]) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.handle(ContactFrame(time: Self.time(seconds), contacts: contacts), from: id) }
    }

    /// `fingers` fingers of `id`'s, landing at `seconds`, held still for `hold` in frames every
    /// 10 ms, and lifting; at `point` for the first, the others beside it.
    @discardableResult
    mutating func touch(
        _ id: TouchscreenID, at seconds: Double, fingers: Int = 1, hold: Double = 0.1,
        point: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> [SetUpSession.Event] {
        let contacts = (0..<fingers).map { Contact(id: $0 + 1, position: CGPoint(x: point.x + Double($0) / 20, y: point.y)) }
        var answered: [SetUpSession.Event] = []
        var t = seconds
        while t < seconds + hold {
            answered += frame(t, id, contacts)
            t += 0.01
        }
        return answered + frame(seconds + hold, id, [])
    }

    /// The glass of `id` clearing.
    @discardableResult
    mutating func lift(_ seconds: Double, _ id: TouchscreenID) -> [SetUpSession.Event] {
        frame(seconds, id, [])
    }

    /// A tap on each glass point in turn, one a second from `seconds`, with a tick before each.
    mutating func taps(_ points: [CGPoint], _ id: TouchscreenID, from seconds: Double) {
        for (i, p) in points.enumerated() {
            tick(seconds + Double(i))
            touch(id, at: seconds + Double(i), point: p)
        }
    }

    @discardableResult
    mutating func choose(_ display: UInt32, at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.choose(display: display, at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func back(at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.back(at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func confirmSize(_ inches: Double?, at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.confirmSize(inches: inches, at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func done(at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.done(at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func begin(_ purpose: SetUpPurpose, of id: TouchscreenID, at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.begin(purpose, of: id, at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func finish(at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.finish(at: Self.time(seconds)) }
    }

    @discardableResult
    mutating func scene(_ scene: SetUpSession.Scene, at seconds: Double) -> [SetUpSession.Event] {
        latest = max(latest, seconds)
        return call { $0.sceneChanged(scene, at: Self.time(seconds)) }
    }

    /// Chooses `display` at `seconds`, and `id` touches its glass half a second later: a flow at the
    /// corners, as long as nothing stops it.
    mutating func chooseAndTouch(_ display: UInt32, _ id: TouchscreenID, at seconds: Double) {
        tick(seconds)
        choose(display, at: seconds)
        tick(seconds + 0.5)
        touch(id, at: seconds + 0.5)
    }

    /// The outcomes the session gave the model to store.
    var stored: [SetUpFlow.Outcome] {
        events.compactMap {
            if case .flowFinished(_, _, _, let outcome?) = $0 { return outcome }
            return nil
        }
    }

    /// How the mode ended, if it has.
    var ending: SetUpSession.Event? {
        events.first {
            if case .ended = $0 { return true }
            return false
        }
    }
}
