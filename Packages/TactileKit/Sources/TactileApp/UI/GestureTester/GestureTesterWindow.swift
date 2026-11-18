// The gesture tester's window: an ordinary titled window on the display the touchscreen is paired
// with, filling it with a margin, brought to the front and made key by the steps Settings uses
// (`ActivationStep`). It follows the snapshot's `gestureTester` through its own observer
// (`GestureTesterFollower`), as the set-up screens and the first-run window follow theirs: opened
// for it, closed when it goes, and opened again on the other display when it is for another
// touchscreen. Its close button and Esc close it at once and send `closeGestureTester`.
//
// Its content never reads the model: the same observer hands each snapshot to the window's store
// (`GestureTesterStore`), which keeps each part's content apart and changes it only when it
// differs, so a gesture's updates draw the feed again and nothing else.
//
// It is key on purpose: macOS sends a pinch or a rotation "to the view under the touch in the key
// window" (`NSResponder.magnify(with:)`, `rotate(with:)`), so the practice photo turns only while
// the tester has the focus. The touchscreen drives as usual while the tester is open: its taps and
// drags reach the controls as clicks and drags.

import AppKit
import Observation
import SwiftUI
import TactileScreens

/// Watches `model.snapshot` with Observation, re-armed after every change, and tells the window the
/// tester the snapshot has: once at the start, then only when it changed. It hands every snapshot,
/// after that, to `show`: the window's store, which takes from it what it shows.
@MainActor
final class GestureTesterFollower {
    private let model: any AppModel
    private let tell: @MainActor (GestureTesterSnapshot?) -> Void
    private let show: (@MainActor (AppSnapshot) -> Void)?
    private var isFollowing = false
    private var hasTold = false
    private var last: GestureTesterSnapshot?

    init(
        model: any AppModel, tell: @escaping @MainActor (GestureTesterSnapshot?) -> Void,
        show: (@MainActor (AppSnapshot) -> Void)? = nil
    ) {
        self.model = model
        self.tell = tell
        self.show = show
    }

    func start() {
        guard !isFollowing else { return }
        isFollowing = true
        follow()
    }

    func stop() {
        isFollowing = false
    }

    private func follow() {
        guard isFollowing else { return }
        let snapshot = withObservationTracking {
            model.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        let tester = snapshot.gestureTester
        if !hasTold || tester != last {
            hasTold = true
            last = tester
            tell(tester)
        }
        show?(snapshot)
    }
}

@MainActor
final class GestureTesterWindow: NSObject, NSWindowDelegate {
    static let shared = GestureTesterWindow()

    private var window: GestureTesterNSWindow?
    /// What the window that is up shows, following the snapshot.
    private var store: GestureTesterStore?
    private var presenter = GestureTesterPresenter()
    private var model: (any AppModel)?
    private var follower: GestureTesterFollower?
    /// Set while Tactile closes the window itself, so that close isn't taken for the person's.
    private var isClosingByItself = false
    private var isQuitting = false
    private var quitObserver: NSObjectProtocol?

    override init() {
        super.init()
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isQuitting = true
                self.presenter.closedQuietly()
                self.closeByItself(reason: "Tactile is quitting", releasingHold: true)
            }
        }
    }

    /// Follows `model` for the tester's window, once: called again for the same model (SwiftUI may
    /// make the scenes again), it changes nothing.
    static func startForTheApp(_ model: any AppModel) {
        shared.follow(model)
    }

    private func follow(_ model: any AppModel) {
        guard self.model.map({ ObjectIdentifier($0) }) != ObjectIdentifier(model) else { return }
        follower?.stop()
        self.model = model
        let follower = GestureTesterFollower(
            model: model,
            tell: { [weak self] tester in self?.told(tester) },
            show: { [weak self] snapshot in self?.store?.update(snapshot) })
        self.follower = follower
        InterfaceLog.log.info("following the snapshot for the gesture tester")
        follower.start()
    }

    /// Gesture Tester… pressed for `touchscreen`, in the menu or a pane: asks the model to open it,
    /// and brings the window forward if it is up for that touchscreen already.
    static func open(_ touchscreen: TouchscreenID, perform: PerformCommand) {
        InterfaceLog.log.info("gesture tester: Gesture Tester… pressed for \(touchscreen.rawValue, privacy: .public)")
        perform(.openGestureTester(touchscreen))
        shared.carryOut(shared.presenter.asked(toOpen: touchscreen))
    }

    private func told(_ tester: GestureTesterSnapshot?) {
        carryOut(presenter.told(tester))
    }

    private func carryOut(_ action: GestureTesterPresenter.Action) {
        switch action {
        case .nothing:
            break
        case .open(let shown):
            put(up: shown)
        case .replace(let shown):
            closeByItself(reason: "the tester moved to another touchscreen or display", releasingHold: action.releasesHold)
            put(up: shown)
        case .close(let reason):
            closeByItself(reason: reason, releasingHold: action.releasesHold)
        case .bringForward:
            if let window {
                bringForward(window)
            }
        case .send(let command):
            model?.perform(command)
        }
    }

    // MARK: - The window

    private func put(up shown: GestureTesterPresenter.Shown) {
        guard let model else { return }
        let screen = Self.screen(showing: shown.displayID)
        if screen == nil {
            InterfaceLog.log.error(
                "gesture tester: display \(shown.displayID, privacy: .public) has no screen; opening it on the main one")
        }
        guard let nsScreen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = GestureTesterWindowFrame.frame(in: nsScreen.visibleFrame)
        let layout = GestureTesterLayout(displaySize: nsScreen.frame.size)
        let name = model.snapshot.gestureTester?.touchscreenName ?? ""

        // Not miniaturisable: a tester out of sight would still hold the touchscreen's swipes.
        let window = GestureTesterNSWindow(
            contentRect: frame, styleMask: GestureTesterNSWindow.style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.title = Wording.gestureTesterWindowTitle(name: name)
        window.delegate = self
        window.onEscape = { [weak window] in window?.performClose(nil) }
        let store = GestureTesterStore(
            touchscreen: shown.touchscreen, layout: layout, snapshot: model.snapshot, perform: { [model] in model.perform($0) })
        self.store = store
        let content = NSHostingView(rootView: GestureTesterRoot(store: store))
        // The window keeps the size it was given: the content fills it, and never resizes it.
        content.sizingOptions = []
        window.contentView = content
        window.setFrame(frame, display: false)
        self.window = window
        RegularAppHold.opened(.gestureTester)
        InterfaceLog.log.info(
            """
            gesture tester window opened for \(name, privacy: .public) on display \(shown.displayID, privacy: .public): \
            \(Int(frame.width), privacy: .public) × \(Int(frame.height), privacy: .public), \
            \(layout == .wide ? "wide" : "regular", privacy: .public) layout
            """)
        bringForward(window)
    }

    /// The screen that shows `display`'s picture: its own, or for a display that mirrors another,
    /// the screen of the display its mirror set shows.
    private static func screen(showing display: UInt32) -> NSScreen? {
        if let own = NSScreen.screens.first(where: { $0.displayID == display }) { return own }
        let primary = CGDisplayPrimaryDisplay(display)
        return NSScreen.screens.first { $0.displayID == primary }
    }

    /// In front, with focus: the steps of `ActivationStep`, as Settings takes them, each logged.
    private func bringForward(_ window: NSWindow) {
        Task { @MainActor [weak self] in
            var step = ActivationStep.cooperative
            while true {
                Self.perform(step, on: window)
                // The answer to an activation arrives on a later turn of the main loop.
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.window === window, window.isVisible else { return }
                let isActive = NSApplication.shared.isActive, isKey = window.isKeyWindow
                InterfaceLog.log.info(
                    "gesture tester after \(String(describing: step), privacy: .public): app active \(isActive), window key \(isKey)")
                guard let next = ActivationStep.next(after: step, isActive: isActive, isKey: isKey) else { return }
                step = next
            }
        }
    }

    private static func perform(_ step: ActivationStep, on window: NSWindow) {
        let app = NSApplication.shared
        switch step {
        case .cooperative:
            app.activate()
        case .becomeRegular:
            InterfaceLog.log.info("gesture tester: activation refused; becoming a regular app while it is open")
            RegularAppHold.hold(.gestureTester)
            app.activate()
        case .force:
            InterfaceLog.log.info("gesture tester: forcing activation")
            (app as ForcedActivation).activateIgnoringOtherApps()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Closes the window up. `releasingHold` false (it is being replaced by another) keeps Tactile a
    /// regular app if the window made it one (`GestureTesterPresenter.Action.releasesHold`).
    private func closeByItself(reason: String, releasingHold: Bool) {
        guard let window else { return }
        isClosingByItself = true
        window.close()
        isClosingByItself = false
        forget(window, releasingHold: releasingHold)
        InterfaceLog.log.info("gesture tester window closed (\(reason, privacy: .public))")
    }

    private func forget(_ closed: NSWindow, releasingHold: Bool) {
        guard window === closed else { return }
        window = nil
        store = nil
        if releasingHold, RegularAppHold.release(.gestureTester) {
            InterfaceLog.log.info("gesture tester closed; back to a menu-bar app")
        }
    }

    // MARK: - NSWindowDelegate

    /// The person closed it (its close button, or Esc, which presses it): the model is told, and the
    /// window goes at once.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !isClosingByItself, let closed = notification.object as? NSWindow, closed === window else { return }
            forget(closed, releasingHold: true)
            guard !isQuitting else { return }
            InterfaceLog.log.info("gesture tester window closed by the person")
            carryOut(presenter.closedByPerson())
        }
    }
}

/// The tester's window: Esc closes it, as its close button does, from whatever has the focus in
/// it, except a text field composing a character.
final class GestureTesterNSWindow: NSWindow {
    /// Titled and closable; not miniaturisable or resizable.
    static let style: NSWindow.StyleMask = [.titled, .closable]

    var onEscape: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, SetUpOverlay.isCancelKey(event.keyCode, modifiers: event.modifierFlags),
            (firstResponder as? NSTextView)?.hasMarkedText() != true, let onEscape
        {
            onEscape()
            return
        }
        super.sendEvent(event)
    }
}

/// The window's content: the tester as its store has it now. Empty for the moment between the
/// tester closing and the window following.
struct GestureTesterRoot: View {
    let store: GestureTesterStore

    var body: some View {
        let _ = store.bodies.count(.root)
        if store.isShown {
            GestureTesterView(store: store, metrics: store.metrics)
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
