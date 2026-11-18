// A drawing of a touchscreen: a screen with a touch on it, drawn on an 18-point grid. It stands for a
// touchscreen in the places that list them (the tile in each touchscreen's pane, the first-run window,
// the menu's rows), and is the menu-bar icon's fallback when the asset catalog's glyph is missing. The
// app's icon and its menu-bar glyphs are in the asset catalog, not here.

import AppKit
import CoreGraphics
import SwiftUI

enum TouchGlyph {
    /// Draws the glyph in `color`, scaled from its 18-point grid into `size`, origin top-left.
    static func draw(in context: CGContext, size: CGSize, color: CGColor) {
        let scale = min(size.width, size.height) / 18
        context.saveGState()
        context.translateBy(x: (size.width - 18 * scale) / 2, y: (size.height - 18 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineCap(.round)

        // The screen and its foot.
        context.setLineWidth(1.5)
        context.addPath(CGPath(roundedRect: CGRect(x: 1.75, y: 2.75, width: 14.5, height: 10.5),
                               cornerWidth: 2, cornerHeight: 2, transform: nil))
        context.strokePath()
        context.move(to: CGPoint(x: 6.5, y: 16.25))
        context.addLine(to: CGPoint(x: 11.5, y: 16.25))
        context.strokePath()

        // The touch, and its ring.
        context.fillEllipse(in: CGRect(x: 9 - 1.9, y: 8 - 1.9, width: 3.8, height: 3.8))
        context.setAlpha(0.55)
        context.setLineWidth(1.1)
        context.strokeEllipse(in: CGRect(x: 9 - 3.6, y: 8 - 3.6, width: 7.2, height: 7.2))
        context.restoreGState()
    }

    /// The warning badge, bottom right: a triangle with an exclamation mark cut out of it, and a gap
    /// cut around it so it reads against the glyph.
    static func drawBadge(in context: CGContext, size: CGSize, color: CGColor) {
        let scale = min(size.width, size.height) / 18
        context.saveGState()
        context.translateBy(x: (size.width - 18 * scale) / 2, y: (size.height - 18 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: 13.7, y: 8.9))
        triangle.addLine(to: CGPoint(x: 17.8, y: 16.3))
        triangle.addLine(to: CGPoint(x: 9.6, y: 16.3))
        triangle.closeSubpath()

        context.setLineJoin(.round)
        context.setBlendMode(.clear)
        context.setLineWidth(1.8)
        context.addPath(triangle)
        context.drawPath(using: .fillStroke)

        context.setBlendMode(.normal)
        context.setFillColor(color)
        context.addPath(triangle)
        context.fillPath()

        context.setBlendMode(.clear)
        context.setLineCap(.round)
        context.setLineWidth(1.3)
        context.move(to: CGPoint(x: 13.7, y: 11.7))
        context.addLine(to: CGPoint(x: 13.7, y: 13.7))
        context.strokePath()
        context.fillEllipse(in: CGRect(x: 13.7 - 0.7, y: 15.1 - 0.7, width: 1.4, height: 1.4))
        context.restoreGState()
    }
}

/// The glyph as a SwiftUI view, drawn in `color`.
struct TouchGlyphView: View {
    var color: NSColor

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                TouchGlyph.draw(in: cg, size: size, color: color.cgColor)
            }
        }
    }
}
