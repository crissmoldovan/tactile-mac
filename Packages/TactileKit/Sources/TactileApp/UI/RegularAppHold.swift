// Tactile becoming a regular app while a window that needed it is open.
//
// Settings and the gesture tester each come forward by the steps of `ActivationStep`; when macOS
// refuses to activate a menu-bar app, the second step makes Tactile a regular app (with a Dock
// icon) while that window is open. Both windows can be open at once, and close in either order: the
// policy Tactile had before one of them changed it comes back only when the last of them closes,
// whichever of them needed the change.

import AppKit

/// Which of the windows are open, and the policy Tactile had before one of them made it regular:
/// kept pure.
struct RegularAppHolds: Equatable, Sendable {
    enum Holder: String, Sendable {
        case settings
        case gestureTester
    }

    /// The windows open now.
    private(set) var open: Set<Holder> = []
    /// The policy before a window made Tactile regular; nil while none has.
    private(set) var policyBefore: NSApplication.ActivationPolicy?

    /// `holder`'s window is up. It changes nothing by itself, and keeps a regular Tactile regular
    /// until it closes.
    mutating func opened(_ holder: Holder) {
        open.insert(holder)
    }

    /// `holder`'s window needs Tactile regular, which it is now or not (`current`): the policy to
    /// set, or nil when it is regular already.
    mutating func hold(_ holder: Holder, current: NSApplication.ActivationPolicy) -> NSApplication.ActivationPolicy? {
        open.insert(holder)
        guard current != .regular else { return nil }
        if policyBefore == nil {
            policyBefore = current
        }
        return .regular
    }

    /// `holder`'s window closed: the policy to go back to when it was the last window open and a
    /// window made Tactile regular, else nil.
    mutating func release(_ holder: Holder) -> NSApplication.ActivationPolicy? {
        open.remove(holder)
        guard open.isEmpty, let before = policyBefore else { return nil }
        policyBefore = nil
        return before
    }
}

/// The app's holds, applied to `NSApplication`.
@MainActor
enum RegularAppHold {
    private static var holds = RegularAppHolds()

    static func opened(_ holder: RegularAppHolds.Holder) {
        holds.opened(holder)
    }

    static func hold(_ holder: RegularAppHolds.Holder) {
        let app = NSApplication.shared
        if let policy = holds.hold(holder, current: app.activationPolicy()) {
            app.setActivationPolicy(policy)
        }
    }

    /// True when Tactile went back to the policy it had: a menu-bar app again.
    @discardableResult
    static func release(_ holder: RegularAppHolds.Holder) -> Bool {
        guard let policy = holds.release(holder) else { return false }
        NSApplication.shared.setActivationPolicy(policy)
        return true
    }
}
