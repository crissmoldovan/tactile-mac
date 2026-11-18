import CoreGraphics
import Foundation

/// How one scroll's deltas, and its momentum's, are posted: each scaled by `scale`, then posted
/// in whole multiples of `step` pixels on each axis, with the rest carried to the next event.
/// Decided once, as the scroll begins, from the app under the pointer (`forApp(_:)`).
public struct ScrollMatch: Equatable, Sendable {
    public let scale: CGFloat
    public let step: CGFloat

    /// As the fingers moved, in whole pixels: every app but the few below.
    public static let asMoved = ScrollMatch(scale: 1, step: 1)

    /// Matched to VS Code's scrolling. For a continuous scroll event of d points, Monaco's
    /// scrollable element moves ceil(1.25 × d) pixels: Chromium hands it the point delta as
    /// `wheelDeltaY` (3 × d), which it divides by 120, multiplies by its sensitivity (1) and by 50,
    /// and rounds up, event by event. Four fifths of the movement, in steps of 4, is exactly the
    /// finger's distance at VS Code's default zoom and sensitivity: every 4 posted moves 5. (Save
    /// 44 and 88 px in one event, which VS Code's own floating point moves one pixel further:
    /// 132 / 120 × 50 is 55.00000000000001. A 120 Hz scroll's events are far smaller.)
    public static let monaco = ScrollMatch(scale: 0.8, step: 4)

    /// The editors built on Monaco, by bundle identifier: the only apps whose scrolls are matched.
    ///
    /// Why: VS Code moves 5 px for every 4 of a continuous scroll's delta and rounds every event up
    /// to a whole pixel, whatever the device. A trackpad's content doesn't sit under a finger, so
    /// nobody sees it; a touchscreen's must, and with small, frequent events it runs up to twice as
    /// fast as the finger. The code, at VS Code 972b66f:
    /// - `StandardWheelEvent` reads `wheelDeltaY / 120`: https://github.com/microsoft/vscode/blob/972b66fdc541e10689adfd90ade9549dea1b18bc/src/vs/base/browser/mouseEvent.ts#L137-L161
    /// - `SCROLL_WHEEL_SENSITIVITY = 50`: https://github.com/microsoft/vscode/blob/972b66fdc541e10689adfd90ade9549dea1b18bc/src/vs/base/browser/ui/scrollbar/scrollableElement.ts#L23
    /// - `_onMouseWheel` scales and rounds each event: https://github.com/microsoft/vscode/blob/972b66fdc541e10689adfd90ade9549dea1b18bc/src/vs/base/browser/ui/scrollbar/scrollableElement.ts#L486-L535
    ///
    /// The identifiers, from public sources: VS Code, Insiders, VSCodium and Windsurf from
    /// VSCodeVim's README, which lists each one's `defaults write <id> ApplePressAndHoldEnabled`
    /// (https://github.com/VSCodeVim/Vim#mac); Cursor from its forum, confirmed by its staff
    /// (https://forum.cursor.com/t/cursor-bundle-identifier/779), built with ToDesktop.
    public static let monacoEditors: Set<String> = [
        "com.microsoft.VSCode",            // Visual Studio Code
        "com.microsoft.VSCodeInsiders",    // Visual Studio Code - Insiders
        "com.vscodium",                    // VSCodium
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf",        // Windsurf
    ]

    /// How a scroll that begins over the app `bundleIdentifier` is posted. No app (none answered in
    /// time) and every app but the editors on Monaco: as moved.
    public static func forApp(_ bundleIdentifier: String?) -> ScrollMatch {
        guard let bundleIdentifier, monacoEditors.contains(bundleIdentifier) else { return .asMoved }
        return .monaco
    }

    /// The debug log's line for a scroll matched over `app`; nil for one posted as moved.
    public func logLine(forApp app: String?) -> String? {
        guard self != .asMoved, let app else { return nil }
        return "scroll in \(app): matched to VS Code's scrolling (x\(scale), steps of \(Int(step)) px)"
    }
}

/// One scroll, or the momentum after it, as it is posted: what to post for each movement, and
/// the part of a step not posted yet, carried to the next.
struct ScrollQuantiser {
    let match: ScrollMatch
    /// Pixels moved but not yet posted, less than one step on each axis, the same way as the
    /// movement that left them.
    private(set) var remainder = CGVector.zero

    init(_ match: ScrollMatch) {
        self.match = match
    }

    /// The pixels to post for `delta`, a movement in points: scaled, with what was carried, in
    /// whole steps toward zero, so never a fraction and never against this movement. `isLast`, the
    /// end of the scroll or of its momentum: what remains is posted as whole steps or not at all,
    /// and nothing is carried on.
    mutating func post(_ delta: CGVector, isLast: Bool) -> CGVector {
        let total = CGVector(dx: delta.dx * match.scale + remainder.dx, dy: delta.dy * match.scale + remainder.dy)
        let whole = CGVector(dx: wholeSteps(of: total.dx), dy: wholeSteps(of: total.dy))
        remainder = isLast ? .zero : CGVector(dx: total.dx - whole.dx, dy: total.dy - whole.dy)
        return whole
    }

    private func wholeSteps(of pixels: CGFloat) -> CGFloat {
        (pixels / match.step).rounded(.towardZero) * match.step
    }
}
