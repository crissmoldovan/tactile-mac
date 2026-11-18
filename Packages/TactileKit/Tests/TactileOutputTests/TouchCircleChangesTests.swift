import CoreGraphics
import XCTest
@testable import TactileOutput

/// What one touch report changes about the circles drawn, worked out from what was drawn last.
final class TouchCircleChangesTests: XCTestCase {
    private let a = TouchCircle(position: CGPoint(x: 250, y: 250), style: .solid)
    private let b = TouchCircle(position: CGPoint(x: 500, y: 450), style: .hollow)

    func testAStillHoldChangesNothing() {
        let frame = [1: a, 2: b]
        let changes = TouchCircleChanges(from: frame, to: frame)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(changes, TouchCircleChanges(from: [:], to: [:]))
    }

    func testNoFingersBeforeOrNowChangesNothing() {
        XCTAssertTrue(TouchCircleChanges(from: [:], to: [:]).isEmpty)
    }

    func testAMovedFingerMovesOnlyItsCircle() {
        var moved = a
        moved.position = CGPoint(x: 260, y: 240)
        let changes = TouchCircleChanges(from: [1: a, 2: b], to: [1: moved, 2: b])
        XCTAssertEqual(changes.moved, [1: CGPoint(x: 260, y: 240)])
        XCTAssertEqual(changes.added, [:])
        XCTAssertEqual(changes.restyled, [:])
        XCTAssertEqual(changes.lifted, [])
        XCTAssertFalse(changes.isEmpty)
    }

    func testAnyMoveAtAllMoves() {
        var nudged = a
        nudged.position.x += 0.001
        XCTAssertEqual(TouchCircleChanges(from: [1: a], to: [1: nudged]).moved, [1: nudged.position])
    }

    func testAChangeOfStyleRestylesOnlyThatCircle() {
        var ringed = a
        ringed.style = .ringed
        let toRinged = TouchCircleChanges(from: [1: a, 2: b], to: [1: ringed, 2: b])
        XCTAssertEqual(toRinged.restyled, [1: .ringed])
        XCTAssertEqual(toRinged.moved, [:])
        XCTAssertEqual(toRinged.added, [:])
        XCTAssertEqual(toRinged.lifted, [])

        let backToSolid = TouchCircleChanges(from: [1: ringed, 2: b], to: [1: a, 2: b])
        XCTAssertEqual(backToSolid.restyled, [1: .solid])
        XCTAssertEqual(backToSolid.moved, [:])
    }

    func testAFingerThatMovesAndChangesStyleIsMovedAndRestyled() {
        let after = TouchCircle(position: CGPoint(x: 300, y: 300), style: .ringed)
        let changes = TouchCircleChanges(from: [1: a], to: [1: after])
        XCTAssertEqual(changes.moved, [1: after.position])
        XCTAssertEqual(changes.restyled, [1: .ringed])
    }

    func testALiftedFingerFadesAndTheOthersStay() {
        let changes = TouchCircleChanges(from: [1: a, 2: b], to: [1: a])
        XCTAssertEqual(changes.lifted, [2])
        XCTAssertEqual(changes.moved, [:])
        XCTAssertEqual(changes.restyled, [:])
        XCTAssertEqual(changes.added, [:])
    }

    func testLiftingEveryFingerFadesEveryCircle() {
        XCTAssertEqual(TouchCircleChanges(from: [1: a, 2: b], to: [:]).lifted, [1, 2])
    }

    func testANewFingerIsAddedWhereItIsInItsStyle() {
        let changes = TouchCircleChanges(from: [1: a], to: [1: a, 2: b])
        XCTAssertEqual(changes.added, [2: b])
        XCTAssertEqual(changes.moved, [:])
        XCTAssertEqual(changes.restyled, [:])
        XCTAssertEqual(changes.lifted, [])
    }
}
