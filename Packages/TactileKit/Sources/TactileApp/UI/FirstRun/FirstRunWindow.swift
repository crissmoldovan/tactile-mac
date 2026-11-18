// The first-run window (mockup 10): when the model offers set-up to touchscreens (`offerSetUpTo`), a
// small window on the main display names every one of them, with Set Up… and Not Now. Set Up…
// begins set-up mode, which covers them all; Not Now declines each one named. It replaces 0.2.0's
// Settings opening by itself while a touchscreen was unpaired. The model offers each touchscreen
// once, so the window is shown once per touchscreen.
//
// A titled, non-activating panel at the floating level: it comes up in front of the person's
// windows without taking the keyboard or the app in front from them, and its buttons act on the
// first click. The person closing it with its close button (or ⌘W) counts as Not Now; a close at
// quit, or any close nobody asked for, counts as nothing. After Set Up… the window goes, and comes
// back if the set-up didn't start (`FirstRunPresenter`).

import AppKit
import SwiftUI

/// What the first-run window does, kept pure: shown for the model's offer; taken down after Set Up…
/// while the set-up is awaited, and back if it didn't start (the model refuses a set-up during a
/// sub-second display reconfiguration, its offer stands, and nothing in the snapshot changes);
/// Not Now only for the person's own close.
struct FirstRunPresenter: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case nothing
        /// Put the window up for this offer, or change it to this offer.
        case show(FirstRunOffer)
        /// Take the window down, saying why in the log.
        case close(String)
        /// Take the window down after Set Up…, and call `graceOver(wait:)` with this wait's number
        /// after `grace`.
        case awaitSetUp(FirstRunOffer, wait: Int)
    }

    /// What a close the window didn't make itself means.
    enum Closed: Equatable, Sendable {
        /// The person closed it: send Not Now for this offer.
        case notNow(FirstRunOffer)
        /// Anything else: nothing is sent; the reason is logged.
        case quietly(String)
    }

    /// How long after Set Up… a set-up that hasn't started counts as refused.
    static let grace: Duration = .milliseconds(1500)

    /// The offer the window is up for.
    private(set) var shown: FirstRunOffer?
    /// The offer Set Up… was pressed for, while the set-up is awaited.
    private(set) var awaited: FirstRunOffer?
    /// The number of the last wait begun: a timer for an earlier one ends nothing.
    private(set) var wait = 0
    /// The model's offer, as last told.
    private(set) var latest: FirstRunOffer?

    /// The model's offer changed (the snapshot follower tells only changes).
    mutating func told(_ offer: FirstRunOffer?) -> Action {
        latest = offer
        guard let offer else {
            awaited = nil
            guard shown != nil else { return .nothing }
            shown = nil
            return .close("the offer was withdrawn")
        }
        if offer == awaited { return .nothing }
        awaited = nil
        guard offer != shown else { return .nothing }
        shown = offer
        return .show(offer)
    }

    mutating func pressedSetUp() -> Action {
        guard let offer = shown else { return .nothing }
        shown = nil
        awaited = offer
        wait += 1
        return .awaitSetUp(offer, wait: wait)
    }

    mutating func pressedNotNow() -> Action {
        guard shown != nil else { return .nothing }
        shown = nil
        awaited = nil
        return .close("Not Now")
    }

    /// The grace after Set Up… numbered `wait` is over. A set-up that started took the offer away
    /// (none is made while one runs); if the same offer still stands, it didn't start, and the window
    /// comes back. The timer of an earlier wait ends nothing.
    mutating func graceOver(wait: Int) -> Action {
        guard wait == self.wait, let offer = awaited else { return .nothing }
        awaited = nil
        guard latest == offer else { return .nothing }
        shown = offer
        return .show(offer)
    }

    /// The window closed without Tactile closing it: Not Now only when the person closed it while
    /// Tactile isn't quitting.
    mutating func closed(byPerson: Bool, quitting: Bool) -> Closed {
        guard let offer = shown else { return .quietly("no window up") }
        shown = nil
        if quitting { return .quietly("Tactile is quitting") }
        return byPerson ? .notNow(offer) : .quietly("closed by macOS")
    }
}

@MainActor
final class FirstRunWindow: NSObject, NSWindowDelegate {
    static let shared = FirstRunWindow()

    private var panel: NSPanel?
    private var presenter = FirstRunPresenter()
    private var perform: PerformCommand = { _ in }
    /// Set while Tactile closes the window itself, so that close isn't taken for anything else.
    private var isClosingByItself = false
    /// Set when the person asks the window to close (its close button, ⌘W): `windowShouldClose`
    /// is asked then, and not when the app quits or Tactile closes it.
    private var isClosedByPerson = false
    private var isQuitting = false
    private var quitObserver: NSObjectProtocol?
    /// The timer of the wait after Set Up…, cancelled by a new wait or a change of offer.
    private var graceTimer: Task<Void, Never>?

    override init() {
        super.init()
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isQuitting = true
                if self.panel != nil {
                    self.closeByItself(reason: "Tactile is quitting")
                }
            }
        }
    }

    /// The model's offer, as the snapshot follower tells it: the window for it, or none.
    func show(_ offer: FirstRunOffer?, perform: @escaping PerformCommand) {
        self.perform = perform
        let action = presenter.told(offer)
        if presenter.awaited == nil {
            graceTimer?.cancel()
            graceTimer = nil
        }
        carryOut(action)
    }

    private func carryOut(_ action: FirstRunPresenter.Action) {
        switch action {
        case .nothing:
            break
        case .show(let offer):
            put(up: offer)
        case .close(let reason):
            closeByItself(reason: reason)
        case .awaitSetUp(_, let wait):
            closeByItself(reason: "Set Up…; waiting for the set-up to start")
            graceTimer?.cancel()
            graceTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: FirstRunPresenter.grace)
                guard !Task.isCancelled, let self else { return }
                let action = self.presenter.graceOver(wait: wait)
                if case .show = action {
                    InterfaceLog.log.info("first-run window: the set-up didn't start; the offer stands, so it is back")
                }
                self.carryOut(action)
            }
        }
    }

    private func put(up offer: FirstRunOffer) {
        let names = Wording.list(offer.names)
        let view = FirstClickHostingView(rootView: FirstRunView(
            names: offer.names,
            setUp: { [weak self] in self?.answer(setUp: true) },
            notNow: { [weak self] in self?.answer(setUp: false) }))
        let panel = self.panel ?? makePanel()
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        if let main = NSScreen.screens.first {
            let visible = main.visibleFrame
            panel.setFrameOrigin(CGPoint(
                x: (visible.midX - panel.frame.width / 2).rounded(),
                y: (visible.minY + visible.height * 0.62 - panel.frame.height / 2).rounded()))
        }
        if self.panel == nil {
            self.panel = panel
            InterfaceLog.log.info("first-run window opened for \(names, privacy: .public)")
        } else {
            InterfaceLog.log.info("first-run window now for \(names, privacy: .public)")
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = Wording.firstRunWindowTitle
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        return panel
    }

    private func answer(setUp: Bool) {
        guard let offer = presenter.shown else { return }
        InterfaceLog.log.info("first-run window: \(setUp ? "Set Up…" : "Not Now", privacy: .public)")
        carryOut(setUp ? presenter.pressedSetUp() : presenter.pressedNotNow())
        for command in setUp ? [offer.setUpCommand] : offer.notNowCommands {
            perform(command)
        }
    }

    private func closeByItself(reason: String) {
        guard let panel else { return }
        isClosingByItself = true
        panel.close()
        isClosingByItself = false
        self.panel = nil
        InterfaceLog.log.info("first-run window closed (\(reason, privacy: .public))")
    }

    // MARK: - NSWindowDelegate

    /// Asked when the person closes the window (its close button, ⌘W), not at quit.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated { isClosedByPerson = true }
        return true
    }

    /// A close Tactile didn't make: Not Now if the person made it, else nothing but a log line.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !isClosingByItself else { return }
            let byPerson = isClosedByPerson
            isClosedByPerson = false
            panel = nil
            switch presenter.closed(byPerson: byPerson, quitting: isQuitting) {
            case .notNow(let offer):
                InterfaceLog.log.info("first-run window closed by its close button: Not Now")
                for command in offer.notNowCommands {
                    perform(command)
                }
            case .quietly(let reason):
                InterfaceLog.log.info("first-run window closed (\(reason, privacy: .public)); nothing sent")
            }
        }
    }
}

/// The first-run window's content: the touchscreen tile, which touchscreens aren't set up and what
/// setting up takes, Not Now and Set Up….
struct FirstRunView: View {
    var names: [String]
    var setUp: @MainActor () -> Void
    var notNow: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 52, height: 52)
                    .overlay(TouchGlyphView(color: .white).frame(width: 32, height: 32))
                    .shadow(color: .black.opacity(0.18), radius: 0.75, y: 0.5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Wording.firstRunTitle(names: names))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Wording.firstRunMessage(count: names.count))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 300, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(Wording.firstRunNotNow, action: notNow)
                    .keyboardShortcut(.cancelAction)
                Button(Wording.firstRunSetUp, action: setUp)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .fixedSize()
    }
}
