// The window a touchscreen's details are drawn in, beside the menu-bar panel.
//
// Why a window of Tactile's own and not a SwiftUI popover: the `MenuBarExtra` panel closes when it
// stops being the key window (as it does for a sheet, an alert or a file importer opened from it). A
// popover's window becomes key when it is clicked, so the first click on a switch in it would close
// the menu, and the popover with it. This window can never become key: the panel stays key, its Esc
// and its shortcuts keep working, and the clicks in the details still reach their controls (a
// non-activating panel takes a click without being made key, as a palette does).
//
// It is a child of the panel's window, so it moves and goes with it. It opens as a submenu does: when
// the pointer rests on a touchscreen's row (`MenuDetailsHover`, fed by tracking areas on each row, on
// the whole panel and on this window, with one timer for what waits), and when a row is clicked,
// tapped or chosen with Return. It moves to another row the pointer rests on, and stays up while the
// pointer heads for it, is in it, or leaves both windows for empty screen. A click on a row is the
// row's: it shows that row's details, and never closes them (`MenuDetailsWatch`). It closes when the
// pointer stays on another item in the menu, on Esc, on a click in the panel off the touchscreens'
// rows, when the panel stops being key (the menu closing, a click in another app), when the app stops
// being active, and when the panel's view goes. It is beside the panel, its top level with its row
// (`MenuDetailsPlacement`), and follows its content's height.

import AppKit
import SwiftUI
import TactileScreens

@MainActor
@Observable
final class TouchscreenDetailsWindow {
    static let shared = TouchscreenDetailsWindow()

    /// The touchscreen whose details are up: its row stays highlighted.
    private(set) var shown: TouchscreenID?

    @ObservationIgnored private var presenter = MenuDetailsPresenter()
    @ObservationIgnored private var panel: DetailsPanel?
    @ObservationIgnored private var hosting: DetailsHostingView?
    /// The row the details are beside, and the panel's window it is in.
    @ObservationIgnored private weak var anchor: NSView?
    @ObservationIgnored private weak var menuWindow: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var monitor: Any?

    /// Where the pointer is, and what waits for its time (`MenuDetailsHover`); the one timer for it.
    @ObservationIgnored private var hover = MenuDetailsHover()
    @ObservationIgnored private var timer: Timer?
    /// The touchscreens' rows drawn now, and the panel's whole area, for telling where the pointer is.
    @ObservationIgnored private var rowViews = NSHashTable<RowAnchorView>.weakObjects()
    @ObservationIgnored private weak var menuArea: NSView?

    /// A touchscreen's row was chosen (a click, a tap, Return), or the pointer rested on it: its
    /// details open beside it, move to it from another row, or stay up when they are its already.
    /// `content` draws them.
    func choose<Content: View>(_ id: TouchscreenID, anchor: NSView?, content: () -> Content) {
        switch presenter.chosen(id) {
        case .close:
            close()
        case .show:
            guard let anchor, let menu = anchor.window else {
                close()
                return
            }
            show(id, content: AnyView(content()), anchor: anchor, menu: menu)
        }
    }

    /// The menu again: details for a touchscreen no longer in it close.
    func follow(_ content: MenuBarContent) {
        if presenter.follow(content) == .close {
            close()
        }
    }

    /// Closes the details (Esc, a click elsewhere, the menu closing, a control in them that leaves
    /// the menu), and drops what the pointer had waiting: they stay closed until it comes onto a row
    /// again.
    func close() {
        hover.cancel()
        lookAgain()
        hide()
    }

    /// Closes the details; what the pointer has waiting stays (`MenuDetailsHover` closed them).
    private func hide() {
        presenter.closed()
        if shown != nil {
            shown = nil
        }
        stopWatching()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        hosting?.rootView = AnyView(EmptyView())
        anchor = nil
    }

    // MARK: - Showing

    private func show(_ id: TouchscreenID, content: AnyView, anchor: NSView, menu: NSWindow) {
        let panel = self.panel ?? makePanel()
        self.anchor = anchor
        hosting?.rootView = AnyView(
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { [weak self] _ in self?.place() }))
        if panel.parent !== menu {
            panel.parent?.removeChildWindow(panel)
            menu.addChildWindow(panel, ordered: .above)
        }
        panel.level = menu.level
        place()
        panel.orderFront(nil)
        watch(menu)
        shown = id
    }

    /// Sizes the window to its content and puts it beside the panel, level with the row.
    private func place() {
        guard let panel, let hosting, let anchor, let menu = anchor.window else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let row = menu.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = (menu.screen ?? NSScreen.main)?.visibleFrame ?? menu.frame
        let frame = MenuDetailsPlacement.frame(size: size, row: row, menu: menu.frame, screen: screen)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    private func makePanel() -> DetailsPanel {
        let panel = DetailsPanel()
        let background = DetailsBackgroundView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        let hosting = DetailsHostingView(rootView: AnyView(EmptyView()))
        // The window is sized from the content's size here (`place`), never by the hosting view.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        panel.contentView = background
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    // MARK: - What closes it

    private func watch(_ menu: NSWindow) {
        guard menuWindow !== menu || monitor == nil else { return }
        stopWatching()
        menuWindow = menu
        let center = NotificationCenter.default
        let close: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { TouchscreenDetailsWindow.shared.close() }
        }
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: menu, queue: .main, using: close),
            center.addObserver(forName: NSWindow.willCloseNotification, object: menu, queue: .main, using: close),
            center.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main, using: close),
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            let read = MenuDetailsWatch.Event(event)
            let stopped = MainActor.assumeIsolated { TouchscreenDetailsWindow.shared.handle(read) }
            return stopped ? nil : event
        }
    }

    private func stopWatching() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        menuWindow = nil
    }

    /// What `event` does to the details (`MenuDetailsWatch`): a click on any touchscreen's row is
    /// left to the row, whose action shows them there (moves them, or keeps them up) in one step,
    /// with nothing closed first; a click elsewhere in the panel closes them and goes on; Esc closes
    /// them and goes no further. The rows are read from the panel as it is drawn now. True when the
    /// event goes no further.
    private func handle(_ event: MenuDetailsWatch.Event) -> Bool {
        guard let menu = menuWindow else { return false }
        var rows: [MenuDetailsWatch.Row] = []
        // From the window's frame view: every view in the window, however SwiftUI wraps its own.
        if case .mouseDown(_, let window) = event, window == menu.windowNumber,
           let top = menu.contentView?.superview ?? menu.contentView {
            rows = RowAnchorView.rows(in: top)
        }
        let response = MenuDetailsWatch.response(
            to: event, menu: menu.windowNumber, details: panel?.windowNumber, rows: rows, shown: presenter.shown)
        switch response {
        case .none, .row:
            return false
        case .close:
            close()
            return false
        case .closeAndStop:
            close()
            return true
        }
    }

    // MARK: - Following the pointer

    /// A touchscreen's row drawn in a window: one the pointer can be on.
    func follow(row: RowAnchorView) {
        rowViews.add(row)
    }

    /// The panel's whole area, drawn in its window: the pointer on it and on no row is on another item.
    func follow(menu area: NSView) {
        menuArea = area
    }

    /// The pointer came onto a row, the panel or the details, left one, or moved over the panel: where
    /// it is now, and which way it goes, decide what the details do (`MenuDetailsHover`). A frame test
    /// against the few rows, the panel and the details; nothing more for each move.
    func pointerMoved() {
        let point = NSEvent.mouseLocation
        let rows = rowViews.allObjects.compactMap { row -> MenuDetailsWatch.Row? in
            guard let id = row.id, let frame = Self.frameOnScreen(row) else { return nil }
            return MenuDetailsWatch.Row(id: id, frame: frame)
        }
        let menu = menuArea.flatMap { Self.frameOnScreen($0) }
        let details = panel.flatMap { $0.isVisible ? $0.frame : nil }
        let place = MenuDetailsHover.place(of: point, details: details, rows: rows, menu: menu)
        perform(hover.pointer(place, at: point, time: Self.now, shown: presenter.shown, details: details))
        lookAgain()
    }

    /// What the pointer decided: a row's details shown as a click on the row shows them, through the
    /// row's own action; the details closed, with what it decided next left waiting.
    private func perform(_ action: MenuDetailsPresenter.Action?) {
        switch action {
        case .show(let id)?:
            // Only beside a row drawn in the menu as it is now: never beside a menu that has closed.
            guard let row = rowViews.allObjects.first(where: { $0.id == id && Self.frameOnScreen($0) != nil }) else {
                return
            }
            row.choose?(row)
        case .close?:
            hide()
        case nil:
            break
        }
    }

    /// Arms the one timer for when the pointer's decision waiting is due; one that fires sooner is
    /// left to fire, and arms it again then.
    private func lookAgain() {
        guard let next = hover.nextLook else {
            timer?.invalidate()
            timer = nil
            return
        }
        let date = Date(timeIntervalSinceNow: max(0, next - Self.now))
        if let timer, timer.isValid, timer.fireDate <= date {
            return
        }
        timer?.invalidate()
        // In the common modes: it fires while a button is held down in the menu too.
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { TouchscreenDetailsWindow.shared.timeCame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timeCame() {
        timer = nil
        perform(hover.tick(at: Self.now, shown: presenter.shown))
        lookAgain()
    }

    /// The hover's clock: seconds since the Mac started, as events and timers count them.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// `view`'s frame on the screen, while it is drawn, in a window on screen.
    private static func frameOnScreen(_ view: NSView) -> CGRect? {
        guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// The details' window: borderless, see-through but for its content, with a shadow; never key or
/// main, so the menu-bar panel stays key while it is up.
final class DetailsPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: TouchscreenDetailsView.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click: the details' window is never key, and a click on a switch must switch it.
final class DetailsHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The details' window's content: the menu's material behind them, and the pointer followed coming
/// into them and leaving them, so that reaching them keeps them up (`MenuDetailsHover`).
final class DetailsBackgroundView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(.pointer(owner: self))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTrackingArea(.pointer(owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }
}

/// The menu panel's whole area, behind its content (`MenuPointerArea`): follows the pointer coming
/// onto the panel, moving over it and leaving it, so that the details know when it is on the menu
/// but on none of the touchscreens' rows, and which way it goes (`MenuDetailsHover`). It never takes
/// a click: those are the content's.
final class MenuPointerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(.pointer(owner: self, moves: true))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTrackingArea(.pointer(owner: self, moves: true))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            TouchscreenDetailsWindow.shared.follow(menu: self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }

    override func mouseMoved(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }
}

/// The menu panel's whole area, behind its content: see `MenuPointerView`.
struct MenuPointerArea: NSViewRepresentable {
    func makeNSView(context: Context) -> MenuPointerView {
        MenuPointerView()
    }

    func updateNSView(_ view: MenuPointerView, context: Context) {}
}

extension NSTrackingArea {
    /// Follows the pointer coming onto `owner` and leaving it (and, with `moves`, moving over it),
    /// whichever window is key, over what is visible of it as that changes.
    static func pointer(owner: NSView, moves: Bool = false) -> NSTrackingArea {
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if moves {
            options.insert(.mouseMoved)
        }
        return NSTrackingArea(rect: .zero, options: options, owner: owner, userInfo: nil)
    }
}

extension MenuDetailsWatch.Event {
    /// Reads from `event` only what its kind has: a key's code from a key, a place from a click.
    /// (`keyCode` is valid only for key events; asked of a click it raises, and AppKit drops the
    /// click: the bug that kept every click in the menu from working while the details were up.)
    init(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            self = .key(code: event.keyCode, window: event.windowNumber)
        case .leftMouseDown, .rightMouseDown:
            self = .mouseDown(at: event.locationInWindow, window: event.windowNumber)
        default:
            self = .other
        }
    }
}

/// The view a touchscreen's row is drawn in (`RowAnchor`), known by its touchscreen: so a click can
/// be told to be on a row, and which; so the pointer coming onto the row and leaving it is followed
/// (`MenuDetailsHover`); and so the row's details can be shown as a click on it shows them.
final class RowAnchorView: NSView {
    var id: TouchscreenID?
    /// The row's own action, given the view to show the details beside: what a click on it does.
    var choose: (@MainActor (NSView?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(.pointer(owner: self))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTrackingArea(.pointer(owner: self))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            TouchscreenDetailsWindow.shared.follow(row: self)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
        TouchscreenDetailsWindow.shared.pointerMoved()
    }

    /// The touchscreen rows drawn under `top` now, each with its frame in its window's coordinates
    /// (in `top`'s, with no window); a hidden one is not a row.
    static func rows(in top: NSView) -> [MenuDetailsWatch.Row] {
        var rows: [MenuDetailsWatch.Row] = []
        var views = [top]
        while let view = views.popLast() {
            if let anchor = view as? RowAnchorView, let id = anchor.id, !anchor.isHiddenOrHasHiddenAncestor {
                rows.append(MenuDetailsWatch.Row(id: id, frame: anchor.convert(anchor.bounds, to: nil)))
            }
            views.append(contentsOf: view.subviews.reversed())
        }
        return rows
    }
}

/// The view a touchscreen's row is drawn in: an empty view behind the row, the size of the row, for
/// the details to be placed beside, for a click to be told to be on it, and for the pointer resting
/// on it to show its details through `choose`, the row's own action.
struct RowAnchor: NSViewRepresentable {
    @MainActor
    final class Box {
        weak var view: NSView?
    }

    var id: TouchscreenID
    var box: Box
    var choose: @MainActor (NSView?) -> Void

    func makeNSView(context: Context) -> RowAnchorView {
        let view = RowAnchorView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: RowAnchorView, context: Context) {
        view.id = id
        view.choose = choose
        box.view = view
    }
}
