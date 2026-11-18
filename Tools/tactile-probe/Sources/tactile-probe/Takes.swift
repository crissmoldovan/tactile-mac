// The takes, in order, each with its number, its words and the state the touchscreen must be in.
// Pure. Takes 1–20 are those of the first survey (2026-11-14): their numbers, IDs and titles are
// read by tests in TactileKit and never change. New takes are added at the end.

import Foundation

/// The state a take needs the touchscreen in. Each later state includes the earlier ones: a take
/// that needs the touchscreen held also runs after the switch to multi-touch.
enum TakeState: Int, Comparable {
    /// As the touchscreen was found: no Input Mode written, not held.
    case asFound
    /// Input Mode switched to multi-touch, when the touchscreen has that setting. Not held.
    case multiTouch
    /// Switched, and its touchscreen and mouse interfaces held by this tool alone.
    case exclusive

    static func < (a: TakeState, b: TakeState) -> Bool { a.rawValue < b.rawValue }
}

struct TakeSpec: Equatable {
    let number: Int
    let id: String
    let title: String
    /// What to do, exactly as shown. Saved in the survey file as `prompt`.
    let prompt: String
    let note: String?
    let state: TakeState
    var isCorner: Bool { id.hasPrefix("corner-") }
}

enum Takes {
    static let all: [TakeSpec] = {
        var list: [(String, String, String, String?, TakeState)] = [
            ("identify-circle", "Find the touchscreen",
             "Put ONE finger on this screen, draw a slow circle for about 3 seconds, then lift.",
             "This first take also shows that the instructions are on the right screen.", .asFound),
            ("two-fingers-rest", "Two fingers resting", "Rest TWO fingers apart for 2 seconds, then lift both.", nil, .multiTouch),
            ("max-fingers", "As many fingers as you can",
             "Put down as many fingers as you can, both hands, hold 2 seconds, then lift.", nil, .multiTouch),
            ("exclusive-circle", "Circle, touchscreen held by this tool",
             "ONE finger: draw a slow circle for 3 seconds, then lift.", "This tool now holds the touchscreen to itself.", .exclusive),
        ]
        for (id, name) in [("top-left", "TOP-LEFT"), ("top-right", "TOP-RIGHT"), ("bottom-right", "BOTTOM-RIGHT"), ("bottom-left", "BOTTOM-LEFT")] {
            list.append(("corner-\(id)", "Corner: \(name.lowercased())",
                         "Tap the \(name) corner of the picture on this screen, as you see it now. One quick tap with one finger.",
                         nil, .multiTouch))
        }
        let gestures: [(String, String, String, String?)] = [
            ("tap", "One-finger tap", "Tap once with ONE finger, anywhere on the screen.", nil),
            ("double-tap", "Double tap", "Double-tap with ONE finger: two quick taps on the same spot.", nil),
            ("drag", "Drag", "With ONE finger, drag about 10 cm from left to right, then lift.", nil),
            ("rest-then-drag", "Rest, then drag", "Rest ONE finger still for 1 second, then drag it about 10 cm, then lift.", nil),
            ("press-and-hold", "Press and hold", "Press ONE finger down, hold it still for 1 second, then lift.", nil),
            ("two-finger-scroll-flick", "Two-finger scroll ending in a flick",
             "Put TWO fingers side by side and slide them UP the screen about 10 cm, as if scrolling a page down, flicking them off the glass at the end.",
             nil),
            ("pinch", "Pinch out, then in", "Put TWO fingers close together, spread them apart, pinch them back together, then lift.", nil),
            ("two-finger-tap", "Two-finger tap", "Tap once with TWO fingers at the same time.", nil),
            ("two-finger-rotate", "Two-finger twist",
             "Put TWO fingers down about 5 cm apart and twist them a quarter turn, like turning a knob, then lift.", nil),
            ("three-finger-swipe-left", "Three-finger swipe left", "With THREE fingers together, swipe LEFT about 10 cm, then lift.", nil),
            ("four-finger-swipe-up", "Four-finger swipe up", "With FOUR fingers together, swipe UP about 10 cm, then lift.", nil),
            ("palm", "Palm", "Lay your palm flat on the screen for 2 seconds, then lift it.", nil),
            // Added after the first survey. Take 14's fingers stopped 0.39 s before lifting, so it
            // showed nothing about momentum; this one lifts while they move.
            ("two-finger-flick", "Two-finger flick",
             "Put TWO fingers side by side and flick them UP the screen, fast, about 5 cm: lift them off the glass while they are still moving.",
             "Do not stop before lifting. Flick as if throwing a page upwards."),
            // A second finger that lands late. Take 15's landed 0.64 s after the first and only just counted.
            ("second-finger-late", "Second finger half a second late",
             "Put ONE finger down and keep it still. About half a second later, put a SECOND finger beside it, then slide both UP together about 5 cm and lift.",
             nil),
        ]
        for (id, title, prompt, note) in gestures { list.append((id, title, prompt, note, .exclusive)) }
        return list.enumerated().map { index, take in
            TakeSpec(number: index + 1, id: take.0, title: take.1, prompt: take.2, note: take.3, state: take.4)
        }
    }()

    static var count: Int { all.count }

    static func take(_ number: Int) -> TakeSpec? {
        all.indices.contains(number - 1) ? all[number - 1] : nil
    }
}
