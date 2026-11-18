// What CoreGraphics and AppKit say about a display → `DisplayFacts`. Pure, so it is tested; the
// calls that gather the raw values are in `LiveDisplaySource`.

import CoreGraphics
import Foundation
import TactileScreens

/// One online display as CoreGraphics and AppKit describe it.
struct RawDisplay: Equatable {
    var displayID: UInt32
    /// `CGDisplayCreateUUIDFromDisplayID` as a string; nil when it gives none.
    var uuid: String?
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    /// Every mode the display advertises, as CoreGraphics gives them.
    var modes: [RawMode]
    /// `CGDisplayScreenSize`, in millimetres.
    var screenSizeMM: CGSize
    /// The matching `NSScreen`'s `localizedName`; nil when there is no `NSScreen` for it.
    var screenName: String?
    /// `CGDisplayBounds`: global, origin at the top-left of the main display.
    var bounds: CGRect
    /// `CGDisplayRotation`, in degrees.
    var rotation: Double
    var isBuiltIn: Bool
    var isMain: Bool
    /// `CGDisplayMirrorsDisplay`: the display it mirrors, or `kCGNullDirectDisplay` (0).
    var mirrors: UInt32
}

/// One mode a display advertises, as CoreGraphics gives it.
struct RawMode: Equatable {
    var pixelWidth: Int
    var pixelHeight: Int
    /// The mode's size in points: half the pixels for a HiDPI ("Retina") mode.
    var width: Int
    var height: Int
    /// `CGDisplayModeGetIOFlags`.
    var ioFlags: UInt32
}

enum DisplayReading {

    /// `kDisplayModeNativeFlag` in IOKit's graphics types: the panel's own mode.
    static let nativeModeFlag: UInt32 = 0x0200_0000

    /// The name of a display with no `NSScreen`: one that mirrors another, or one read before
    /// AppKit has added its screen. A display may also really be called this.
    static let fallbackName = "Display"

    /// `raw` as `DisplayFacts`; nil when its frame or native size isn't finite, as no mapping or
    /// fingerprint could use it.
    ///
    /// - The UUID is exactly `""` when there is none, or it is blank, `"(null)"` or all zeros: the
    ///   display matcher never matches by an empty UUID, and any other placeholder would match.
    /// - `sizeMM` is `CGDisplayScreenSize` as it is: it already turns with the display, as the
    ///   frame does.
    /// - `nativePixels` is the panel's own mode (see `nativeMode`), unrotated. On a display turned
    ///   90° or 270°, a mode with the frame's shape has been given turned, and is turned back. Zero
    ///   when it advertises no mode.
    /// - The name is the `NSScreen`'s, else "Display": a display that mirrors another has no
    ///   `NSScreen` of its own.
    static func facts(from raw: RawDisplay) -> DisplayFacts? {
        let frame = raw.bounds
        guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite else {
            return nil
        }
        var native = nativeMode(of: raw.modes).map { CGSize(width: $0.pixelWidth, height: $0.pixelHeight) } ?? .zero
        guard native.width.isFinite, native.height.isFinite else { return nil }
        let rotation = degrees(raw.rotation)
        if rotation % 180 != 0, native.width != native.height,
           (native.width > native.height) == (frame.width > frame.height), frame.width != frame.height {
            native = CGSize(width: native.height, height: native.width)
        }
        return DisplayFacts(
            displayID: raw.displayID, uuid: uuid(raw.uuid), vendor: Int(raw.vendor), model: Int(raw.model),
            serial: Int(raw.serial), nativePixels: native, sizeMM: raw.screenSizeMM, name: raw.screenName ?? fallbackName,
            frame: frame, rotation: rotation, isBuiltIn: raw.isBuiltIn, isMain: raw.isMain,
            mirrors: raw.mirrors == 0 ? nil : raw.mirrors)
    }

    /// The panel's own mode: the largest one flagged native; else the largest whose pixels are its
    /// points, as a HiDPI mode's backing store (6016 × 3384 on a 4K panel) is not; else the largest.
    static func nativeMode(of modes: [RawMode]) -> RawMode? {
        func largest(_ modes: [RawMode]) -> RawMode? {
            modes.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
        }
        return largest(modes.filter { $0.ioFlags & nativeModeFlag != 0 })
            ?? largest(modes.filter { $0.pixelWidth == $0.width })
            ?? largest(modes)
    }

    /// A display's UUID, or `""` for none.
    static func uuid(_ text: String?) -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed == "(null)" { return "" }
        let digits = trimmed.filter { $0 != "-" }
        if digits.allSatisfy({ $0 == "0" }) { return "" }
        return trimmed
    }

    /// Whole degrees, 0…359; 0 for a rotation that isn't finite.
    private static func degrees(_ rotation: Double) -> Int {
        guard rotation.isFinite else { return 0 }
        let whole = Int(rotation.truncatingRemainder(dividingBy: 360).rounded())
        return (whole % 360 + 360) % 360
    }
}

/// What the live display source publishes. While macOS reconfigures the displays there are none,
/// so that no touch is mapped through a frame that is changing: every touch is cancelled on the
/// mapping it had, and every touchscreen held, until the displays have settled. Pure.
struct PublishedDisplays: Equatable {
    private(set) var displays: [DisplayFacts]
    private(set) var isReconfiguring = false
    /// How many reconfigurations have begun: each one's token.
    private var reconfigurations = 0

    init(_ displays: [DisplayFacts]) {
        self.displays = displays
    }

    /// A reconfiguration has begun: no displays. CoreGraphics says so once for each display; only
    /// the first, while none is under way, begins one. Returns whether `displays` changed, and, for
    /// a reconfiguration that has just begun, its token for `needsFallback`.
    mutating func reconfigurationBegan() -> (changed: Bool, fallback: Int?) {
        guard !isReconfiguring else { return (false, nil) }
        isReconfiguring = true
        reconfigurations += 1
        let changed = !displays.isEmpty
        displays = []
        return (changed, reconfigurations)
    }

    /// Whether the reconfiguration with `token` is still under way, so that its fallback should read
    /// the displays: never during a later one.
    func needsFallback(_ token: Int) -> Bool {
        isReconfiguring && token == reconfigurations
    }

    /// The displays have settled, after a reconfiguration or whenever AppKit says the screens
    /// changed; `current` is what CoreGraphics says now. Whether `displays` changed.
    mutating func settled(_ current: [DisplayFacts]) -> Bool {
        isReconfiguring = false
        guard current != displays else { return false }
        displays = current
        return true
    }
}
