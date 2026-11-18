// The path of a point, from a touchscreen's glass to the desktop.

import CoreGraphics
import Foundation

/// The path of a point from one touchscreen's glass to the desktop, while its display is as
/// `display` says. It is built again when the pairing, the fit or the display changes, then used for
/// every finger of every frame: each call is a little arithmetic and allocates nothing.
///
/// 1. **Orientation.** `orientation.apply`.
/// 2. **Alignment.** x becomes (x − rect.minX) ÷ rect.width, y likewise, each clamped to 0…1. The
///    point is now on the display's own unrotated picture, which fills its panel.
/// 3. **macOS rotation.** `rotate(_:by:)` by `display.rotation`: onto the panel as macOS has turned
///    it.
/// 4. **Mirroring.** When `content` is given, its picture is fitted inside this panel and centred,
///    with bars on the other axis; the point is rescaled into it and clamped to 0…1. That gives the
///    display point. Then the desktop, through the frame of `content ?? display`.
///
/// The letterbox compares the panel, as macOS has turned it, with the content's frame. `glassAspect`
/// is `display.nativePixels`' width ÷ height, and its height ÷ width when the display is turned 90°
/// or 270°: the native size is unrotated, while step 3 has already turned the point (as the frame
/// is). `contentAspect` is `content.frame`'s width ÷ height. When `contentAspect ≥ glassAspect` the
/// picture fills the width and `glassAspect ÷ contentAspect` of the height; otherwise it fills the
/// height and `contentAspect ÷ glassAspect` of the width. Pictures of the same shape have no bars.
///
/// A desktop point stays on its display: a frame holds its left and top edges but not its right and
/// bottom ones, which belong to whatever display lies beyond. So the far edges are kept one point
/// inside. Without that, on the desk, a touch at the very bottom of the display above the main one
/// would land on the main display's menu bar.
///
/// There is no mapping for a display with nowhere for a touch to land: the initialiser fails when
/// the frame of `content ?? display` isn't finite (its origin, its size or its far corner) or has
/// no area (a width or height that is zero or negative). A display that has just gone away can
/// report exactly that, and no mapping means no touches: any point would be on another display. It
/// fails too when the frame's origin or far corner is more than 1,000,000 points from the desktop's
/// origin on either axis (`desktopReach`): no display's frame is, and points on it would mean
/// nothing (`CGRect.infinite` would put the middle of the glass at (0, 0)).
///
/// Otherwise nothing traps or gives a point that isn't finite, whatever it is given:
/// - Where a step clamps to 0…1, a coordinate that isn't a number counts as 0. Display and native
///   points are always 0…1, and desktop points on the frame.
/// - An alignment rectangle that isn't one (see `GlassAlignment`) maps as the whole glass.
/// - A rotation is taken modulo 360; one that isn't then 0, 90, 180 or 270 is 0.
/// - A letterbox that can't be worked out is none: a native size with a width or height that is
///   zero, negative or not finite, or two shapes so far apart that their ratio, or the picture's
///   share of the panel, can't be written as a number above zero.
/// - A frame less than a point across puts every point at its origin.
public struct TouchMapping: Equatable, Sendable {
    public let orientation: Orientation
    public let alignment: GlassAlignment
    /// The display the touchscreen's glass sits on.
    public let display: DisplayFacts
    /// The display whose picture `display` shows, when it mirrors another; `nil` otherwise.
    public let content: DisplayFacts?

    /// The alignment's rectangle, or the whole glass when it isn't one: finite, with a positive size.
    private let picture: CGRect
    /// The macOS rotation, in quarter turns: 0…3.
    private let turns: Int
    /// Where the content's picture is on the panel as macOS has turned it; the whole panel when
    /// there are no bars. Inside 0…1, with a positive size.
    private let shown: CGRect
    /// Where display points go on the desktop: finite, with an area.
    private let desktop: CGRect
    /// The last point on the desktop frame, one point in from its far corner; its origin when the
    /// frame is smaller than a point.
    private let lastPoint: CGPoint

    /// `content` is the display whose picture `display` shows when it mirrors another; `nil`
    /// otherwise. `nil` when the frame of `content ?? display` isn't finite, has no area, or reaches
    /// beyond `desktopReach`: there is nowhere for a touch to land.
    public init?(orientation: Orientation, alignment: GlassAlignment, display: DisplayFacts, content: DisplayFacts?) {
        let desktop = (content ?? display).frame
        guard Self.hasArea(desktop), Self.isWithinReach(desktop) else { return nil }
        self.desktop = desktop
        lastPoint = CGPoint(
            x: max(desktop.origin.x, desktop.origin.x + desktop.size.width - 1),
            y: max(desktop.origin.y, desktop.origin.y + desktop.size.height - 1))
        self.orientation = orientation
        self.alignment = alignment
        self.display = display
        self.content = content
        let turns = Self.quarterTurns(degrees: display.rotation)
        self.turns = turns
        picture = Self.hasArea(alignment.pictureRect) ? alignment.pictureRect : Self.whole
        if let content {
            shown = Self.letterbox(native: display.nativePixels, quarterTurns: turns, content: content.frame)
        } else {
            shown = Self.whole
        }
    }

    /// A glass point on the picture: steps 1 to 3 and the letterbox. 0…1 on each axis, origin
    /// top-left; this is what the gesture engine is given.
    public func displayPoint(forGlass p: CGPoint) -> CGPoint {
        let oriented = orientation.apply(p)
        let aligned = CGPoint(
            x: Self.clamped((oriented.x - picture.origin.x) / picture.size.width),
            y: Self.clamped((oriented.y - picture.origin.y) / picture.size.height))
        let turned = Orientation.turned(aligned, quarterTurns: turns)
        return CGPoint(
            x: Self.clamped((turned.x - shown.origin.x) / shown.size.width),
            y: Self.clamped((turned.y - shown.origin.y) / shown.size.height))
    }

    /// A display point on the global desktop, through the frame of `content ?? display`: x becomes
    /// frame.minX + x × frame.width, y likewise. The point is clamped to 0…1 first, and the result
    /// is kept at least one point inside the frame's right and bottom edges, which belong to the
    /// display beyond.
    public func desktopPoint(forDisplay p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(desktop.origin.x + Self.clamped(p.x) * desktop.size.width, lastPoint.x),
            y: min(desktop.origin.y + Self.clamped(p.y) * desktop.size.height, lastPoint.y))
    }

    /// A display point back through the letterbox and the macOS rotation, onto the display's own
    /// unrotated picture: where step 2 put a glass point that `displayPoint` maps to `p`. The point
    /// is clamped to 0…1 first. Calibration uses it to know where on the picture a target was drawn.
    ///
    /// It can't undo a clamp. A glass point off the picture, or on a letterbox bar, became a display
    /// point on the picture's edge, and comes back as that edge, not as where the finger was.
    public func nativePoint(forDisplay p: CGPoint) -> CGPoint {
        let onPanel = CGPoint(
            x: shown.origin.x + Self.clamped(p.x) * shown.size.width,
            y: shown.origin.y + Self.clamped(p.y) * shown.size.height)
        return Orientation.turned(onPanel, quarterTurns: 4 - turns)
    }

    /// `p` on a display that macOS has rotated by `degrees`: 0 leaves it; 90 gives (1 − y, x); 180
    /// gives (1 − x, 1 − y); 270 gives (y, 1 − x). The mapping the app has always used for a rotated
    /// display.
    ///
    /// `degrees` is taken modulo 360, so −90 is 270 and 450 is 90; one that isn't then 0, 90, 180 or
    /// 270 leaves the point, as 0 does. Exact and unclamped: a finite point gives a finite point.
    public static func rotate(_ p: CGPoint, by degrees: Int) -> CGPoint {
        Orientation.turned(p, quarterTurns: quarterTurns(degrees: degrees))
    }

    /// How far from the desktop's origin, in points, a frame touches land on may reach on each axis,
    /// at its origin and at its far corner. No arrangement of displays comes near it.
    static let desktopReach: CGFloat = 1_000_000

    // MARK: - Private

    private static let whole = GlassAlignment.wholeGlass.pictureRect

    /// Whether `rect`'s origin and far corner are within `desktopReach` of the desktop's origin on
    /// each axis. `rect` has an area (the initialiser has checked), so it is finite.
    private static func isWithinReach(_ rect: CGRect) -> Bool {
        let farX = rect.origin.x + rect.size.width, farY = rect.origin.y + rect.size.height
        return abs(rect.origin.x) <= desktopReach && abs(rect.origin.y) <= desktopReach
            && abs(farX) <= desktopReach && abs(farY) <= desktopReach
    }

    /// `degrees` modulo 360, in quarter turns (0…3); 0 when it isn't a whole number of them. `& 3` is
    /// modulo 4 for negative numbers too: −90° is −1 turn, which is 3.
    private static func quarterTurns(degrees: Int) -> Int {
        degrees % 90 == 0 ? (degrees / 90) & 3 : 0
    }

    /// Whether `rect` is a rectangle with an area: its origin, size and far corner finite, its width
    /// and height above zero.
    private static func hasArea(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite
            && (rect.origin.x + rect.size.width).isFinite && (rect.origin.y + rect.size.height).isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }

    /// Where a picture with `content`'s shape falls on a panel `native` pixels in size, unrotated,
    /// that macOS has turned `quarterTurns` times: fitted inside it and centred. `content` has an
    /// area (the initialiser has checked). The whole panel when either shape can't be worked out.
    private static func letterbox(native: CGSize, quarterTurns: Int, content: CGRect) -> CGRect {
        guard native.width.isFinite, native.height.isFinite, native.width > 0, native.height > 0 else { return whole }
        let glassAspect = quarterTurns & 1 == 1 ? native.height / native.width : native.width / native.height
        let contentAspect = content.size.width / content.size.height
        let width = contentAspect >= glassAspect ? 1 : contentAspect / glassAspect
        let height = contentAspect >= glassAspect ? glassAspect / contentAspect : 1
        // Sides that are each fine can still have a ratio that overflows or underflows to 0. Then the
        // picture's share of the panel is 0 or not a number (∞ ÷ ∞, 0 ÷ 0), and fails this.
        guard width > 0, height > 0 else { return whole }
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// `value` brought into 0…1; NaN counts as 0.
    private static func clamped(_ value: CGFloat) -> CGFloat {
        value >= 1 ? 1 : (value > 0 ? value : 0)
    }
}
