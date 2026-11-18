# Icon sources

Tactile's app icon and its menu-bar glyphs come from one of six drawn options. **In use: option 1, "Ripple":** a white ring in the middle of a blue square, with two fainter rings spreading out around it. Its menu-bar glyph is a ring with a solid dot in the middle; while Tactile is off, the ring alone, crossed by a slash, with no dot. The other five stay in `options/`, and swapping to one of them is one script (below).

The Ripple is Tactile's icon and is not licensed under the GPL: see `TRADEMARKS.md` at the repository's root. A fork must use an icon of its own.

`options/` holds all six as drawn, as SVG (one change: the middle dot was taken out of option 1's off glyph, which it made look dirty at 18 px): for each option N, `option-N-app.svg` (the app icon, on a 1024-unit canvas, its body 824 units square) and `option-N-menubar.svg`, `option-N-menubar-off.svg`, `option-N-menubar-attention.svg` (18-point glyphs, black on transparent). The options: 1 Ripple, 2 Touch Display, 3 Pinch, 4 Ink, 5 Swipe T, 6 Pointer.

Nothing in this folder is part of the build. `make-icons.sh N` writes option N into `../Assets.xcassets`, replacing what is there:

- **`AppIcon.appiconset`:** `option-N-app.svg` rendered once at 1024 px by headless Google Chrome (in a throw-away profile; it opens no window), then scaled down with `sips` to the ten images macOS needs (16, 32, 128, 256 and 512 points, at 1x and 2x).
- **`MenuBarGlyph`, `MenuBarGlyphOff`, `MenuBarGlyphAttention`:** the three glyph SVGs, copied as they are, as template images that keep their vector form. The app loads them by these names. Each state is a shape, not a colour (the "off" slash and the attention dot are cut out of the drawing), so it survives being drawn in one colour.

## Swapping to another option

1. From the repository's root: `Tactile/IconSources/make-icons.sh N`, with N from 1 to 6.
2. Say which option is in use in the first paragraph above.
3. Build into a scratch folder and look at the result:
   - the icon: `sips -s format png <app>/Contents/Resources/AppIcon.icns --out icon.png`, then open `icon.png`;
   - among the names: `xcrun assetutil --info <app>/Contents/Resources/Assets.car | grep '"Name"'` lists `AppIcon` and the three glyphs, among others (`AccentColor`, packed images);
   - the three glyphs, drawn in one colour the way the menu bar draws them: `swift Tactile/IconSources/render-glyphs.swift <app> <folder>` writes each at 18 and 36 px, black on white and white on dark grey, and prints that each is 18 × 18 pt and a template image. Look at them enlarged:
     - **on** (`MenuBarGlyph`): the option's symbol, whole;
     - **off** (`MenuBarGlyphOff`): the same symbol crossed by a slash, with a gap cut out on each side of the slash (option 3 shows it faded instead; option 1 drops its middle dot, leaving the ring alone, crossed by a slash);
     - **needs attention** (`MenuBarGlyphAttention`): the same symbol with a solid dot at the top right, a gap cut out around it.

     Each state must be readable from its shape alone, in both colours: if the slash or the dot only shows up through colour, it disappears in the menu bar.
4. Commit `Tactile/Assets.xcassets` and this README.
