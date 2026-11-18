// The general pasteboard, for Copy Diagnostics.

import AppKit

/// Puts text on the general pasteboard, replacing what is there. The model's default; tests give
/// the model a closure that keeps the text instead.
@MainActor
public enum LivePasteboard {
    public static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
