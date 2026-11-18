// Calibration: how a touchscreen's glass is fitted to its display, worked out from a few taps on
// targets the app draws one at a time.

import CoreGraphics
import Foundation

/// One tap during calibration: a target the app drew, and where the touchscreen said the finger was.
public struct CalibrationTap: Equatable, Sendable {
    /// Where the target was drawn, on the display's own unrotated picture: 0…1 on each axis, origin
    /// top-left. The app draws targets as display points; `TouchMapping.nativePoint(forDisplay:)`
    /// gives this from one.
    public var target: CGPoint
    /// Where the touchscreen reported the finger: a glass point, 0…1 on each axis, origin top-left.
    public var glass: CGPoint

    public init(target: CGPoint, glass: CGPoint) {
        self.target = target
        self.glass = glass
    }
}

/// Works out how a touchscreen's glass is fitted to its display, its `Orientation` and its
/// `GlassAlignment`, from taps on known targets.
///
/// For the true orientation and alignment, `orientation.apply(glass)` is `rect.origin + target ×
/// rect.size` on each axis, where `rect` is the alignment's `pictureRect`. So `fit` tries each of
/// the 8 orientations. It applies the orientation to every tap's glass point, and on each axis fits
/// the least-squares line through (target, oriented point). The line's intercept is the rectangle's
/// origin on that axis and its slope is the rectangle's extent.
///
/// A least-squares line can have a negative slope. An orientation followed by a mirror (x becomes
/// 1 − x, y becomes 1 − y, or both) fits any taps exactly as well as the orientation alone: the
/// mirrored axis's line is the same line turned round, and every tap is as far from it as before.
/// The error alone tells only whether the axes are exchanged. So only an orientation whose
/// rectangle has a width and a height within `extents` (0.5…1.5 of the glass) competes, and
/// requiring a positive extent is what tells the 8 apart. Among those that compete, the smallest
/// `error` wins.
///
/// `fit` refuses, rather than return anything doubtful, because a wrong fit would put every later
/// touch in the wrong place:
/// - `tooFewTaps`: fewer than 4.
/// - `tapsDoNotFit`: a tap holds a number that isn't finite; or no orientation competes (that
///   includes taps whose targets don't vary on an axis, which has no line then); or the winner's
///   `error` is above `largestError` (0.04).
/// - `ambiguous`: another competing orientation's `error` is within `ambiguityMargin` (0.02) of
///   the winner's. With the four `targets`, taps that fit one orientation leave the orientations
///   that exchange the axes with extents near 0, so they don't compete. It is for other targets,
///   such as targets along a diagonal, which can't tell whether the axes are exchanged.
///
/// A known limit. The four `targets` sit on a square's corners. When the taps meet the targets in
/// an order that is itself one of the square's symmetries, the taps are, exactly, a calibration of
/// a glass fitted that other way, and fit it perfectly. For example, the targets of two opposite
/// corners exchanged is the square's reflection across the diagonal through the other two corners.
/// Nothing in the taps can tell them apart. The app shows one target at a time, so this takes
/// tapping, twice, where no target is shown. Two neighbouring targets exchanged fit no orientation,
/// and are refused.
///
/// The same taps always give the same answer; nothing traps, and nothing returned holds a number
/// that isn't finite, whatever the taps.
public enum Calibration {
    /// Where the app draws the four targets, one at a time, as display points: the corners of the
    /// picture, 0.12 in from each edge, in the order top-left, top-right, bottom-right, bottom-left.
    public static let targets: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.12), CGPoint(x: 0.88, y: 0.12), CGPoint(x: 0.88, y: 0.88), CGPoint(x: 0.12, y: 0.88),
    ]

    /// How the glass is fitted: what the app stores with the pairing.
    public struct Fit: Equatable, Sendable {
        public var orientation: Orientation
        public var alignment: GlassAlignment
        /// The root-mean-square distance between where the taps land after the fit and their
        /// targets, as a fraction of the glass: on the oriented glass, from each tap's oriented point
        /// to `rect.origin + target × rect.size`.
        public var error: Double

        public init(orientation: Orientation, alignment: GlassAlignment, error: Double) {
            self.orientation = orientation
            self.alignment = alignment
            self.error = error
        }
    }

    /// Why `fit` gave no fit. The app asks for the taps again.
    public enum Failure: Error, Equatable {
        /// Fewer than 4 taps.
        case tooFewTaps
        /// No orientation fits the taps with a believable picture, or the best one leaves the taps
        /// too far from their targets, or a tap holds a number that isn't finite.
        case tapsDoNotFit
        /// Two orientations fit the taps almost equally well.
        case ambiguous
    }

    /// The most `error` a fit may have, as a fraction of the glass.
    static let largestError: Double = 0.04
    /// The widths and heights a competing orientation's rectangle may have, as a share of the
    /// glass: a picture this much smaller or larger than the glass is believable, and a negative
    /// extent, which a mirrored orientation gives, isn't.
    static let extents: ClosedRange<CGFloat> = 0.5...1.5
    /// How much worse than the winner's every other competing orientation's `error` must be.
    static let ambiguityMargin: Double = 0.02

    /// The orientation and alignment of the glass, from `taps`; see `Calibration` for how, and for
    /// when it refuses.
    public static func fit(_ taps: [CalibrationTap]) -> Result<Fit, Failure> {
        guard taps.count >= 4 else { return .failure(.tooFewTaps) }
        guard taps.allSatisfy(isFinite) else { return .failure(.tapsDoNotFit) }
        let competing = everyFit(taps).filter(competes)
        // `min` keeps the first of equals, so ties go the same way every time.
        guard let best = competing.min(by: { $0.error < $1.error }), best.error <= largestError else {
            return .failure(.tapsDoNotFit)
        }
        let rival = competing.contains { $0.orientation != best.orientation && $0.error - best.error <= ambiguityMargin }
        return rival ? .failure(.ambiguous) : .success(best)
    }

    /// Every orientation's least-squares fit of `taps`, competing or not, in `Orientation.allCases`
    /// order. An orientation is left out when an axis has no line (its targets don't vary) or when
    /// a number in its fit isn't finite, as with taps that aren't. Every number in what is listed
    /// is finite.
    static func everyFit(_ taps: [CalibrationTap]) -> [Fit] {
        Orientation.allCases.compactMap { fit(taps, as: $0) }
    }

    /// Whether `fit` competes: its rectangle's width and height are both within `extents`.
    static func competes(_ fit: Fit) -> Bool {
        extents.contains(fit.alignment.pictureRect.size.width) && extents.contains(fit.alignment.pictureRect.size.height)
    }

    // MARK: - Private

    private static func isFinite(_ tap: CalibrationTap) -> Bool {
        tap.target.x.isFinite && tap.target.y.isFinite && tap.glass.x.isFinite && tap.glass.y.isFinite
    }

    /// The fit of `taps` in `orientation`; `nil` when an axis has no line or a number isn't finite.
    private static func fit(_ taps: [CalibrationTap], as orientation: Orientation) -> Fit? {
        let oriented = taps.map { orientation.apply($0.glass) }
        guard
            let x = Line(targets: taps.map { Double($0.target.x) }, oriented: oriented.map { Double($0.x) }),
            let y = Line(targets: taps.map { Double($0.target.y) }, oriented: oriented.map { Double($0.y) })
        else { return nil }
        var squares = 0.0
        for (tap, point) in zip(taps, oriented) {
            let dx = Double(point.x) - x.at(Double(tap.target.x))
            let dy = Double(point.y) - y.at(Double(tap.target.y))
            squares += dx * dx + dy * dy
        }
        let error = (squares / Double(taps.count)).squareRoot()
        guard error.isFinite else { return nil }
        let rect = CGRect(x: x.origin, y: y.origin, width: x.extent, height: y.extent)
        return Fit(orientation: orientation, alignment: GlassAlignment(pictureRect: rect), error: error)
    }
}

/// The least-squares line on one axis: oriented = origin + extent × target.
private struct Line {
    let origin: Double
    let extent: Double

    /// `nil` when the targets don't vary, so there is no line, or when a number in it isn't finite.
    init?(targets: [Double], oriented: [Double]) {
        let count = Double(targets.count)
        let meanTarget = targets.reduce(0, +) / count
        let meanOriented = oriented.reduce(0, +) / count
        var spread = 0.0, together = 0.0
        for (t, o) in zip(targets, oriented) {
            spread += (t - meanTarget) * (t - meanTarget)
            together += (t - meanTarget) * (o - meanOriented)
        }
        // Not a number fails `> 0` too.
        guard spread > 0, spread.isFinite else { return nil }
        let extent = together / spread
        let origin = meanOriented - extent * meanTarget
        guard extent.isFinite, origin.isFinite, (origin + extent).isFinite else { return nil }
        self.origin = origin
        self.extent = extent
    }

    func at(_ target: Double) -> Double {
        origin + extent * target
    }
}
