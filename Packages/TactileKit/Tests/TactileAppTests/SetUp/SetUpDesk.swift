// The desk as the set-up flow sees it, and a driver that feeds a flow frames and ticks the way the
// model does.
//
// The displays are the design's *The desk today*, with the same values as `DeskFixture` (kept here
// so that these tests stand alone): frames in points, origin at the top-left of the main display,
// y growing downwards; sizes as each display reports them, which can be wrong.

import CoreGraphics
import Foundation
import TactileApp
import TactileReading
import TactileScreens
import XCTest

enum SetUpDesk {

    // MARK: - Displays

    /// The Mac's own display: never a candidate.
    static let builtIn = DisplayFacts(
        displayID: 1, uuid: "FACADE00-0000-4000-8000-000000000001", vendor: 0x0610, model: 0xa050, serial: 0,
        nativePixels: CGSize(width: 3024, height: 1964), sizeMM: CGSize(width: 302, height: 196), name: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), rotation: 0, isBuiltIn: true, isMain: true,
        mirrors: nil)

    /// The 27″ 4K monitor, to the right.
    static let lg = DisplayFacts(
        displayID: 2, uuid: "1E6D5B14-0000-0000-2B1F-0104B53C2278", vendor: 0x1e6d, model: 0x5b14, serial: 0x0006_d3b1,
        nativePixels: CGSize(width: 3840, height: 2160), sizeMM: CGSize(width: 597, height: 336), name: "LG HDR 4K",
        frame: CGRect(x: 2056, y: 0, width: 3008, height: 1692), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 2K monitor the ILITEK sits on, above the main display. It reports 27″; it is 23.8″.
    static let hdmi = DisplayFacts(
        displayID: 3, uuid: "4C2D0E10-0000-0000-0A20-0104B53C2278", vendor: 0x4c2d, model: 0x0e10, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1440), sizeMM: CGSize(width: 602, height: 329), name: "HDMI",
        frame: CGRect(x: -252, y: -1440, width: 2560, height: 1440), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The strip the wch.cn touchscreen sits on, below the main display. It reports 10.1″; it is 12.3″.
    static let strip = DisplayFacts(
        displayID: 4, uuid: "2D1E0123-0000-0000-1A21-0103802D1A78", vendor: 0x2d1e, model: 0x0123, serial: 0,
        nativePixels: CGSize(width: 1920, height: 720), sizeMM: CGSize(width: 240, height: 90), name: "12.3FHD",
        frame: CGRect(x: 228, y: 1329, width: 1600, height: 600), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    /// The 18″ monitor, to the left.
    static let display = DisplayFacts(
        displayID: 5, uuid: "3A495678-0000-0000-0F22-0104A5271878", vendor: 0x3a49, model: 0x5678, serial: 1,
        nativePixels: CGSize(width: 2560, height: 1600), sizeMM: CGSize(width: 388, height: 242), name: "Display",
        frame: CGRect(x: -2048, y: 24, width: 2048, height: 1280), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)

    static let all = [builtIn, lg, hdmi, strip, display]

    /// "HDMI" turned 90° in macOS: its frame and reported size turn with it, its native size doesn't.
    static let hdmiTurned = changed(hdmi) {
        $0.frame = CGRect(x: -252, y: -2560, width: 1440, height: 2560)
        $0.sizeMM = CGSize(width: 329, height: 602)
        $0.rotation = 90
    }

    /// `display` turned `degrees` in macOS: its frame and reported size turn, its native size doesn't.
    static func turned(_ display: DisplayFacts, by degrees: Int) -> DisplayFacts {
        changed(display) {
            $0.rotation = degrees
            if degrees % 180 != 0 {
                $0.frame.size = CGSize(width: display.frame.height, height: display.frame.width)
                $0.sizeMM = CGSize(width: display.sizeMM.height, height: display.sizeMM.width)
            }
        }
    }

    /// Every display, with `display` in place of the one with its ID.
    static func all(with display: DisplayFacts) -> [DisplayFacts] {
        all.map { $0.displayID == display.displayID ? display : $0 }
    }

    // MARK: - Touchscreens

    static let ilitekID = TouchscreenID(rawValue: "222a:0001:V06.00.00.00")
    /// The glass the ILITEK reports: 21.5″.
    static let ilitekGlass = CGSize(width: 476, height: 268)
    static let stripID = TouchscreenID(rawValue: "27c0:0859:TEST-SERIAL-0001")
    /// The glass the strip reports.
    static let stripGlass = CGSize(width: 217, height: 91)

    /// The ILITEK's set-up, by default a full one on "HDMI", the display set-up mode chose.
    static func start(
        _ purpose: SetUpPurpose = .full, candidates: [DisplayFacts] = [hdmi],
        all: [DisplayFacts] = all, glass: CGSize? = ilitekGlass, current: Pairing? = nil, diagonal: Double? = nil
    ) -> SetUpFlow.Start {
        SetUpFlow.Start(
            touchscreen: ilitekID, touchscreenName: "ILITEK-TP", purpose: purpose, candidates: candidates,
            allDisplays: all, reportedSizeMM: glass, current: current, currentDiagonal: diagonal)
    }

    /// A calibration of the ILITEK on `display`: its own display, already paired.
    static func calibrating(_ display: DisplayFacts = hdmi) -> SetUpFlow.Start {
        start(.calibrate, candidates: [display], current: pairing(display))
    }

    /// The ILITEK paired with `display`, fitted as given.
    static func pairing(
        _ display: DisplayFacts, _ orientation: Orientation = .asFitted, _ rect: CGRect = wholeGlass
    ) -> Pairing {
        Pairing(
            display: DisplayIdentity(display), orientation: orientation, alignment: GlassAlignment(pictureRect: rect))
    }

    // MARK: - Glass

    static let wholeGlass = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// A picture a little in from the glass's edges, not centred: what a real fit looks like.
    static let offCentre = CGRect(x: 0.02, y: 0.03, width: 0.95, height: 0.93)

    /// Where on the glass a finger lands to touch `p`, a point of `display`'s picture as the person
    /// sees it (0…1, origin top-left), when the glass is fitted with `orientation` and the picture
    /// covers `rect` of it. Worked out by hand, backwards along the path of a point, so that it
    /// doesn't lean on `TouchMapping`:
    /// - the letterbox, when `display` shows `content`'s picture: centred, filling the panel (as
    ///   macOS has turned it) on one axis;
    /// - the macOS rotation: by 90° a point (x, y) of the panel's own picture shows at (1 − y, x), so
    ///   a point seen at p is (p.y, 1 − p.x) of the panel; by 270°, (1 − p.y, p.x);
    /// - the alignment, then the orientation, undone.
    static func glassPoint(
        touching p: CGPoint, on display: DisplayFacts, content: DisplayFacts? = nil,
        orientation: Orientation = .asFitted, rect: CGRect = wholeGlass
    ) -> CGPoint {
        var panel = p
        if let content {
            let native = display.nativePixels
            let panelAspect = display.rotation % 180 == 0 ? native.width / native.height : native.height / native.width
            let contentAspect = content.frame.width / content.frame.height
            if contentAspect >= panelAspect {
                let share = panelAspect / contentAspect
                panel.y = (1 - share) / 2 + p.y * share
            } else {
                let share = contentAspect / panelAspect
                panel.x = (1 - share) / 2 + p.x * share
            }
        }
        let unturned: CGPoint
        switch display.rotation {
        case 90: unturned = CGPoint(x: panel.y, y: 1 - panel.x)
        case 180: unturned = CGPoint(x: 1 - panel.x, y: 1 - panel.y)
        case 270: unturned = CGPoint(x: 1 - panel.y, y: panel.x)
        default: unturned = panel
        }
        let oriented = CGPoint(
            x: rect.origin.x + unturned.x * rect.size.width, y: rect.origin.y + unturned.y * rect.size.height)
        return orientation.inverse(oriented)
    }

    /// The glass points of the four corner taps, in the order the targets are shown.
    static func cornerTaps(
        on display: DisplayFacts, content: DisplayFacts? = nil, orientation: Orientation = .asFitted,
        rect: CGRect = wholeGlass
    ) -> [CGPoint] {
        Calibration.targets.map {
            glassPoint(touching: $0, on: display, content: content, orientation: orientation, rect: rect)
        }
    }
}

/// A set-up flow, fed as the model feeds it. Times are given in seconds since the flow started,
/// `t0` on the host's clock, which is not 0, so that nothing can rely on it being.
struct FlowDriver {
    static let t0: TimeInterval = 1000

    private(set) var flow: SetUpFlow
    /// The last tick given, in tenths of a second since the start.
    private var lastTick = 0
    /// What the flow said last.
    private(set) var last: SetUpFlow.Event = .stillRunning
    /// The latest time given, in seconds since the start.
    private(set) var latest: Double = 0

    init(_ start: SetUpFlow.Start, file: StaticString = #filePath, line: UInt = #line) throws {
        flow = try XCTUnwrap(SetUpFlow(start, at: Self.t0), "no flow", file: file, line: line)
    }

    var step: SetUpStep { flow.snapshot.step }

    /// The time `seconds` after the start, on the host's clock.
    static func time(_ seconds: Double) -> TimeInterval {
        t0 + seconds
    }

    /// Ticks every tenth of a second, as the model does, after the last one given up to and including
    /// `seconds`.
    @discardableResult
    mutating func wait(until seconds: Double) -> SetUpFlow.Event {
        let end = Int((seconds * 10).rounded())
        while lastTick < end {
            lastTick += 1
            last = flow.tick(at: Self.t0 + Double(lastTick) / 10)
        }
        latest = max(latest, Double(end) / 10)
        return last
    }

    @discardableResult
    mutating func frame(_ seconds: Double, _ contacts: [Contact]) -> SetUpFlow.Event {
        last = flow.handle(ContactFrame(time: Self.time(seconds), contacts: contacts))
        latest = max(latest, seconds)
        return last
    }

    /// One finger, `id`, at `p`.
    @discardableResult
    mutating func finger(_ seconds: Double, at p: CGPoint, id: Int = 1) -> SetUpFlow.Event {
        frame(seconds, [Contact(id: id, position: p)])
    }

    /// The glass clearing.
    @discardableResult
    mutating func lift(_ seconds: Double) -> SetUpFlow.Event {
        frame(seconds, [])
    }

    /// One finger that lands on `p` at `seconds`, is held still for `hold` in frames every 10 ms,
    /// and lifts.
    @discardableResult
    mutating func tap(_ p: CGPoint, at seconds: Double, hold: Double = 0.1, id: Int = 1) -> SetUpFlow.Event {
        var t = seconds
        while t < seconds + hold {
            finger(t, at: p, id: id)
            t += 0.01
        }
        return lift(seconds + hold)
    }

    /// A tap on each glass point in turn, one a second from `seconds`, with the ticks up to each.
    @discardableResult
    mutating func taps(_ points: [CGPoint], from seconds: Double) -> SetUpFlow.Event {
        for (i, p) in points.enumerated() {
            wait(until: seconds + Double(i))
            tap(p, at: seconds + Double(i))
        }
        return last
    }

    /// Calls `confirmSize`, `redo`, `done` or `cancel`, and keeps what it said.
    @discardableResult
    mutating func call(_ action: (inout SetUpFlow) -> SetUpFlow.Event) -> SetUpFlow.Event {
        last = action(&flow)
        return last
    }

    /// The person's command, `delay` after the latest time given, as the model gives it: a tick at
    /// that moment, the command, and a tick at the same moment, which times a change it made.
    @discardableResult
    mutating func press(after delay: Double = 1, _ action: (inout SetUpFlow) -> SetUpFlow.Event) -> SetUpFlow.Event {
        latest += delay
        let time = Self.time(latest)
        last = flow.tick(at: time)
        if last == .stillRunning { last = action(&flow) }
        if last == .stillRunning { last = flow.tick(at: time) }
        return last
    }
}

/// The same numbers on every run (SplitMix64).
struct Seeded: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `value` with `change` made to it. (`with` itself is `DeskFixture`'s, in this target.)
func changed<Value>(_ value: Value, _ change: (inout Value) -> Void) -> Value {
    var value = value
    change(&value)
    return value
}
