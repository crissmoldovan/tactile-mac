import CoreGraphics
import Darwin

/// Hides and shows the arrow, even while Tactile isn't the active app.
@MainActor
final class CursorVisibility {
    private var isHidden = false

    /// Lets this app hide the cursor while in the background, through the undocumented
    /// WindowServer connection property `SetsCursorInBackground`. False when unavailable.
    private static let canHideInBackground: Bool = {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let connectionSymbol = dlsym(everyImage, "_CGSDefaultConnection"),
              let setSymbol = dlsym(everyImage, "CGSSetConnectionProperty") else { return false }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSymbol, to: SetConnectionProperty.self)
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }()

    func hide() {
        guard !isHidden, Self.canHideInBackground else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        isHidden = true
    }

    func show() {
        guard isHidden else { return }
        CGDisplayShowCursor(CGMainDisplayID())
        isHidden = false
    }
}
