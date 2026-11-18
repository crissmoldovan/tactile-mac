// The windows on the glass. One borderless panel per display, above other windows, on every Space.
// They never take the keyboard from the terminal: the panels are non-activating and can't become
// key, and this process never asks to be the active app. Only `survey` starts AppKit; `list`
// shows nothing.
//
// They don't stand in the way of what is recorded: the survey reads the touchscreen at the HID
// level, below any window. Every window, "Not this one" included, takes the clicks that land on it
// and does nothing with them: a touchscreen that is not held (the other one, or this one in the
// takes it is not held for) clicks like a mouse, and a click that reached the desktop would make
// Finder the active app and take the keyboard from the terminal. The Mac's own display has no
// window, which is why the terminal belongs there.

import AppKit

/// AppKit for this process, started once: no Dock icon, no menu bar, never activated.
enum AppKitHost {
    private(set) static var started = false

    static func start() {
        guard !started else { return }
        let app = NSApplication.shared
        _ = app.setActivationPolicy(.accessory)
        app.finishLaunching()
        started = true
    }
}

/// Runs the main run loop for about `seconds`: HID reports and signals always, and once AppKit
/// has started, window events and drawing too. Every wait in this tool goes through here.
func pumpEvents(_ seconds: Double) {
    guard AppKitHost.started else {
        CFRunLoopRunInMode(.defaultMode, seconds, false)
        return
    }
    let until = Date(timeIntervalSinceNow: seconds)
    let latest = until.addingTimeInterval(0.1)
    while let event = NSApp.nextEvent(matching: .any, until: until, inMode: .default, dequeue: true) {
        NSApp.sendEvent(event)
        if Date() > latest { break }
    }
}

/// A panel that can never become the key or main window, so typing always stays in the terminal.
final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The windows of one run, one per display, created as they are first needed.
final class Board {
    private struct Entry {
        let panel: BoardPanel
        let view: BoardView
    }

    private var entries: [UInt32: Entry] = [:]

    /// Shows each display's content. A display left out of `contents` has its window taken away.
    /// `catchingClicks` are the displays whose window takes the clicks that land on it.
    func show(_ contents: [UInt32: BoardContent], catchingClicks: Set<UInt32>) {
        // Without AppKit (--no-windows) there is nothing to show.
        guard AppKitHost.started else { return }
        for (id, entry) in entries where contents[id] == nil {
            entry.panel.orderOut(nil)
            entries[id] = nil
        }
        for (id, content) in contents {
            let opaque: Bool
            if case .instruction = content { opaque = true } else { opaque = false }
            if let entry = entries[id] {
                entry.view.content = content
                configure(entry.panel, opaque: opaque, catchesClicks: catchingClicks.contains(id))
                continue
            }
            guard let screen = screen(for: id) else { continue }
            let frame = screen.frame
            let panel = BoardPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.hasShadow = false
            panel.isMovable = false
            let view = BoardView(frame: CGRect(origin: .zero, size: frame.size), content: content)
            view.autoresizingMask = [.width, .height]
            panel.contentView = view
            configure(panel, opaque: opaque, catchesClicks: catchingClicks.contains(id))
            panel.setFrame(frame, display: false)
            panel.orderFrontRegardless()
            entries[id] = Entry(panel: panel, view: view)
        }
    }

    /// Called on every tick of a take, so it changes only what differs.
    private func configure(_ panel: BoardPanel, opaque: Bool, catchesClicks: Bool) {
        if panel.isOpaque != opaque {
            panel.isOpaque = opaque
            panel.backgroundColor = opaque ? BoardStyle.background : .clear
        }
        if panel.ignoresMouseEvents == catchesClicks { panel.ignoresMouseEvents = !catchesClicks }
    }

    func closeAll() {
        for entry in entries.values { entry.panel.orderOut(nil) }
        entries = [:]
    }
}

// MARK: - Pictures of the windows, without showing them

/// Draws one display's content into a PNG file. Opens no window.
func renderBoardPNG(_ content: BoardContent, size: CGSize, to url: URL) throws {
    let view = BoardView(frame: CGRect(origin: .zero, size: size), content: content)
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CommandLineError("Could not draw \(url.lastPathComponent).")
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CommandLineError("Could not encode \(url.lastPathComponent).")
    }
    try data.write(to: url, options: .atomic)
}
