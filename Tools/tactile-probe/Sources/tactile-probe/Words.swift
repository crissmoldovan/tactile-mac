// What the person reads in the terminal: the opening line, the summary after each take, and the
// apps that must not run alongside. Pure.

import Foundation

/// The first thing `survey` prints, before anything else.
let surveyOpeningLine =
    "Quit Tactile and Touch Up before this survey: they read the touchscreens too, and every touch would happen twice."

/// "Tactile" or "Touch Up" when a process at this path is one of them, else nil.
func conflictingAppName(path: String) -> String? {
    let executable = (path as NSString).lastPathComponent
    for name in ["Touch Up", "Tactile"] where executable == name || path.contains("/\(name).app/Contents/MacOS/") {
        return name
    }
    return nil
}

/// The plain-words line after a take, saved as the take's `summary`. It says nothing about the
/// pointer: the pointer's record stays in the file, where an analyst can read it, but a line about
/// it misled the person into stopping a good run.
func summarize(_ take: Take, stepTimeout: Double, isCorner: Bool, otherTouchscreen: String?) -> String {
    let otherTouched = take.otherTouchscreenReports > 0
    guard let facts = take.facts else {
        var text = take.result == "interrupted" ? "Stopped before any touch arrived." : "No touch seen in \(Int(stepTimeout.rounded())) s."
        if otherTouched {
            text += " But the other touchscreen\(otherTouchscreen.map { ", \($0)," } ?? "") was touched: that is the wrong screen."
            text += " Touch the screen that says TOUCH THIS SCREEN."
        }
        return text
    }
    var text: String
    let n = facts.maxContactsDown
    if n > 0 {
        text = "Got it: \(n) finger\(n == 1 ? "" : "s")"
        if take.endReason == "went quiet with contacts down" {
            text += ", but the panel went quiet without reporting the lift"
        } else if facts.finalTipUp == "every contact" {
            text += ", lifted cleanly"
        } else if facts.finalTipUp == "some" {
            text += ", lifted (some lifts were not reported, the fingers just disappeared)"
        } else {
            text += ", lifted (the panel did not report the lifts, the fingers just disappeared)"
        }
    } else if let buttons = facts.mouseButtonsSeen {
        if buttons != 0 {
            text = "Got it: it came through as a mouse, "
            text += facts.mouseButtonReleased == true ? "button pressed and released" : "button still held at the end"
        } else {
            text = "Got it: it came through as a mouse, but with no button press"
        }
    } else {
        text = "Reports arrived, but none showed a finger down"
    }
    if take.endReason == "15 s limit" { text += "; stopped at the 15 s limit" }
    let total = take.reportCounts.values.reduce(0, +)
    let parts = take.reportCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    let seconds = String(format: "%.1f", take.reportSpanSeconds ?? 0)
    text += ". \(seconds) s, \(total) report\(total == 1 ? "" : "s") (\(parts))."
    if isCorner, let tap = take.tap {
        if let p = tap.touch { text += String(format: " Tap at %.0f%% across, %.0f%% down.", p.x * 100, p.y * 100) }
        else if let p = tap.mouse { text += String(format: " Tap at %.0f%% across, %.0f%% down (from the mouse interface).", p.x * 100, p.y * 100) }
    }
    if otherTouched {
        text += " The other touchscreen\(otherTouchscreen.map { ", \($0)," } ?? "") was touched too; its \(take.otherTouchscreenReports) reports were ignored."
    }
    return text
}

/// The short verdict shown on the glass after a take.
struct GlassVerdict: Equatable {
    let text: String
    /// Green when something was recorded, red otherwise.
    let good: Bool
}

func glassVerdict(_ take: Take, otherTouchscreen: String?) -> GlassVerdict {
    guard let facts = take.facts else {
        if take.otherTouchscreenReports > 0 {
            let name = otherTouchscreen.map { " (\($0))" } ?? ""
            return GlassVerdict(text: "That came from the OTHER touchscreen\(name), not this one.", good: false)
        }
        return GlassVerdict(text: take.result == "interrupted" ? "Stopped." : "No touch seen.", good: false)
    }
    let full = summarize(take, stepTimeout: 0, isCorner: false, otherTouchscreen: nil)
    let first = full.range(of: ". ").map { String(full[..<$0.lowerBound]) + "." } ?? full
    return GlassVerdict(text: first, good: facts.maxContactsDown > 0 || (facts.mouseButtonsSeen ?? 0) != 0)
}

// MARK: - Decisions during a run (review, fix round 1)

/// The red line on the glass after a touch on another touchscreen. Only while nothing has come
/// from the touchscreen being surveyed: once it is recording, the warning would contradict the
/// status line, which is what led the person to stop a good run before.
func wrongScreenWarning(otherReports: Int, started: Bool, otherName: String?, knowsDisplay: Bool, product: String?) -> String? {
    guard otherReports > 0, !started else { return nil }
    let name = otherName.map { " (\($0))" } ?? ""
    return knowsDisplay
        ? "That was the OTHER touchscreen\(name). Touch THIS screen."
        : "That was the OTHER touchscreen\(name). Use \(product ?? "this touchscreen") instead."
}

/// Whether a new attempt at a take goes into the file in place of the earlier one. A recording is
/// never given up for an attempt that saw no touch or was cut short: a redo can't lose a good take.
func newAttemptReplaces(earlier: Take?, with new: Take) -> Bool {
    guard let earlier else { return true }
    if new.result == "recorded" { return true }
    return earlier.result != "recorded"
}

/// How a run ended.
enum RunEnd: Equatable {
    case finished
    /// `s` after a take.
    case stoppedByPerson(afterTake: Int)
    /// A signal, during a take or between takes (`take` is the last one started; nil before the first).
    case signal(Int32, take: Int?, duringTake: Bool)
    case stillRunning
}

/// `completed` and `endedBecause` at the top of the survey file. Endings 1.0 also had start with its
/// words ("finished", "stopped by signal N", "still running"); the new one, `s`, starts "stopped by
/// the person". Each then says which takes were asked for.
func runEnding(_ end: RunEnd, selection: TakeSelection) -> (completed: Bool, endedBecause: String) {
    let asked = selection.text
    switch end {
    case .finished:
        return (true, "finished: \(asked)")
    case .stoppedByPerson(let take):
        return (false, "stopped by the person after take \(take), of \(asked)")
    case .signal(let sig, let take, let during):
        let place = take.map { during ? "during take \($0)" : "after take \($0)" } ?? "before the first take"
        return (false, "stopped by signal \(sig) \(place), of \(asked)")
    case .stillRunning:
        return (false, "still running: \(asked)")
    }
}

/// `tactile-survey-YYYYMMDD-HHMMSS.json`, with the takes when not all of them: `-takes16to22`.
func surveyFileName(stamp: String, selection: TakeSelection) -> String {
    "tactile-survey-\(stamp)\(selection.fileNameTag).json"
}

/// What `survey` says about how it works, before the first take.
func surveyIntroduction(stepTimeout: Double, windows: Bool) -> [String] {
    var lines = ["How it works:"]
    if windows { lines.append("  - Watch the screen that shows the take: it says what to do, and counts down.") }
    lines.append("  - Touch only when a take asks you to. A take waits up to \(Int(stepTimeout.rounded())) s for your touch; with none,")
    lines.append("    it says so and waits for you: Enter goes on, r tries it again.")
    lines.append("  - After each take: Enter for the next, r to redo it, s to stop here. Type here, in the terminal" + (windows ? ":" : "."))
    if windows { lines.append("    the windows on the glass never take the keyboard.") }
    lines.append("  - Keep this terminal on the Mac's own display" + (windows ? ": every other display shows a window." : "."))
    lines.append("  - For the takes that need it, this tool holds the touchscreen, and keeps it held between them,")
    lines.append("    so a stray touch on it does nothing.")
    lines.append("  - Ctrl-C stops at any time. The touchscreen is always put back as it was found.")
    return lines
}

/// The terminal line at the start of every take. It names the screen that says TOUCH THIS SCREEN
/// only when windows are shown; with --no-windows, or a target with no screen of its own, it names
/// the display, else the touchscreen.
func waitingLine(stepTimeout: Double, target: DisplayInfo?, product: String?, windowsShown: Bool) -> String {
    let place: String
    if let target {
        let name = target.name ?? "display \(target.displayID)"
        place = windowsShown ? "\(name), the screen that says TOUCH THIS SCREEN" : name
    } else {
        place = product ?? "the touchscreen"
    }
    return "  Waiting up to \(Int(stepTimeout.rounded())) s for your touch on \(place)..."
}

/// The start-of-run note when the chosen display has no screen of its own to draw on.
func noScreenNote(displayName: String) -> [String] {
    ["Note: \(displayName) has no screen of its own to draw on (it shows another display's picture), so nothing",
     "is shown on any display: each take is described here, in the terminal."]
}

/// The terminal line after trying to hold one interface of the touchscreen.
func holdingLine(interface: String, ok: Bool, ioReturn: String) -> String {
    ok ? "  Holding the \(interface) interface for this tool alone: done (IOReturn \(ioReturn))."
       : "  Holding the \(interface) interface for this tool alone: FAILED (IOReturn \(ioReturn)). The recording carries on, shared with macOS: touches may also act on the Mac."
}
