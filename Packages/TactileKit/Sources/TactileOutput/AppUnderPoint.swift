import AppKit
import CoreGraphics
import Foundation

/// The app whose window is under a point, found from the window server's list of windows: no
/// Accessibility (nothing an app could be slow to answer, and nothing that makes an Electron app
/// turn its accessibility tree on), and never one of Tactile's own windows, such as the touch
/// circles drawn under the finger.
public struct AppUnderPoint: Equatable, Sendable {
    public let pid: pid_t
    /// Nil for a process without one.
    public let bundleIdentifier: String?

    public init(pid: pid_t, bundleIdentifier: String?) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
    }

    /// The app whose window is front-most at `point` (global coordinates, origin at the top left),
    /// from the windows on screen now; nil over no app's window.
    public static func find(at point: CGPoint) -> AppUnderPoint? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let pid = ownerPID(at: point, in: windows, excluding: getpid()) else { return nil }
        return AppUnderPoint(pid: pid, bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }

    /// The owner of the front-most window in `windows` (window-info dictionaries, front to back, as
    /// `CGWindowListCopyWindowInfo` lists them) whose bounds contain `point`, passing over the
    /// windows of `ownPID` and those fully transparent. When that window is above the apps (any
    /// layer but 0: the Dock, the menu bar, an open menu, a panel), no app answers there: nil. So
    /// is a window there without an owner or a layer. One without bounds can't be placed and is
    /// passed over; one without an alpha counts as opaque.
    static func ownerPID(at point: CGPoint, in windows: [[String: Any]], excluding ownPID: pid_t) -> pid_t? {
        for window in windows {
            let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            guard pid != ownPID,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.contains(point) else { continue }
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return pid
        }
        return nil
    }
}
