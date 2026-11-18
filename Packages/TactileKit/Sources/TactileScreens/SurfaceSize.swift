// The size of a touchscreen's glass in millimetres, which every frame of touches carries.

import CoreGraphics
import Foundation

/// The size of a touchscreen's glass in millimetres. The gesture engine's thresholds are distances
/// on the glass (a finger must move 3 mm to count as moving, a swipe must travel 30 mm), so every
/// frame of touches carries this. The glass covers its display's picture, so it is the picture's
/// size, in the same orientation as the display's `frame`.
///
/// It comes from, in order:
/// 1. **A diagonal the person has confirmed**, in inches, when it is 3 to 200 inches
///    (`plausibleDiagonals`): a rectangle with the shape of `frame` and that diagonal. Displays can
///    report the wrong size. On the desk, "HDMI" reports 602 × 329 mm, 27.0″, and is 23.8″;
///    "12.3FHD" reports 240 × 90 mm, 10.1″, and is 12.3″. Both are plausible, so only the person can
///    correct them.
/// 2. **The size the display reports**, `sizeMM`, when both its sides are above zero and the
///    densities it implies are both 50 to 400 points per inch: across, `frame` width ÷ (`sizeMM`
///    width ÷ 25.4), and down, `frame` height ÷ (`sizeMM` height ÷ 25.4). `sizeMM` is taken to be in
///    the orientation of `frame`, turned with it when macOS rotates the display.
/// 3. **96 points per inch**: `frame` width × 25.4 ÷ 96 by `frame` height × 25.4 ÷ 96.
///
/// A rule that can't give a size whose sides are both finite and above zero is passed over. So a
/// diagonal outside 3 to 200 inches, or not a number, is ignored, and the next rule applies.
///
/// A frame with a side that is zero, negative or not finite has no shape for rule 1 and no density
/// for rule 2, and rule 3 would give no size. Its answer is the fixed `fallback`, 508 × 285.75 mm:
/// 96 points per inch on a 1920 × 1080 picture, a common one, about 23″. Such a display
/// gets no `TouchMapping`, so no touch on it reaches the engine; the size only has to be one the
/// engine can divide by, and an ordinary one is the least surprising. The same size is the answer
/// when the frame is so large or so small that rule 3 overflows or comes to zero.
///
/// `millimetres` never returns a side that is zero, negative or not finite, whatever it is given.
public enum SurfaceSize {
    /// The diagonals, in inches, that rule 1 uses: no touchscreen's glass is smaller or larger. The
    /// app lets a person confirm a diagonal only in this range.
    public static let plausibleDiagonals: ClosedRange<Double> = 3...200
    /// Millimetres in an inch.
    static let millimetresPerInch: Double = 25.4
    /// The densities, in points per inch, at which a reported size is believed. The desk's five
    /// displays, by the sizes they report, run from 108 ("HDMI") to 173 (the built-in one).
    static let plausibleDensities: ClosedRange<Double> = 50...400
    /// The density, in points per inch, assumed when nothing better is known.
    static let assumedDensity: Double = 96
    /// The picture, in points, whose size at `assumedDensity` is the answer for a frame with no
    /// usable size.
    static let fallbackPicture = CGSize(width: 1920, height: 1080)
    /// The answer for a frame with no usable size: `fallbackPicture` at `assumedDensity`,
    /// 508 × 285.75 mm.
    static let fallback = atAssumedDensity(fallbackPicture)

    /// The size of `display`'s picture in millimetres, in the same orientation as its `frame`; see
    /// `SurfaceSize` for the rules. `diagonalInches` is the diagonal the person has confirmed, or
    /// `nil` when there is none. Both sides are always finite and above zero.
    public static func millimetres(display: DisplayFacts, diagonalInches: Double?) -> CGSize {
        let frame = display.frame.size
        guard isUsable(frame) else { return fallback }
        if let diagonalInches, let size = rectangle(shapedLike: frame, diagonalInches: diagonalInches) {
            return size
        }
        if isPlausible(display.sizeMM, across: frame) {
            return display.sizeMM
        }
        let assumed = atAssumedDensity(frame)
        return isUsable(assumed) ? assumed : fallback
    }

    /// The diagonal of `size`, a size in millimetres, in inches. Not finite when a side isn't.
    public static func diagonalInches(of size: CGSize) -> Double {
        hypot(Double(size.width), Double(size.height)) / millimetresPerInch
    }

    // MARK: - Private

    /// Whether both sides of `size` are finite and above zero.
    private static func isUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    /// Rule 1: a rectangle with the shape of `frame`, which is usable, and a diagonal of
    /// `diagonalInches`; `nil` when the diagonal is outside `plausibleDiagonals`, or the rectangle
    /// has a side that isn't finite and above zero.
    private static func rectangle(shapedLike frame: CGSize, diagonalInches: Double) -> CGSize? {
        // Not a number is outside the range.
        guard plausibleDiagonals.contains(diagonalInches) else { return nil }
        // The shape with its longer side 1, so that working out its diagonal can't overflow.
        let longer = Double(max(frame.width, frame.height))
        let width = Double(frame.width) / longer, height = Double(frame.height) / longer
        let scale = diagonalInches * millimetresPerInch / (width * width + height * height).squareRoot()
        let size = CGSize(width: width * scale, height: height * scale)
        return isUsable(size) ? size : nil
    }

    /// Rule 2: whether `sizeMM` has both sides finite and above zero, and the densities it implies
    /// across and down `frame` are both in `plausibleDensities`.
    private static func isPlausible(_ sizeMM: CGSize, across frame: CGSize) -> Bool {
        guard isUsable(sizeMM) else { return false }
        let across = Double(frame.width) / (Double(sizeMM.width) / millimetresPerInch)
        let down = Double(frame.height) / (Double(sizeMM.height) / millimetresPerInch)
        // Not a number, and infinity, are outside the range.
        return plausibleDensities.contains(across) && plausibleDensities.contains(down)
    }

    /// Rule 3: `frame`, in points, at `assumedDensity`, in millimetres.
    private static func atAssumedDensity(_ frame: CGSize) -> CGSize {
        CGSize(
            width: Double(frame.width) * millimetresPerInch / assumedDensity,
            height: Double(frame.height) * millimetresPerInch / assumedDensity)
    }
}
