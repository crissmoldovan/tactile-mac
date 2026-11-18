// The set-up screens on the displays: borderless windows on every screen at once, above everything
// including full-screen apps and on every Space, for as long as the snapshot has set-up mode or a
// set-up, changing with it. Like Identify's, they are placed by display ID and removed when their
// display goes.
//
// Each screen is two windows:
// - the backdrop, the whole display. In set-up mode's overview it always takes the mouse and
//   swallows it: the click on a card is the choice, and a click beside the cards does nothing.
//   During a flow, where it hides what is beneath (the corners, the size card) it takes the mouse
//   and swallows it, so a click never lands in a window the person can't see
//   (`SetUpScreen.backdropTakesMouse`); elsewhere (the check, and every dimmed display) it ignores
//   the mouse, so another touchscreen's taps and drags, and the person's mouse, go through it to
//   whatever is beneath;
// - where the screen has buttons, a small panel just the size of its cards, above the backdrop: the
//   only part that acts on the mouse. During a flow, a display another touchscreen is paired with
//   has none, and its backdrop always lets clicks through.
// The model draws the check step's touch circles itself, in `TouchCircleOverlay`'s click-through
// window per display at the assistive-technology-high level (1500). These windows sit below it: the
// backdrop at the screen-saver level (1000), the buttons one above (1001). So the circles show over
// everything here, and the check's backdrop is clear and click-through besides.
//
// The keyboard: Esc cancels from any display, whichever app is in front (in set-up mode, it leaves
// the mode). While the screens are up:
// - a local key monitor sees every key that reaches Tactile, and Esc sends `.cancelSetUp`, swallowed;
// - a global key monitor sees the keys that go to every other app, and Esc there sends `.cancelSetUp`
//   too (the app in front sees that Esc as well: a global monitor can only watch). A global key
//   monitor needs Accessibility, which Tactile already has to set anything up; it asks for nothing
//   new. The dimmed and clear backdrops are click-through, so a click on a dimmed display, or another
//   touchscreen's tap, can make the app beneath active at any moment: the global monitor is what
//   keeps Esc working then.
// - For Return, the step's default button (Continue, Done), one card is key: the button panels are
//   non-activating panels that can be key, and one is made key when the screens go up and when the
//   step moves to another display or back to the overview (whose session card takes it), without
//   activating Tactile or changing the app in front. Return is never watched globally.

import AppKit
import SwiftUI
import os

@MainActor
public final class SetUpOverlay {
    public static let shared = SetUpOverlay()

    /// One screen's windows.
    private final class ScreenWindows {
        let backdrop: NSPanel
        let backdropView: NSHostingView<SetUpBackdrop>
        var controls: SetUpControlsPanel?
        var controlsView: FirstClickHostingView<SetUpControls>?
        var screen: SetUpScreen

        init(backdrop: NSPanel, backdropView: NSHostingView<SetUpBackdrop>, screen: SetUpScreen) {
            self.backdrop = backdrop
            self.backdropView = backdropView
            self.screen = screen
        }
    }

    /// By the display ID of the screen they are on.
    private var windows: [UInt32: ScreenWindows] = [:]
    private var plan: [SetUpScreen] = []
    private var perform: PerformCommand = { _ in }
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    /// Whether "no displays for a moment" has been logged, once per gap.
    private var loggedKeeping = false
    /// The screen whose buttons were last given the keyboard, and the step then (nil: the overview).
    private var keyboard: (screenID: UInt32, step: SetUpStepName?)?
    /// Displays already logged as having no screen, so each is logged once per set-up.
    private var loggedUnplaced: Set<UInt32> = []

    public init() {}

    /// Whether a key is the Esc that cancels a set-up: Esc with no ⌘, ⌥ or ⌃ held, so that ⌘-Esc,
    /// ⌥⌘-Esc (Force Quit) and the like, meant for another app or for macOS, never cancel it. Shift
    /// and Caps Lock make no difference.
    static func isCancelKey(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 53 && modifiers.intersection([.command, .option, .control]).isEmpty
    }

    /// Puts up, changes or takes down the screens to match `presentation` (see `SetUpPresentation`),
    /// carrying over from the plan shown until now what only it can tell (see
    /// `SetUpScreens.following`). A set-up with no displays for a moment keeps its screens as they
    /// are.
    func show(_ presentation: SetUpPresentation, perform: @escaping PerformCommand) {
        self.perform = perform
        switch presentation.change {
        case .takeDown:
            plan = []
            tearDown()
        case .keep:
            if !loggedKeeping {
                loggedKeeping = true
                InterfaceLog.log.info("set-up: no displays for the moment; keeping the set-up screens as they are")
            }
        case .show:
            loggedKeeping = false
            plan = SetUpScreens.following(presentation.plan, after: plan)
            if keyMonitor == nil {
                InterfaceLog.log.info("set-up screens up for \(Self.describe(self.plan), privacy: .public)")
                startWatching()
            }
            reconcile()
        }
    }

    // MARK: - Windows

    private func reconcile() {
        var screensByID: [UInt32: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID, screensByID[id] == nil {
                screensByID[id] = screen
            }
        }
        let placed = SetUpScreens.placed(plan, screen: { Self.screenShowing($0, among: screensByID) })
        for display in placed.unplaced where !loggedUnplaced.contains(display) {
            loggedUnplaced.insert(display)
            InterfaceLog.log.info("set-up: display \(display, privacy: .public) has no screen; nothing shown for it")
        }

        let wanted = Set(placed.screens.map(\.screenID))
        for (screenID, gone) in windows where !wanted.contains(screenID) {
            close(gone, on: screenID)
            windows[screenID] = nil
        }
        for (screenID, screen) in placed.screens {
            guard let nsScreen = screensByID[screenID] else { continue }
            if let existing = windows[screenID] {
                update(existing, to: screen, on: nsScreen, screenID: screenID)
            } else {
                windows[screenID] = open(screen, on: nsScreen, screenID: screenID)
            }
        }
        giveKeyboard(placed.screens)
    }

    /// The display ID of the screen that shows `display`'s picture: its own screen, or for a display
    /// that mirrors another, the screen of the display its mirror set shows.
    private static func screenShowing(_ display: UInt32, among screens: [UInt32: NSScreen]) -> UInt32? {
        if screens[display] != nil { return display }
        let primary = CGDisplayPrimaryDisplay(display)
        return screens[primary] != nil ? primary : nil
    }

    private func open(_ screen: SetUpScreen, on nsScreen: NSScreen, screenID: UInt32) -> ScreenWindows {
        let backdrop = NSPanel(
            contentRect: nsScreen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.configure(backdrop, level: .screenSaver)
        backdrop.ignoresMouseEvents = !screen.backdropTakesMouse
        let backdropView = NSHostingView(rootView: SetUpBackdrop(screen: screen, displaySize: nsScreen.frame.size))
        backdropView.appearance = Self.appearance(screen.role.backdropScheme)
        backdrop.contentView = backdropView
        backdrop.setFrame(nsScreen.frame, display: false)
        backdrop.orderFrontRegardless()
        InterfaceLog.log.info(
            "set-up screen opened on display \(screenID, privacy: .public) (\(Self.describe(screen), privacy: .public))")
        let windows = ScreenWindows(backdrop: backdrop, backdropView: backdropView, screen: screen)
        updateControls(windows, on: nsScreen, screenID: screenID)
        return windows
    }

    private func update(_ windows: ScreenWindows, to screen: SetUpScreen, on nsScreen: NSScreen, screenID: UInt32) {
        let before = windows.screen
        windows.screen = screen
        if windows.backdrop.frame != nsScreen.frame {
            windows.backdrop.setFrame(nsScreen.frame, display: true)
        }
        windows.backdropView.rootView = SetUpBackdrop(screen: screen, displaySize: nsScreen.frame.size)
        windows.backdropView.appearance = Self.appearance(screen.role.backdropScheme)
        windows.backdrop.ignoresMouseEvents = !screen.backdropTakesMouse
        if Self.describe(before) != Self.describe(screen) {
            InterfaceLog.log.info(
                "set-up screen on display \(screenID, privacy: .public) now \(Self.describe(screen), privacy: .public)")
        }
        updateControls(windows, on: nsScreen, screenID: screenID)
    }

    /// Puts up, resizes or takes down a screen's buttons.
    private func updateControls(_ windows: ScreenWindows, on nsScreen: NSScreen, screenID: UInt32) {
        let screen = windows.screen
        guard screen.hasControls else {
            if let controls = windows.controls {
                controls.orderOut(nil)
                windows.controls = nil
                windows.controlsView = nil
                InterfaceLog.log.info("set-up buttons closed on display \(screenID, privacy: .public)")
            }
            return
        }
        let root = SetUpControls(
            screen: screen, displaySize: nsScreen.frame.size, perform: { [weak self] command in self?.send(command) })
        let view: FirstClickHostingView<SetUpControls>
        let panel: SetUpControlsPanel
        if let existing = windows.controls, let existingView = windows.controlsView {
            panel = existing
            view = existingView
            view.rootView = root
        } else {
            panel = SetUpControlsPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            Self.configure(panel, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
            panel.becomesKeyOnlyIfNeeded = false
            panel.onEscape = { [weak self] in self?.escape(from: "a set-up card") }
            view = FirstClickHostingView(rootView: root)
            panel.contentView = view
            windows.controls = panel
            windows.controlsView = view
            InterfaceLog.log.info("set-up buttons opened on display \(screenID, privacy: .public)")
        }
        view.appearance = Self.appearance(screen.role.cardScheme)
        view.layoutSubtreeIfNeeded()
        let frame = SetUpScreens.controlsFrame(screen.placement, size: view.fittingSize, on: nsScreen.frame)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func close(_ windows: ScreenWindows, on screenID: UInt32) {
        if let controls = windows.controls {
            controls.orderOut(nil)
            InterfaceLog.log.info("set-up buttons closed on display \(screenID, privacy: .public)")
        }
        windows.backdrop.orderOut(nil)
        InterfaceLog.log.info("set-up screen closed on display \(screenID, privacy: .public)")
    }

    /// The appearance a role asks for (see `SetUpScreenRole.backdropScheme`, `.cardScheme`); nil: the
    /// Mac's.
    private static func appearance(_ scheme: ColorScheme?) -> NSAppearance? {
        switch scheme {
        case .light?: return NSAppearance(named: .aqua)
        case .dark?: return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    private static func configure(_ panel: NSPanel, level: NSWindow.Level) {
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.worksWhenModal = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
    }

    // MARK: - The keyboard

    /// Gives the keyboard to the screen the plan says, when the screens first go up and when the
    /// step moves on or back to the overview; not while the overview's stages change.
    private func giveKeyboard(_ placed: [(screenID: UInt32, screen: SetUpScreen)]) {
        guard let chosen = placed.first(where: { $0.screen.takesKeyboard }),
            let controls = windows[chosen.screenID]?.controls
        else { return }
        let step = chosen.screen.keyboardMoment
        if let keyboard, keyboard.screenID == chosen.screenID, keyboard.step == step { return }
        keyboard = (chosen.screenID, step)
        controls.makeKeyAndOrderFront(nil)
        InterfaceLog.log.info(
            "set-up: keyboard on display \(chosen.screenID, privacy: .public), key \(controls.isKeyWindow), Tactile active \(NSApplication.shared.isActive)")
    }

    private func startWatching() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCancelKey(event.keyCode, modifiers: event.modifierFlags) else { return event }
            MainActor.assumeIsolated { self?.escape(from: "Tactile") }
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCancelKey(event.keyCode, modifiers: event.modifierFlags) else { return }
            Task { @MainActor in self?.escape(from: "another app") }
        }
        if globalKeyMonitor == nil {
            InterfaceLog.log.error("set-up: no global key monitor; Esc works only while Tactile has the keyboard")
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.plan.isEmpty else { return }
                // No screens for a moment while the displays reconfigure: keep what is up.
                guard !NSScreen.screens.isEmpty else { return }
                InterfaceLog.log.info("set-up: the screens changed; placing the set-up screens again")
                self.reconcile()
            }
        }
    }

    private func escape(from source: String) {
        guard !plan.isEmpty else { return }
        InterfaceLog.log.info("set-up: Esc pressed (\(source, privacy: .public)); cancelling")
        perform(.cancelSetUp)
    }

    private func send(_ command: AppCommand) {
        InterfaceLog.log.info("set-up: \(Self.describe(command), privacy: .public) pressed")
        perform(command)
    }

    private func tearDown() {
        guard keyMonitor != nil || !windows.isEmpty else { return }
        for (screenID, open) in windows {
            close(open, on: screenID)
        }
        windows = [:]
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        loggedKeeping = false
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        keyboard = nil
        loggedUnplaced = []
        // Done, Cancel, Finish, Esc, the two minutes without input and a display or touchscreen gone
        // all look the same from here: the snapshot has neither set-up mode nor a set-up.
        InterfaceLog.log.info("set-up ended; set-up screens down")
    }

    // MARK: - Logging

    /// What the screens are up for: set-up mode, or a flow's touchscreen.
    private static func describe(_ plan: [SetUpScreen]) -> String {
        guard let first = plan.first else { return "nothing" }
        if case .overview = first.role { return "set-up mode" }
        return first.touchscreenName + (first.inSetUpMode ? ", in set-up mode" : "")
    }

    private static func describe(_ screen: SetUpScreen) -> String {
        switch screen.role {
        case .overview(let overview):
            var parts: [String] = []
            if let card = overview.card {
                switch card.moment {
                case .offering: parts.append(card.touchedFirst == nil ? "offering" : "offering, touched first")
                case .touchHere: parts.append("touch here")
                case .waitingElsewhere: parts.append("waiting elsewhere")
                }
                if card.isJustSetUp { parts.append("just set up") }
            }
            if let session = overview.session {
                parts.append("session card" + (session.notice == nil ? "" : ", with a notice"))
            }
            return "overview: " + (parts.isEmpty ? "no card" : parts.joined(separator: ", "))
        case .corners(_, let index, let problem):
            return "corners \(index + 1) of \(SetUpScreens.targetCount)" + (problem.map { ", \($0.rawValue)" } ?? "")
                + (screen.restartedCorners ? ", started again" : "")
        case .size: return "size"
        case .check: return "check"
        case .elsewhere: return "elsewhere"
        }
    }

    private static func describe(_ command: AppCommand) -> String {
        switch command {
        case .cancelSetUp: return "Cancel or Finish"
        case .setUpBack: return "Back"
        case .setUpChoose(let display): return "This One or Set Up Again Here (display \(display))"
        case .beginSetUp(_, .test): return "Test"
        case .setUpRedo: return "Redo"
        case .setUpDone: return "Done"
        case .setUpConfirmSize(let inches): return "Continue (\(inches.map { "\($0)″" } ?? "as reported"))"
        default: return "\(command)"
        }
    }
}

/// A set-up screen's buttons: a borderless, non-activating panel that can take the keyboard without
/// activating Tactile, and that acts on the first click even when it isn't key.
final class SetUpControlsPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Return held: only its first press counts, so a repeat can't reach Done.
        if event.type == .keyDown, SetUpScreens.dropsKeyDown(keyCode: event.keyCode, isARepeat: event.isARepeat) {
            return
        }
        // Key first, so the click that makes it key also presses the button under it.
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// A hosting view whose first click acts, in a window that isn't key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
