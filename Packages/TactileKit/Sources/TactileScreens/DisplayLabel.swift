// How Tactile shows a display: in the picker, and in large type on the display itself.

import CoreGraphics
import Foundation

/// A display's label: a name, and a line that tells it apart from the others. Some displays' own
/// names say nothing ("HDMI", "Display"), so Tactile builds its own.
public enum DisplayLabel {

    /// `display`'s label among the connected displays `all`.
    ///
    /// - `name` is `customName` without spaces around it, unless that leaves nothing; otherwise the
    ///   display's own name.
    /// - `detail` is its diagonal, its picture and where it sits, each left out when unknown, joined
    ///   with ` · `: `"27″ · 2560 × 1440 · left of the main display"`.
    ///   - The diagonal is `diagonalInches` when given, else from the reported `sizeMM`, rounded to
    ///     one decimal and the decimal dropped when it is 0: `23.8″`, `27″`. An override that isn't a
    ///     size (not a number, or not above 0 once rounded) counts as not given; a reported size with
    ///     either side zero, or that isn't a size, gives no diagonal.
    ///   - The picture is `frame`'s width × height in points, as the display is turned now.
    ///   - Where it sits: `the main display` for the main one; `built-in` for a built-in one that
    ///     isn't main; otherwise left of, right of, above or below the main display, by the larger
    ///     gap between the two frames' centres, left or right when the gaps are equal. Left out when
    ///     the centres are the same (a display that mirrors the main one), and when `all` doesn't
    ///     hold exactly one main display.
    ///
    /// A frame that isn't one (not finite, or too large to write in whole points) leaves out the
    /// picture and where the display sits.
    public static func label(
        for display: DisplayFacts, among all: [DisplayFacts], customName: String?, diagonalInches: Double?
    ) -> (name: String, detail: String) {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = custom.isEmpty ? display.name : custom
        let parts = [
            diagonal(of: display, override: diagonalInches), picture(of: display), place(of: display, among: all),
        ]
        return (name, parts.compactMap { $0 }.joined(separator: " \u{00B7} "))
    }

    // MARK: - Private

    private static func diagonal(of display: DisplayFacts, override: Double?) -> String? {
        if let override, let text = inches(override) {
            return text
        }
        let size = display.sizeMM
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        return inches(Double(hypot(size.width, size.height)) / 25.4)
    }

    /// `value` in inches to one decimal, the decimal dropped when it is 0: "23.8″", "27″". Nil when
    /// it isn't a size: not a number, not above 0 once rounded, or too large to write.
    private static func inches(_ value: Double) -> String? {
        guard value.isFinite, let tenths = Int(exactly: (value * 10).rounded()), tenths > 0 else { return nil }
        let whole = tenths / 10, decimal = tenths % 10
        return (decimal == 0 ? "\(whole)" : "\(whole).\(decimal)") + "\u{2033}"
    }

    /// "2560 × 1440".
    private static func picture(of display: DisplayFacts) -> String? {
        guard let (width, height) = wholePoints(display.frame) else { return nil }
        return "\(width) \u{00D7} \(height)"
    }

    private static func place(of display: DisplayFacts, among all: [DisplayFacts]) -> String? {
        if display.isMain {
            return "the main display"
        }
        if display.isBuiltIn {
            return "built-in"
        }
        let mains = all.filter(\.isMain)
        guard mains.count == 1, let main = mains.first, wholePoints(main.frame) != nil,
            wholePoints(display.frame) != nil
        else { return nil }

        // y grows downwards.
        let across = display.frame.midX - main.frame.midX
        let down = display.frame.midY - main.frame.midY
        if across == 0, down == 0 {
            return nil
        }
        if abs(across) >= abs(down) {
            return across < 0 ? "left of the main display" : "right of the main display"
        }
        return down < 0 ? "above the main display" : "below the main display"
    }

    /// `frame`'s width and height in whole points, rounded; nil when the frame isn't finite or its
    /// size is too large to write.
    private static func wholePoints(_ frame: CGRect) -> (Int, Int)? {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
            let width = Int(exactly: frame.width.rounded()), let height = Int(exactly: frame.height.rounded())
        else { return nil }
        return (width, height)
    }
}
