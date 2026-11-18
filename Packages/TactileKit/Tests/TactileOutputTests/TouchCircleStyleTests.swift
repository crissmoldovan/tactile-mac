import QuartzCore
import XCTest
@testable import TactileOutput

/// The circle styles, on layers that are never put in a window: nothing here opens one.
final class TouchCircleStyleTests: XCTestCase {

    func testTheStyleForAFingerThatIsHollowRingedBothOrNeither() {
        XCTAssertEqual(TouchCircleStyle(hollow: false, ringed: false), .solid)
        XCTAssertEqual(TouchCircleStyle(hollow: true, ringed: false), .hollow)
        XCTAssertEqual(TouchCircleStyle(hollow: false, ringed: true), .ringed)
        // Decision: a touch Tactile doesn't act on can't right-click, so it gets no ring.
        XCTAssertEqual(TouchCircleStyle(hollow: true, ringed: true), .hollow)
    }

    private func ring(of layer: CAShapeLayer) -> CAShapeLayer? {
        layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.name == TouchCircleStyle.ringName }
    }

    private func circle(_ style: TouchCircleStyle) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: TouchCircleOverlay.diameter, height: TouchCircleOverlay.diameter)
        style.apply(to: layer)
        return layer
    }

    func testARingedCircleIsASolidOneWithAThinRingOutsideIt() {
        let ringed = circle(.ringed)
        let solid = circle(.solid)
        XCTAssertEqual(ringed.path, solid.path)
        XCTAssertEqual(ringed.fillColor, solid.fillColor)

        guard let ring = ring(of: ringed), let ringPath = ring.path, let disc = ringed.path else {
            return XCTFail("no ring")
        }
        XCTAssertTrue(ringPath.boundingBox.contains(disc.boundingBox))
        XCTAssertGreaterThan(ringPath.boundingBox.width, disc.boundingBox.width + 4)   // outside, with a gap
        XCTAssertEqual(ring.fillRule, .evenOdd)          // a band, not a disc
        XCTAssertNotNil(ring.strokeColor)                // edged dark, to show on light content too
        XCTAssertEqual(ring.frame, ringed.bounds)
    }

    func testTheRingAppearsOverAboutATenthOfASecond() {
        let ringed = circle(.ringed)
        guard let ring = ring(of: ringed) else { return XCTFail("no ring") }
        let appear = ring.animationKeys()?.compactMap { ring.animation(forKey: $0) as? CABasicAnimation }
            .first { $0.keyPath == "opacity" }
        XCTAssertEqual(appear?.fromValue as? Double, 0)
        XCTAssertEqual(appear?.toValue as? Double, 1)
        XCTAssertEqual(appear?.duration ?? 0, 0.1, accuracy: 0.03)
    }

    func testTheRingGoesWhenTheFingerIsNoLongerRinged() {
        for next in [TouchCircleStyle.solid, .hollow] {
            let layer = circle(.ringed)
            next.apply(to: layer)
            XCTAssertNil(ring(of: layer), "\(next)")
        }
    }

    func testStayingRingedKeepsOneRingAndDoesNotFadeItInAgain() {
        let layer = circle(.ringed)
        guard let first = ring(of: layer) else { return XCTFail("no ring") }
        first.removeAllAnimations()
        TouchCircleStyle.ringed.apply(to: layer)
        XCTAssertEqual(layer.sublayers?.filter { $0.name == TouchCircleStyle.ringName }.count, 1)
        XCTAssertTrue(ring(of: layer) === first)
        XCTAssertNil(first.animationKeys())
    }

    func testSolidAndHollowCirclesHaveNoRing() {
        XCTAssertNil(ring(of: circle(.solid)))
        XCTAssertNil(ring(of: circle(.hollow)))
    }

    // MARK: Shadows from paths
    //
    // Without a shadow path, Core Animation works a layer's shadow out from what the layer draws, in
    // an offscreen pass, every time it draws it. Each shape casts its shadow from a path of itself
    // instead. A shadow path is filled with the non-zero rule.

    /// A point `radius` pt right of the circle's centre.
    private func point(_ radius: CGFloat, from layer: CALayer) -> CGPoint {
        CGPoint(x: layer.bounds.midX + radius, y: layer.bounds.midY)
    }

    func testAFilledCircleCastsItsShadowFromItsDiscOutToTheEdgeOfItsRim() throws {
        for style in [TouchCircleStyle.solid, .ringed] {
            let layer = circle(style)
            let shadow = try XCTUnwrap(layer.shadowPath, "\(style)")
            let disc = try XCTUnwrap(layer.path)
            XCTAssertTrue(shadow.contains(point(0, from: layer)), "\(style)")
            XCTAssertEqual(shadow.boundingBox,
                           disc.boundingBox.insetBy(dx: -layer.lineWidth / 2, dy: -layer.lineWidth / 2), "\(style)")
        }
    }

    func testAHollowCircleCastsNoShadowInsideIt() throws {
        let layer = circle(.hollow)
        let shadow = try XCTUnwrap(layer.shadowPath)
        let outline = try XCTUnwrap(layer.path)
        XCTAssertFalse(shadow.contains(point(0, from: layer)))
        XCTAssertFalse(shadow.contains(point(14, from: layer)))     // inside the band
        XCTAssertTrue(shadow.contains(point(18, from: layer)))      // the band, 16.5–20 pt out
        XCTAssertEqual(shadow.boundingBox,
                       outline.boundingBox.insetBy(dx: -layer.lineWidth / 2, dy: -layer.lineWidth / 2))
    }

    func testTheRingCastsItsOwnShadowFromItsBand() throws {
        let ringed = circle(.ringed)
        let ring = try XCTUnwrap(ring(of: ringed))
        let shadow = try XCTUnwrap(ring.shadowPath, "a shadow path on the circle leaves the ring without one")
        XCTAssertTrue(shadow.contains(point(27.5, from: ring)))     // the band, 26–29 pt out
        XCTAssertFalse(shadow.contains(point(23, from: ring)))      // the gap between it and the circle
        XCTAssertFalse(shadow.contains(point(0, from: ring)))
        XCTAssertGreaterThan(ring.shadowOpacity, 0)
        XCTAssertEqual(ring.shadowRadius, 3)
        XCTAssertEqual(ring.shadowOffset, .zero)
    }

    func testTheShadowChangesWithTheStyle() throws {
        let layer = circle(.solid)
        TouchCircleStyle.hollow.apply(to: layer)
        XCTAssertFalse(try XCTUnwrap(layer.shadowPath).contains(point(0, from: layer)))
        TouchCircleStyle.solid.apply(to: layer)
        XCTAssertTrue(try XCTUnwrap(layer.shadowPath).contains(point(0, from: layer)))
    }
}
