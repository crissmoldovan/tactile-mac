// The survey's takes, replayed end to end: the reader the app uses for the interface the reports
// arrived on, the path of a point, the contact filter and the gesture engine, chained as the app
// chains them. Nothing here opens a device, posts an event or writes a file.

import CoreGraphics
import Foundation
import TactileGestures
import TactileReading
import TactileScreens
import TactileTestSupport

/// Feeds one touchscreen's frames of contacts through the rest of the app's path, and collects what
/// the engine asks for.
///
/// Each contact's glass point goes through a `TouchMapping` with the glass as fitted (not turned,
/// not flipped) over the whole picture, which is how the survey's corner taps found both panels.
/// Each frame then carries the glass's size from `SurfaceSize`, at the diagonal given, and its
/// fingers pass through `ContactFilter(fingerLimit: options.fingerLimit)` before the engine sees
/// them. Time is ticked as `TouchScript.replay` ticks it in `TactileGesturesTests`: 60 times a
/// second between frames, then two seconds with no frames so that momentum and the session can
/// finish.
struct Replay {
    private let mapping: TouchMapping
    /// The glass's size in millimetres, which every frame carries.
    private let surfaceSize: CGSize
    private var filter: ContactFilter
    private let engine: GestureEngine

    /// `intent` answers every one-finger drag-or-scroll question.
    init(display: DisplayFacts, diagonalInches: Double, options: GestureOptions = .all, intent: OneFingerIntent) {
        guard let mapping = TouchMapping(orientation: .asFitted, alignment: .wholeGlass, display: display, content: nil)
        else { fatalError("no mapping for \(display.name): its frame \(display.frame) has no area") }
        self.mapping = mapping
        surfaceSize = SurfaceSize.millimetres(display: display, diagonalInches: diagonalInches)
        filter = ContactFilter(fingerLimit: options.fingerLimit)
        engine = GestureEngine(options: options) { _ in intent }
    }

    /// Feeds `frames` at their own times, ticking in between, then lets two seconds pass. Returns
    /// every action the engine asked for, in order.
    mutating func run(_ frames: [ContactFrame]) -> [GestureAction] {
        guard let first = frames.first else { return [] }
        var actions: [GestureAction] = []
        var time = first.time
        for frame in frames {
            while time + 1.0 / 60 < frame.time {
                time += 1.0 / 60
                actions += engine.tick(at: time)
            }
            time = frame.time
            actions += process(frame)
        }
        let end = time + 2
        while time < end {
            time = min(end, time + 1.0 / 60)
            actions += engine.tick(at: time)
        }
        return actions
    }

    /// One frame: its contacts mapped onto the display, through the filter, into the engine. A
    /// contact's size is in the panel's own units, not millimetres, so it isn't carried; neither
    /// surveyed panel reports one.
    private mutating func process(_ frame: ContactFrame) -> [GestureAction] {
        let fingers = frame.contacts.map {
            Finger(id: $0.id, location: mapping.displayPoint(forGlass: $0.position), isConfident: $0.isConfident)
        }
        return engine.process(TouchFrame(time: frame.time, fingers: filter.live(fingers), surfaceSize: surfaceSize))
    }
}

// MARK: - The two surveyed touchscreens

/// Something a take's recording doesn't have, that a replay needs.
struct ReplayError: Error, CustomStringConvertible {
    let description: String
}

/// The ILITEK "ILITEK-TP" (USB 222a:0001), on "HDMI", in survey B, takes 1–15. It sends touches on
/// its touch interface.
enum ILITEK {
    /// "HDMI": 2560 × 1440 points, not rotated. It reports 602 × 330 mm (27″); its glass is 23.8″.
    static let display = DisplayFacts(
        displayID: 3, uuid: "7E5D0A11-0000-4000-8000-000000000003", vendor: 0, model: 0, serial: 0,
        nativePixels: CGSize(width: 2560, height: 1440), sizeMM: .zero, name: "HDMI",
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)
    static let diagonalInches = 23.8

    /// Take `number`: the reports that arrived on the touch interface, decoded with that interface's
    /// own descriptor and built into frames by one `TouchFrameBuilder`, timed by the host's clock.
    static func frames(take number: Int) throws -> [ContactFrame] {
        let (decoder, reports) = try recording(
            SurveyFixtures.surveyB, vendorID: 0x222a, productID: 0x0001, interface: "touchscreen", take: number)
        var builder = TouchFrameBuilder()
        var frames: [ContactFrame] = []
        for (index, report) in reports.enumerated() {
            guard case .touch(let touch)? = decoder.decode(report.bytes) else {
                throw ReplayError(description: "ILITEK take \(number): touchscreen report \(index) is not a touch report")
            }
            if let frame = builder.add(touch, at: report.hostTime) { frames.append(frame) }
        }
        return frames
    }
}

/// The wch.cn "TouchScreen" strip (USB 27c0:0859), on "12.3FHD", in survey A, takes 1–20. It stays
/// in mouse mode and only sends reports on its mouse interface.
enum Strip {
    /// "12.3FHD": 1600 × 600 points, not rotated. It reports 240 × 90 mm (10.1″); its glass is 12.3″.
    static let display = DisplayFacts(
        displayID: 4, uuid: "7E5D0A11-0000-4000-8000-000000000004", vendor: 0, model: 0, serial: 0,
        nativePixels: CGSize(width: 1600, height: 600), sizeMM: .zero, name: "12.3FHD",
        frame: CGRect(x: 0, y: 0, width: 1600, height: 600), rotation: 0, isBuiltIn: false, isMain: false,
        mirrors: nil)
    static let diagonalInches = 12.3

    /// Take `number`: the reports that arrived on the mouse interface, decoded with that interface's
    /// own descriptor and read as one finger by a `PointerFingerReader` with this `guardInterval`,
    /// timed by the host's clock.
    static func frames(take number: Int, guardInterval: TimeInterval = 0.05) throws -> [ContactFrame] {
        let (decoder, reports) = try recording(
            SurveyFixtures.surveyA, vendorID: 0x27c0, productID: 0x0859, interface: "mouse", take: number)
        var reader = PointerFingerReader(guardInterval: guardInterval)
        var frames: [ContactFrame] = []
        for (index, report) in reports.enumerated() {
            guard case .pointer(let pointer)? = decoder.decode(report.bytes) else {
                throw ReplayError(description: "strip take \(number): mouse report \(index) is not a pointer report")
            }
            if let frame = reader.add(pointer, at: report.hostTime) { frames.append(frame) }
        }
        return frames
    }
}

/// The decoder for one interface of a surveyed touchscreen, and the take's reports that arrived on
/// that interface, in arrival order. Reports are told apart by the interface they came on, never by
/// report ID: the ILITEK uses report ID 4 on two interfaces.
private func recording(
    _ survey: SurveyFixtures.Survey, vendorID: Int, productID: Int, interface key: String, take number: Int
) throws -> (InterfaceDecoder, [SurveyFixtures.Report]) {
    let name = String(format: "%04x:%04x", vendorID, productID)
    guard let screen = survey.touchscreen(vendorID: vendorID, productID: productID) else {
        throw ReplayError(description: "the survey has no \(name)")
    }
    guard let interface = screen.interfaces.first(where: { $0.key == key }) else {
        throw ReplayError(description: "\(name) has no \(key) interface")
    }
    guard let decoder = InterfaceDecoder(descriptor: interface.descriptor) else {
        throw ReplayError(description: "the descriptor of \(name)'s \(key) interface did not parse")
    }
    guard let take = screen.takes.first(where: { $0.number == number }) else {
        throw ReplayError(description: "\(name) has no take \(number)")
    }
    return (decoder, take.reports.filter { $0.interfaceKey == key })
}

// MARK: - Reading the actions

/// The actions as short names, with the names `TouchScript` uses in `TactileGesturesTests`
/// ("click 1", "scroll began", "session ended" and so on), consecutive repeats collapsed.
func names(_ actions: [GestureAction]) -> [String] {
    var result: [String] = []
    for action in actions {
        let name = name(of: action)
        if result.last != name { result.append(name) }
    }
    return result
}

private func name(of action: GestureAction) -> String {
    switch action {
    case .sessionBegan: return "session began"
    case .movePointer: return "move"
    case .click(_, let count): return "click \(count)"
    case .press(_, let count): return "press \(count)"
    case .drag: return "drag"
    case .release: return "release"
    case .rightClick: return "right-click"
    case .longPressReady: return "long-press ready"
    case .longPressWithdrawn: return "long-press withdrawn"
    case .scroll(_, let phase): return "scroll \(phase)"
    case .momentum(_, let phase): return "momentum \(phase)"
    case .pinch(_, let phase): return "pinch \(phase)"
    case .rotate(_, let phase): return "rotate \(phase)"
    case .swipe(let direction): return "swipe \(direction)"
    case .swipeTracking(_, _, .began): return "tracking began"
    case .swipeTracking(_, _, .changed): return "tracking changed"
    case .swipeTracking(_, _, .completed): return "tracking completed"
    case .swipeTracking(_, _, .cancelled): return "tracking cancelled"
    case .sessionEnded: return "session ended"
    case .sessionCancelled: return "session cancelled"
    }
}

/// Whether every one of `expected` is in `names`, in that order, other names allowed between them.
func appear(_ expected: [String], inOrderIn names: [String]) -> Bool {
    var remaining = expected[...]
    for name in names where name == remaining.first {
        remaining = remaining.dropFirst()
    }
    return remaining.isEmpty
}

/// The count of every click, in order: 1 for a click, 2 for a double-click.
func clickCounts(_ actions: [GestureAction]) -> [Int] {
    actions.compactMap { if case .click(_, let count) = $0 { return count } else { return nil } }
}

/// The sum of every scroll movement, relative to the display. Momentum isn't counted.
func totalScroll(_ actions: [GestureAction]) -> CGVector {
    actions.reduce(CGVector.zero) { total, action in
        guard case .scroll(let delta, _) = action else { return total }
        return CGVector(dx: total.dx + delta.dx, dy: total.dy + delta.dy)
    }
}

/// Whether every `longPressReady` is followed at once by an action that takes its ring down: a
/// right-click, the press of a drag, `longPressWithdrawn` or `sessionCancelled`. Nothing else may
/// come between, and the actions may not end on it.
func everyRingIsTakenDown(_ actions: [GestureAction]) -> Bool {
    for (index, action) in actions.enumerated() {
        guard case .longPressReady = action else { continue }
        guard index + 1 < actions.count else { return false }
        switch actions[index + 1] {
        case .rightClick, .press, .longPressWithdrawn, .sessionCancelled: continue
        default: return false
        }
    }
    return true
}

/// Whether presses and releases alternate, starting with a press and ending with a release: no
/// button is pressed twice, released unpressed, or left held.
func everyPressIsReleased(_ actions: [GestureAction]) -> Bool {
    var held = false
    for action in actions {
        switch action {
        case .press:
            if held { return false }
            held = true
        case .release:
            if !held { return false }
            held = false
        default:
            break
        }
    }
    return !held
}
