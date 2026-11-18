import AppKit
import QuartzCore
import XCTest
@testable import TactileOutput

/// The overlay drawing circles on a bare root layer that is never put in a window: nothing here
/// opens one. The root stands for the overlay window's content, 1000 × 500 pt. Each circle's layer
/// records every write to it.
///
/// Off screen, a transaction that commits ends its animations at once. A test that reads an
/// animation holds a transaction open around the drawing, as an open transaction does until the
/// run loop turns.
@MainActor
final class TouchCircleOverlayTests: XCTestCase {
    private let overlay = TouchCircleOverlay(makeLayer: { RecordingLayer() })
    private let root: RecordingLayer = {
        let layer = RecordingLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
        layer.writes = []
        return layer
    }()

    /// A finger at (0.25, 0.5) and one at (0.5, 0.1) on the display, and where their circles go.
    private let left = CGPoint(x: 0.25, y: 0.5), leftOnRoot = CGPoint(x: 250, y: 250)
    private let top = CGPoint(x: 0.5, y: 0.1), topOnRoot = CGPoint(x: 500, y: 450)

    private var circles: [RecordingLayer] { root.sublayers?.compactMap { $0 as? RecordingLayer } ?? [] }

    private func circle(at position: CGPoint) -> RecordingLayer? {
        circles.first { $0.position == position && $0.opacity > 0 }
    }

    private func rings(of layer: CALayer) -> [CALayer] {
        layer.sublayers?.filter { $0.name == TouchCircleStyle.ringName } ?? []
    }

    func testANewFingerGetsACircleUnderItWithAShadowPathOfItsDisc() throws {
        overlay.draw(fingers: [1: left], hollow: [], ringed: [], in: root)

        XCTAssertEqual(circles.count, 1)
        let circle = try XCTUnwrap(circle(at: leftOnRoot))
        let shadow = try XCTUnwrap(circle.shadowPath, "no shadow path: Core Animation works the shadow out offscreen")
        let disc = try XCTUnwrap(circle.path)
        XCTAssertTrue(shadow.contains(CGPoint(x: circle.bounds.midX, y: circle.bounds.midY)))
        // Out to the outer edge of the rim, which is stroked on the disc's edge.
        XCTAssertEqual(shadow.boundingBox, disc.boundingBox.insetBy(dx: -circle.lineWidth / 2, dy: -circle.lineWidth / 2))
        XCTAssertEqual(circle.shadowRadius, 3)
        XCTAssertEqual(circle.shadowOffset, .zero)
        XCTAssertEqual(circle.shadowColor, NSColor.black.cgColor)
        XCTAssertGreaterThan(circle.shadowOpacity, 0)
    }

    func testAStillHoldWritesNothingToAnyLayer() throws {
        let fingers = [1: left, 2: top]
        overlay.draw(fingers: fingers, hollow: [2], ringed: [1], in: root)
        let ringed = try XCTUnwrap(circle(at: leftOnRoot)), hollow = try XCTUnwrap(circle(at: topOnRoot))
        let ring = try XCTUnwrap(rings(of: ringed).first)
        let layersBefore = (root.sublayers ?? []).map(ObjectIdentifier.init)
        for layer in [root, ringed, hollow] { layer.writes = [] }

        for _ in 0..<5 {
            overlay.draw(fingers: fingers, hollow: [2], ringed: [1], in: root)
        }

        XCTAssertEqual(root.writes, [])
        XCTAssertEqual(ringed.writes, [], "the ringed circle")
        XCTAssertEqual(hollow.writes, [], "the hollow circle")
        XCTAssertEqual((root.sublayers ?? []).map(ObjectIdentifier.init), layersBefore)
        XCTAssertEqual(rings(of: ringed).count, 1)
        XCTAssertTrue(rings(of: ringed).first === ring)
    }

    func testAMovedFingerMovesOnlyItsCircle() throws {
        overlay.draw(fingers: [1: left, 2: top], hollow: [], ringed: [], in: root)
        let moving = try XCTUnwrap(circle(at: leftOnRoot)), still = try XCTUnwrap(circle(at: topOnRoot))
        for layer in [root, moving, still] { layer.writes = [] }

        overlay.draw(fingers: [1: CGPoint(x: 0.3, y: 0.6), 2: top], hollow: [], ringed: [], in: root)

        XCTAssertEqual(moving.writes, ["position"])
        XCTAssertEqual(still.writes, [])
        XCTAssertEqual(root.writes, [])
        XCTAssertEqual(moving.position.x, 300, accuracy: 1e-9)
        XCTAssertEqual(moving.position.y, 200, accuracy: 1e-9)
        XCTAssertEqual(still.position, topOnRoot)
    }

    func testTurningRingedAddsTheRingOnceAndTurningSolidTakesItAway() throws {
        overlay.draw(fingers: [1: left], hollow: [], ringed: [], in: root)
        let circle = try XCTUnwrap(circle(at: leftOnRoot))
        XCTAssertEqual(rings(of: circle).count, 0)

        CATransaction.begin()
        overlay.draw(fingers: [1: left], hollow: [], ringed: [1], in: root)
        let ring = try XCTUnwrap(rings(of: circle).first)
        let appear = ring.animation(forKey: "appear") as? CABasicAnimation
        XCTAssertEqual(appear?.keyPath, "opacity", "the ring fades in")
        XCTAssertEqual(appear?.duration ?? 0, 0.1, accuracy: 0.001)
        ring.removeAllAnimations()
        // Staying ringed, still or moving, keeps that one ring and does not fade it in again.
        overlay.draw(fingers: [1: left], hollow: [], ringed: [1], in: root)
        overlay.draw(fingers: [1: CGPoint(x: 0.3, y: 0.5)], hollow: [], ringed: [1], in: root)
        XCTAssertEqual(rings(of: circle).count, 1)
        XCTAssertTrue(rings(of: circle).first === ring)
        XCTAssertNil(ring.animationKeys())
        CATransaction.commit()

        overlay.draw(fingers: [1: CGPoint(x: 0.3, y: 0.5)], hollow: [], ringed: [], in: root)
        XCTAssertEqual(rings(of: circle).count, 0)
        XCTAssertNil(ring.superlayer)
    }

    func testALiftedFingerFadesOutAndTheOthersStay() throws {
        overlay.draw(fingers: [1: left, 2: top], hollow: [], ringed: [], in: root)
        let staying = try XCTUnwrap(circle(at: leftOnRoot)), lifted = try XCTUnwrap(circle(at: topOnRoot))
        for layer in [staying, lifted] { layer.writes = [] }

        overlay.draw(fingers: [1: left], hollow: [], ringed: [], in: root)

        XCTAssertEqual(lifted.opacity, 0)
        // Animated: Core Animation looked for the change's animation, in a 0.2 s transaction.
        let fade = try XCTUnwrap(lifted.animated.first { $0.key == "opacity" })
        XCTAssertEqual(fade.duration, 0.2, accuracy: 0.001)
        XCTAssertEqual(staying.writes, [])
        XCTAssertEqual(staying.opacity, 1)

        // The same contact ID down again is a new touch: it gets a new circle.
        overlay.draw(fingers: [1: left, 2: top], hollow: [], ringed: [], in: root)
        let again = try XCTUnwrap(circle(at: topOnRoot))
        XCTAssertFalse(again === lifted)
    }

    func testAfterClearingTheSameFingersGetNewCircles() throws {
        overlay.draw(fingers: [1: left], hollow: [], ringed: [], in: root)
        let first = try XCTUnwrap(circle(at: leftOnRoot))

        overlay.clear()
        XCTAssertEqual(first.opacity, 0)
        overlay.draw(fingers: [1: left], hollow: [], ringed: [], in: root)

        let second = try XCTUnwrap(circle(at: leftOnRoot))
        XCTAssertFalse(second === first)
    }
}

/// A layer that records every write to the properties a circle is drawn with, and every sublayer
/// added to it. A write is recorded even when it sets the value the layer already has, which
/// key-value observing on a layer does not report.
private final class RecordingLayer: CAShapeLayer {
    var writes: [String] = []
    /// The changes Core Animation looked for an animation for, which it does only while actions
    /// are on, with the duration of the transaction each came in.
    var animated: [(key: String, duration: CFTimeInterval)] = []

    override init() { super.init() }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { nil }

    override func action(forKey event: String) -> CAAction? {
        animated.append((event, CATransaction.animationDuration()))
        return super.action(forKey: event)
    }

    override func addSublayer(_ layer: CALayer) {
        writes.append("addSublayer")
        super.addSublayer(layer)
    }

    override var position: CGPoint {
        get { super.position }
        set { writes.append("position"); super.position = newValue }
    }
    override var bounds: CGRect {
        get { super.bounds }
        set { writes.append("bounds"); super.bounds = newValue }
    }
    override var opacity: Float {
        get { super.opacity }
        set { writes.append("opacity"); super.opacity = newValue }
    }
    override var path: CGPath? {
        get { super.path }
        set { writes.append("path"); super.path = newValue }
    }
    override var fillRule: CAShapeLayerFillRule {
        get { super.fillRule }
        set { writes.append("fillRule"); super.fillRule = newValue }
    }
    override var fillColor: CGColor? {
        get { super.fillColor }
        set { writes.append("fillColor"); super.fillColor = newValue }
    }
    override var strokeColor: CGColor? {
        get { super.strokeColor }
        set { writes.append("strokeColor"); super.strokeColor = newValue }
    }
    override var lineWidth: CGFloat {
        get { super.lineWidth }
        set { writes.append("lineWidth"); super.lineWidth = newValue }
    }
    override var shadowPath: CGPath? {
        get { super.shadowPath }
        set { writes.append("shadowPath"); super.shadowPath = newValue }
    }
    override var shadowOpacity: Float {
        get { super.shadowOpacity }
        set { writes.append("shadowOpacity"); super.shadowOpacity = newValue }
    }
    override var shadowColor: CGColor? {
        get { super.shadowColor }
        set { writes.append("shadowColor"); super.shadowColor = newValue }
    }
    override var shadowRadius: CGFloat {
        get { super.shadowRadius }
        set { writes.append("shadowRadius"); super.shadowRadius = newValue }
    }
    override var shadowOffset: CGSize {
        get { super.shadowOffset }
        set { writes.append("shadowOffset"); super.shadowOffset = newValue }
    }
}
