import AppKit
import QuartzCore

/// How one circle under a finger is drawn.
public enum TouchCircleStyle: Sendable {
    /// A light disc with a dark rim: a touch Tactile acts on.
    case solid
    /// An outline with nothing inside it: a touch that is seen but not acted on. For touches the
    /// pointer arbiter ignores, such as on a touchscreen while another touchscreen has the
    /// pointer, and for contacts the contact filter refuses, such as a resting palm.
    case hollow
    /// A solid circle with a thin second ring outside it: lifting this finger now will right-click.
    case ringed

    /// The style for a finger: hollow if it is seen but not acted on, ringed if lifting it will
    /// right-click, otherwise solid. A hollow finger gets no ring: a touch Tactile doesn't act on
    /// can't right-click.
    public init(hollow: Bool, ringed: Bool) {
        self = hollow ? .hollow : ringed ? .ringed : .solid
    }
}

/// One circle as drawn: where it is on the overlay's window, and its style.
struct TouchCircle: Equatable {
    var position: CGPoint
    var style: TouchCircleStyle
}

/// What one touch report changes about the circles drawn, from what each was last drawn as. A circle
/// whose finger is where it was, in the style it had, is in none of these: a finger held still
/// changes nothing.
struct TouchCircleChanges: Equatable {
    /// The circles of fingers that came down.
    private(set) var added: [Int: TouchCircle] = [:]
    /// Where the circles of fingers that moved go. Positions are compared exactly, so any move at
    /// all is drawn.
    private(set) var moved: [Int: CGPoint] = [:]
    /// The new style of each circle whose style changed.
    private(set) var restyled: [Int: TouchCircleStyle] = [:]
    /// The fingers that lifted: their circles fade out.
    private(set) var lifted: Set<Int> = []

    init(from drawn: [Int: TouchCircle], to frame: [Int: TouchCircle]) {
        for (id, circle) in frame {
            guard let was = drawn[id] else {
                added[id] = circle
                continue
            }
            if circle.position != was.position { moved[id] = circle.position }
            if circle.style != was.style { restyled[id] = circle.style }
        }
        for id in drawn.keys where frame[id] == nil {
            lifted.insert(id)
        }
    }

    var isEmpty: Bool { added.isEmpty && moved.isEmpty && restyled.isEmpty && lifted.isEmpty }
}

/// A click-through window over one touchscreen that draws a circle under each finger.
/// Main thread only.
@MainActor
public final class TouchCircleOverlay {
    /// Readable from any thread: `TouchCircleStyle` draws its paths from it.
    public nonisolated static let diameter: CGFloat = 44

    /// A circle on the window: its layer, and what it was last drawn as.
    private struct Circle {
        let layer: CAShapeLayer
        var drawn: TouchCircle
    }

    private var window: NSWindow?
    /// The circles on `window`, by contact ID.
    private var circles: [Int: Circle] = [:]
    /// Makes each circle's layer. Tests pass one that records what is written to it.
    private let makeLayer: () -> CAShapeLayer

    public convenience init() {
        self.init(makeLayer: { CAShapeLayer() })
    }

    init(makeLayer: @escaping () -> CAShapeLayer) {
        self.makeLayer = makeLayer
    }

    /// Shows a circle at each finger and fades out the circles of fingers that lifted. Only what
    /// changed is drawn: a circle whose finger hasn't moved or changed style is left alone, and a
    /// report that changes nothing, such as one during a still hold, does nothing on screen.
    /// - Parameters:
    ///   - fingers: contact ID to location relative to the display (0…1, origin at the top left).
    ///   - hollow: the contact IDs to draw hollow; every other finger is drawn solid, in the same
    ///     call. A finger can change between the two while it is down.
    ///   - ringed: the contact IDs whose circle carries a ring outside it, because lifting that
    ///     finger now will right-click (the engine's `longPressReady`). The ring fades in over about
    ///     0.1 s. A finger that is also hollow gets no ring.
    ///   - screen: the touchscreen's display.
    public func show(fingers: [Int: CGPoint], hollow: Set<Int> = [], ringed: Set<Int> = [], on screen: NSScreen) {
        guard let root = window(on: screen).contentView?.layer else { return }
        draw(fingers: fingers, hollow: hollow, ringed: ringed, in: root)
    }

    /// `show`'s drawing, on `root`: the window's content layer, or in tests a layer never on screen.
    func draw(fingers: [Int: CGPoint], hollow: Set<Int>, ringed: Set<Int>, in root: CALayer) {
        let size = root.bounds.size
        var frame: [Int: TouchCircle] = [:]
        for (id, location) in fingers {
            frame[id] = TouchCircle(position: CGPoint(x: location.x * size.width, y: (1 - location.y) * size.height),
                                    style: TouchCircleStyle(hollow: hollow.contains(id), ringed: ringed.contains(id)))
        }
        let changes = TouchCircleChanges(from: circles.mapValues(\.drawn), to: frame)
        // Nothing changed: no transaction, nothing written to a layer, so the window isn't redrawn.
        guard !changes.isEmpty else { return }

        // Each lifted circle fades in a transaction of its own.
        for id in changes.lifted {
            if let lifted = circles.removeValue(forKey: id) { fadeOut(lifted.layer) }
        }
        guard !(changes.added.isEmpty && changes.moved.isEmpty && changes.restyled.isEmpty) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, circle) in changes.added {
            let layer = makeCircle(in: root)
            layer.position = circle.position
            circle.style.apply(to: layer)
            circles[id] = Circle(layer: layer, drawn: circle)
        }
        for (id, position) in changes.moved {
            guard let circle = circles[id] else { continue }
            circle.layer.position = position
            circles[id]?.drawn.position = position
        }
        for (id, style) in changes.restyled {
            guard let circle = circles[id] else { continue }
            style.apply(to: circle.layer)
            circles[id]?.drawn.style = style
        }
        CATransaction.commit()
    }

    /// Fades out every circle.
    public func clear() {
        circles.values.forEach { fadeOut($0.layer) }
        circles.removeAll()
    }

    /// Takes the overlay down: orders its window out and releases it, with every circle on it.
    /// A later `show` opens a new window.
    public func close() {
        window?.orderOut(nil)
        window = nil
        circles.removeAll()
    }

    private func window(on screen: NSScreen) -> NSWindow {
        if let window, window.frame == screen.frame { return window }
        // The screen changed. The old window goes with its circles, so fingers already down get
        // new circles on the new window.
        close()
        let overlay = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.setFrame(screen.frame, display: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        overlay.contentView = content
        overlay.orderFrontRegardless()
        window = overlay
        return overlay
    }

    private func makeCircle(in root: CALayer) -> CAShapeLayer {
        let layer = makeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        TouchCircleStyle.castShadow(on: layer)
        root.addSublayer(layer)
        return layer
    }

    private func fadeOut(_ layer: CAShapeLayer) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.opacity = 0
        CATransaction.commit()
    }
}

extension TouchCircleStyle {
    private static let bounds = CGRect(x: 0, y: 0, width: TouchCircleOverlay.diameter, height: TouchCircleOverlay.diameter)

    /// The whole circle.
    private static let disc = CGPath(ellipseIn: bounds.insetBy(dx: 2, dy: 2), transform: nil)

    /// The circle's edge and a smaller circle inside it. Filled even-odd, only the narrow band
    /// between the two is painted; the inside stays empty.
    private static let ring: CGPath = {
        let path = CGMutablePath()
        path.addEllipse(in: bounds.insetBy(dx: 2, dy: 2))
        path.addEllipse(in: bounds.insetBy(dx: 5.5, dy: 5.5))
        return path
    }()

    /// The name of the sublayer that draws a ringed circle's outer ring.
    static let ringName = "ring"

    /// A narrow band outside the circle, with a gap between them: two circles 52 and 58 pt across,
    /// filled even-odd.
    private static let outerRing: CGPath = {
        let path = CGMutablePath()
        path.addEllipse(in: bounds.insetBy(dx: -7, dy: -7))
        path.addEllipse(in: bounds.insetBy(dx: -4, dy: -4))
        return path
    }()

    /// How long the outer ring takes to appear.
    private static let ringAppearance: CFTimeInterval = 0.1

    private static let lightFill = NSColor.white.withAlphaComponent(0.35).cgColor
    private static let lightBand = NSColor.white.withAlphaComponent(0.85).cgColor
    private static let darkRim = NSColor.black.withAlphaComponent(0.4).cgColor
    /// The dark rim's width, stroked on the edge of each shape.
    private static let rimWidth: CGFloat = 1.5

    // MARK: Shadows
    //
    // Each shape casts its shadow from a path of itself, out to the outer edge of its rim. Without a
    // path, Core Animation works a shadow out from what the layer draws, in an offscreen pass, every
    // time it draws the layer. A shadow path is filled with the non-zero rule, so a band's inner
    // circle runs the other way round, and the inside of the band casts no shadow.
    //
    // The shadow worked out from what a layer draws is as dark as that paint is opaque: 0.25 black
    // under paint about 0.35 opaque for a disc, 0.85 for a band. A path's shadow is evenly dark, so
    // each opacity below is the one at which the path's shadow matches the old one: rendered offscreen
    // both ways, within 4/255 on white, on mid grey and on black.

    /// The disc's shadow.
    private static let discShadow = CGPath(ellipseIn: bounds.insetBy(dx: 2 - rimWidth / 2, dy: 2 - rimWidth / 2),
                                           transform: nil)
    /// The outline's shadow: its band, with nothing inside.
    private static let ringShadow = band(outer: bounds.insetBy(dx: 2 - rimWidth / 2, dy: 2 - rimWidth / 2),
                                         inner: bounds.insetBy(dx: 5.5 + rimWidth / 2, dy: 5.5 + rimWidth / 2))
    /// The outer ring's shadow: its band, with nothing inside.
    private static let outerRingShadow = band(outer: bounds.insetBy(dx: -7 - rimWidth / 2, dy: -7 - rimWidth / 2),
                                              inner: bounds.insetBy(dx: -4 + rimWidth / 2, dy: -4 + rimWidth / 2))
    private static let discShadowOpacity: Float = 0.09
    private static let bandShadowOpacity: Float = 0.18

    /// A circle `outer` with a circle `inner` running the other way round inside it.
    private static func band(outer: CGRect, inner: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: outer)
        // Mirrored left to right about its centre, the same circle runs the other way round.
        path.addEllipse(in: inner, transform: CGAffineTransform(translationX: 2 * inner.midX, y: 0).scaledBy(x: -1, y: 1))
        return path
    }

    /// Gives `layer` the shadow every shape casts: black, soft over 3 pt, straight under it. What
    /// it is cast from, and how dark, is set by the shape.
    static func castShadow(on layer: CALayer) {
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = 3
        layer.shadowOffset = .zero
    }

    /// Sets everything the styles draw differently, shadow included, so a circle can change style
    /// while its finger is down. Light paint edged with dark shows up on both light and dark content.
    func apply(to layer: CAShapeLayer) {
        switch self {
        case .solid, .ringed:
            // A light fill with a dark rim.
            layer.path = Self.disc
            layer.fillRule = .nonZero
            layer.fillColor = Self.lightFill
            layer.shadowPath = Self.discShadow
            layer.shadowOpacity = Self.discShadowOpacity
        case .hollow:
            // An outline only: a light band with a dark rim on each side, and no fill inside it.
            layer.path = Self.ring
            layer.fillRule = .evenOdd
            layer.fillColor = Self.lightBand
            layer.shadowPath = Self.ringShadow
            layer.shadowOpacity = Self.bandShadowOpacity
        }
        layer.strokeColor = Self.darkRim
        layer.lineWidth = Self.rimWidth
        setOuterRing(on: layer)
    }

    /// Adds the outer ring, fading it in, when this style has one and the circle hasn't; takes it
    /// away at once when this style has none.
    private func setOuterRing(on layer: CAShapeLayer) {
        let existing = layer.sublayers?.first { $0.name == Self.ringName }
        guard self == .ringed else {
            existing?.removeFromSuperlayer()
            return
        }
        guard existing == nil else { return }
        let ring = CAShapeLayer()
        ring.name = Self.ringName
        ring.frame = layer.bounds
        ring.path = Self.outerRing
        ring.fillRule = .evenOdd
        ring.fillColor = Self.lightBand
        ring.strokeColor = Self.darkRim
        ring.lineWidth = Self.rimWidth
        // Its own shadow: the circle's shadow path covers the circle alone.
        Self.castShadow(on: ring)
        ring.shadowPath = Self.outerRingShadow
        ring.shadowOpacity = Self.bandShadowOpacity
        layer.addSublayer(ring)
        // An explicit animation, so it runs even where implicit ones are switched off.
        let appear = CABasicAnimation(keyPath: "opacity")
        appear.fromValue = 0.0
        appear.toValue = 1.0
        appear.duration = Self.ringAppearance
        ring.add(appear, forKey: "appear")
    }
}
