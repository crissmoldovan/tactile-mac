import AppKit
import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// The menu-bar glyph: the app's own image for each state, as a template at menu-bar size, and the
/// drawn glyph wherever the image isn't found.
@MainActor
final class MenuBarGlyphTests: XCTestCase {
    // MARK: - The menu-bar glyph

    func testEachStateHasItsOwnGlyph() {
        XCTAssertEqual(MenuBarIcon.assetName(.normal), "MenuBarGlyph")
        XCTAssertEqual(MenuBarIcon.assetName(.off), "MenuBarGlyphOff")
        XCTAssertEqual(MenuBarIcon.assetName(.attention), "MenuBarGlyphAttention")
    }

    func testTheAssetIsUsedWhenItIsThereAndTheDrawnGlyphWhenNot() {
        for state in [MenuBarIcon.State.normal, .off, .attention] {
            XCTAssertEqual(MenuBarIcon.source(state, hasAsset: { _ in true }), .asset(MenuBarIcon.assetName(state)))
            XCTAssertEqual(MenuBarIcon.source(state, hasAsset: { _ in false }), .drawn(state))
        }
        XCTAssertEqual(MenuBarIcon.source(.normal, hasAsset: { $0 == "MenuBarGlyphOff" }), .drawn(.normal),
                       "without the app's main glyph, the drawn one")
    }

    /// Only `MenuBarGlyph` shipped: Off and Attention are made from it, so the icon keeps its shape
    /// when Tactile is turned off or a warning comes. The drawn glyph only when `MenuBarGlyph`
    /// itself is missing.
    func testAMissingOffOrAttentionIsMadeFromTheMainGlyph() {
        let onlyMain: (String) -> Bool = { $0 == "MenuBarGlyph" }
        XCTAssertEqual(MenuBarIcon.source(.normal, hasAsset: onlyMain), .asset("MenuBarGlyph"))
        XCTAssertEqual(MenuBarIcon.source(.off, hasAsset: onlyMain), .dimmed("MenuBarGlyph"))
        XCTAssertEqual(MenuBarIcon.source(.attention, hasAsset: onlyMain), .badged("MenuBarGlyph"))
        let mainAndOff: (String) -> Bool = { $0 == "MenuBarGlyph" || $0 == "MenuBarGlyphOff" }
        XCTAssertEqual(MenuBarIcon.source(.off, hasAsset: mainAndOff), .asset("MenuBarGlyphOff"))
        XCTAssertEqual(MenuBarIcon.source(.attention, hasAsset: mainAndOff), .badged("MenuBarGlyph"))
        XCTAssertEqual(MenuBarIcon.source(.off, hasAsset: { $0 == "MenuBarGlyphOff" }), .asset("MenuBarGlyphOff"),
                       "its own image, when it has one")
        XCTAssertEqual(MenuBarIcon.source(.attention, hasAsset: { $0 == "MenuBarGlyphOff" }), .drawn(.attention))
    }

    /// The made images: Off at 40 % ink, Attention with the badge cut in, both templates at
    /// menu-bar size, drawn from a solid 18-point square standing in for `MenuBarGlyph`.
    func testTheMadeImages() throws {
        let solid = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        let lookup: (String) -> NSImage? = { $0 == "MenuBarGlyph" ? solid : nil }

        let off = MenuBarIcon.image(.off, lookup: lookup)
        XCTAssertTrue(off.isTemplate)
        XCTAssertEqual(off.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(off.accessibilityDescription, "Tactile, off")
        XCTAssertEqual(try alpha(of: off, at: CGPoint(x: 9, y: 9)), 0.4, accuracy: 0.05)

        let attention = MenuBarIcon.image(.attention, lookup: lookup)
        XCTAssertTrue(attention.isTemplate)
        XCTAssertEqual(attention.accessibilityDescription, "Tactile, needs attention")
        XCTAssertEqual(try alpha(of: attention, at: CGPoint(x: 4, y: 4)), 1, accuracy: 0.05, "the glyph itself")
        XCTAssertLessThan(try alpha(of: attention, at: CGPoint(x: 13.7, y: 12.7)), 0.3,
                          "the badge's exclamation mark is cut out of it")
        XCTAssertEqual(try alpha(of: attention, at: CGPoint(x: 15, y: 15.5)), 1, accuracy: 0.05, "the badge")
    }

    /// The opacity of `image` at `point`, in points from its top-left, drawn offscreen at 4×.
    private func alpha(of image: NSImage, at point: CGPoint) throws -> CGFloat {
        let scale: CGFloat = 4
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.restoreGraphicsState()
        let color = try XCTUnwrap(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
        return color.alphaComponent
    }

    func testAnAssetIsATemplateAtMenuBarSize() {
        let wide = NSImage(size: NSSize(width: 40, height: 20))
        let image = MenuBarIcon.image(.off, lookup: { $0 == "MenuBarGlyphOff" ? wide : nil })
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 36, height: 18), "18 points tall, its shape kept")
        XCTAssertEqual(image.accessibilityDescription, "Tactile, off")
        XCTAssertFalse(wide.isTemplate, "a copy is changed, not the shared image")
        XCTAssertEqual(wide.size, NSSize(width: 40, height: 20))
    }

    func testWithoutTheAssetsTheDrawnGlyphIsUsed() {
        let image = MenuBarIcon.image(.attention, lookup: { _ in nil })
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(image.accessibilityDescription, "Tactile, needs attention")
        XCTAssertNil(NSImage(named: "MenuBarGlyph"), "a test runs outside the app: no asset, so the drawn glyph")
    }

    func testTheMenuBarSize() {
        XCTAssertEqual(MenuBarIcon.menuBarSize(for: NSSize(width: 18, height: 18)), NSSize(width: 18, height: 18))
        XCTAssertEqual(MenuBarIcon.menuBarSize(for: NSSize(width: 36, height: 36)), NSSize(width: 18, height: 18))
        XCTAssertEqual(MenuBarIcon.menuBarSize(for: NSSize(width: 22, height: 16)), NSSize(width: 24.75, height: 18))
        XCTAssertEqual(MenuBarIcon.menuBarSize(for: .zero), NSSize(width: 18, height: 18), "no size of its own")
    }
}
