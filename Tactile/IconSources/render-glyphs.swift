// Draws the three menu-bar glyphs from a built Tactile.app as one-colour PNGs, the way the menu bar
// draws a template image, so they can be looked at after an icon swap. It loads the images from the
// app's asset catalog without running the app, and opens no window.
//
//   swift Tactile/IconSources/render-glyphs.swift <path to Tactile.app> <output folder>
//
// For each glyph it writes <name>-18-light.png and <name>-36-light.png (black on white) and
// <name>-18-dark.png and <name>-36-dark.png (white on dark grey): 18 and 36 pixels are the menu bar
// at 1x and 2x. It prints each glyph's size in points and whether it is a template image.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let app = Bundle(path: arguments[1]) else {
    FileHandle.standardError.write("usage: swift render-glyphs.swift <Tactile.app> <output folder>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func draw(_ glyph: NSImage, pixels: Int, colour: NSColor, background: NSColor) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let square = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    background.setFill()
    square.fill()
    // One colour, as for a template image: the glyph's shape filled with `colour`.
    let tinted = NSImage(size: glyph.size, flipped: false) { rect in
        glyph.draw(in: rect)
        colour.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: square)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var missing = false
for name in ["MenuBarGlyph", "MenuBarGlyphOff", "MenuBarGlyphAttention"] {
    guard let glyph = app.image(forResource: name) else {
        print("\(name): not found in \(arguments[1])")
        missing = true
        continue
    }
    print("\(name): \(Int(glyph.size.width)) x \(Int(glyph.size.height)) pt, template image: \(glyph.isTemplate)")
    for pixels in [18, 36] {
        try draw(glyph, pixels: pixels, colour: .black, background: .white)
            .write(to: output.appendingPathComponent("\(name)-\(pixels)-light.png"))
        try draw(glyph, pixels: pixels, colour: .white, background: NSColor(white: 0.16, alpha: 1))
            .write(to: output.appendingPathComponent("\(name)-\(pixels)-dark.png"))
    }
}
exit(missing ? 1 : 0)
