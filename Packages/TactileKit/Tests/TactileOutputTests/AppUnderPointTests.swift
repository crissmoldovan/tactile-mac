import CoreGraphics
import Foundation
import XCTest
@testable import TactileOutput

/// The window chooser, on window lists written here as the window server writes them
/// (`CGWindowListCopyWindowInfo`'s dictionaries, front to back). Nothing here reads the real
/// window list or asks Accessibility.
final class AppUnderPointTests: XCTestCase {

    private let own: pid_t = 500
    private let point = CGPoint(x: 300, y: 200)

    /// One window's info: its owner, layer, alpha and bounds (global, origin at the top left).
    private func window(_ pid: pid_t, layer: Int = 0, alpha: Double = 1,
                        _ bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
        ]
    }

    private func owner(_ windows: [[String: Any]], at point: CGPoint? = nil) -> pid_t? {
        AppUnderPoint.ownerPID(at: point ?? self.point, in: windows, excluding: own)
    }

    func testTheFrontMostWindowUnderThePointWins() {
        XCTAssertEqual(owner([window(101), window(102)]), 101)
    }

    func testTactilesOwnWindowsArePassedOver() {
        // The touch circles: Tactile's, high above every app, under the finger, in front of VS Code.
        XCTAssertEqual(owner([window(own, layer: 1500), window(own), window(102)]), 102)
    }

    /// Another app's window above the apps (the Dock, 20; the menu bar, 24; an open menu, 101; a
    /// panel or overlay) is what the finger is on: no app answers there, so Automatic drags and no
    /// scroll is matched. It doesn't stop the search where it isn't under the point.
    func testAnotherAppsWindowAboveTheAppsStopsTheSearch() {
        for layer in [20, 24, 101, 1500, -1] {
            XCTAssertNil(owner([window(103, layer: layer), window(102)]), "layer \(layer) in front of VS Code")
        }
        let elsewhere = CGRect(x: 1000, y: 0, width: 100, height: 100)
        XCTAssertEqual(owner([window(103, layer: 20, elsewhere), window(102)]), 102)
        XCTAssertNil(owner([window(own, layer: 1500), window(103, layer: 20), window(102)]), "own passed over, the Dock not")
    }

    func testFullyTransparentWindowsArePassedOver() {
        XCTAssertEqual(owner([window(103, alpha: 0), window(102, alpha: 0.5)]), 102)
        XCTAssertEqual(owner([window(104, layer: 1500, alpha: 0), window(102)]), 102, "at any layer")
    }

    func testWindowsElsewhereAreSkipped() {
        let left = CGRect(x: -2048, y: 24, width: 2048, height: 1280)
        XCTAssertEqual(owner([window(103, left), window(102)]), 102)
        XCTAssertEqual(owner([window(103, left)], at: CGPoint(x: -10, y: 100)), 103)
    }

    func testAPointOnNoWindowHasNoApp() {
        XCTAssertNil(owner([window(101, CGRect(x: 1000, y: 0, width: 100, height: 100))]))
        XCTAssertNil(owner([]))
        XCTAssertNil(owner([window(own)]), "only Tactile's own")
    }

    func testAWindowWithoutBoundsIsPassedOverAndOneWithoutOwnerOrLayerIsNoApp() {
        var noBounds = window(103)
        noBounds[kCGWindowBounds as String] = nil
        XCTAssertEqual(owner([noBounds, window(102)]), 102, "it can't be placed")
        var noOwner = window(104)
        noOwner[kCGWindowOwnerPID as String] = nil
        XCTAssertNil(owner([noOwner, window(102)]))
        var noLayer = window(105)
        noLayer[kCGWindowLayer as String] = nil
        XCTAssertNil(owner([noLayer, window(102)]))
        // No alpha given: taken as opaque.
        var noAlpha = window(106)
        noAlpha[kCGWindowAlpha as String] = nil
        XCTAssertEqual(owner([noAlpha, window(102)]), 106)
    }
}
