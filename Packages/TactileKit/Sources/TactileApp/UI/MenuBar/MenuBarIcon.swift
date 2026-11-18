import AppKit

/// The menu-bar icon: Tactile's glyph as a template image, in one of three states.
///
/// From 0.4.0 each state is an image of the app's own, from its asset catalog: `MenuBarGlyph`,
/// `MenuBarGlyphOff` and `MenuBarGlyphAttention`. A missing Off or Attention is made from
/// `MenuBarGlyph` (at 40 % ink; with the warning badge cut in), so the icon keeps its shape. Only
/// when `MenuBarGlyph` itself isn't found (in tests, in previews, in a build without the assets) do
/// the states without an image of their own fall back to the glyph drawn here, which is dimmed while
/// Tactile is off and badged while any warning stands.
enum MenuBarIcon {

    enum State: Equatable, Hashable, Sendable {
        case normal, off, attention

        /// A warning shows even while Tactile is off: Accessibility access is needed either way.
        init(_ snapshot: AppSnapshot) {
            if !snapshot.warnings.isEmpty {
                self = .attention
            } else {
                self = snapshot.isOn ? .normal : .off
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .normal: return "Tactile"
            case .off: return "Tactile, off"
            case .attention: return "Tactile, needs attention"
            }
        }
    }

    /// Where a state's image comes from.
    enum Source: Equatable, Sendable {
        /// The app's own image for the state, by its name in the asset catalog.
        case asset(String)
        /// Off, made from the app's main glyph at 40 % ink.
        case dimmed(String)
        /// Attention, made from the app's main glyph with the warning badge cut in.
        case badged(String)
        /// The glyph drawn here.
        case drawn(State)
    }

    /// How much ink the drawn and the made Off glyphs have.
    static let offInk: CGFloat = 0.4

    /// The menu bar's height for its icon, in points.
    static let height: CGFloat = 18

    /// The name of a state's image in the app's asset catalog.
    static func assetName(_ state: State) -> String {
        switch state {
        case .normal: return "MenuBarGlyph"
        case .off: return "MenuBarGlyphOff"
        case .attention: return "MenuBarGlyphAttention"
        }
    }

    /// The app's image for `state` when it has one; else, for Off and Attention, one made from the
    /// app's main glyph; else the drawn glyph.
    static func source(_ state: State, hasAsset: (String) -> Bool) -> Source {
        let name = assetName(state)
        if hasAsset(name) { return .asset(name) }
        let main = assetName(.normal)
        guard hasAsset(main) else { return .drawn(state) }
        switch state {
        case .normal: return .drawn(state)
        case .off: return .dimmed(main)
        case .attention: return .badged(main)
        }
    }

    /// The size an image is shown at in the menu bar: 18 points tall, its proportions kept; 18 × 18
    /// for an image with no size of its own.
    static func menuBarSize(for size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            return NSSize(width: height, height: height)
        }
        return NSSize(width: (size.width * height / size.height * 100).rounded() / 100, height: height)
    }

    /// The icon for `state`, as `source` says: the app's images are looked up by name
    /// (`NSImage(named:)`, the app's main bundle, unless a test gives another lookup), each made a
    /// template at menu-bar size. An image found is copied or drawn from, never changed:
    /// `NSImage(named:)` shares it.
    @MainActor
    static func image(_ state: State, lookup: (String) -> NSImage? = { NSImage(named: $0) }) -> NSImage {
        var found: [String: NSImage] = [:]
        let source = source(state, hasAsset: { name in
            if let image = lookup(name) { found[name] = image }
            return found[name] != nil
        })
        logOnce(state, source)
        let image: NSImage
        switch source {
        case .asset(let name):
            guard let original = found[name], let copy = original.copy() as? NSImage else { return drawnImage(state) }
            copy.size = menuBarSize(for: original.size)
            image = copy
        case .dimmed(let name):
            guard let original = found[name] else { return drawnImage(state) }
            image = made(from: original, ink: offInk, badged: false)
        case .badged(let name):
            guard let original = found[name] else { return drawnImage(state) }
            image = made(from: original, ink: 1, badged: true)
        case .drawn:
            return drawnImage(state)
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    /// `original` drawn at menu-bar size with `ink` opacity, and the warning badge cut in when
    /// `badged`, as the drawn glyph has them.
    @MainActor
    private static func made(from original: NSImage, ink: CGFloat, badged: Bool) -> NSImage {
        NSImage(size: menuBarSize(for: original.size), flipped: true) { rect in
            original.draw(in: rect, from: .zero, operation: .sourceOver, fraction: ink, respectFlipped: true, hints: nil)
            if badged, let context = NSGraphicsContext.current?.cgContext {
                TouchGlyph.drawBadge(in: context, size: rect.size, color: NSColor.black.withAlphaComponent(ink).cgColor)
            }
            return true
        }
    }

    /// The glyph drawn here: an 18-point template image; the menu bar tints it.
    @MainActor
    static func drawnImage(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: height, height: height), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let ink = NSColor.black.withAlphaComponent(state == .off ? offInk : 1).cgColor
            TouchGlyph.draw(in: context, size: rect.size, color: ink)
            if state == .attention {
                TouchGlyph.drawBadge(in: context, size: rect.size, color: ink)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = state.accessibilityDescription
        return image
    }

    /// The states whose source has been logged: one line per state a launch, saying which it is.
    @MainActor private static var logged: Set<State> = []

    @MainActor
    private static func logOnce(_ state: State, _ source: Source) {
        guard !logged.contains(state) else { return }
        logged.insert(state)
        switch source {
        case .asset(let name):
            InterfaceLog.log.info("menu-bar glyph: \(name, privacy: .public) from the app's assets")
        case .dimmed(let name), .badged(let name):
            InterfaceLog.log.info(
                "menu-bar glyph: \(assetName(state), privacy: .public) not in the app's assets; made from \(name, privacy: .public)")
        case .drawn:
            InterfaceLog.log.info(
                "menu-bar glyph: \(assetName(state), privacy: .public) not in the app's assets; the drawn glyph is used")
        }
    }
}
