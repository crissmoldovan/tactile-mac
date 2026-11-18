// The touchscreen check's window: an ordinary titled window, like the gesture tester's, on the
// touchscreen's own display when Tactile knows it (else the main one), brought to the front and made
// key by the steps Settings uses (`ActivationStep`), so its email field takes typing. One check at a
// time: opening another closes this one first. Closing it (its close button, Esc, quitting, the Mac
// going to sleep) stops the check, lets the device go, and Tactile takes its touchscreen back.

import AppKit
import SwiftUI
import TactileDevices
import TactileScreens

@MainActor
final class SupportCheckWindow: NSObject, NSWindowDelegate {
    static let shared = SupportCheckWindow()

    static let size = CGSize(width: 780, height: 540)

    private var window: GestureTesterNSWindow?
    private var session: SupportCheckSession?
    /// The app's model: what the check tells to let go and take back, and whose snapshot says whether
    /// it can. Set once, as the app starts.
    private var model: (any AppModel)?
    private var isClosingByItself = false
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeByItself(reason: "Tactile is quitting") }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.session?.stop() }
        })
    }

    /// The app's model, once: the check asks it to let go of a touchscreen and to take it back.
    static func startForTheApp(_ model: any AppModel) {
        shared.model = model
    }

    /// Help Me Support This Touchscreen…, for a touchscreen Tactile lists.
    static func open(_ touchscreen: SupportTarget, perform: @escaping PerformCommand) {
        InterfaceLog.log.info("touchscreen check: Help Me Support This Touchscreen… pressed for \(touchscreen.usbID, privacy: .public)")
        let model = shared.model
        shared.open(SupportCheckSession(deviceID: nil, touchscreen: touchscreen, name: touchscreen.name,
                                        perform: model.map { model in { model.perform($0) } } ?? perform,
                                        snapshot: { model?.snapshot }, environment: .live()),
                    display: touchscreen.pairedDisplayID)
    }

    /// Check… in Touchscreen Not Listed?, for a device Tactile doesn't list.
    static func open(_ device: SupportDevice, perform: @escaping PerformCommand) {
        InterfaceLog.log.info("touchscreen check: Check… pressed for \(device.usbID, privacy: .public)")
        shared.open(SupportCheckSession(deviceID: device.id, touchscreen: nil, name: Wording.supportDeviceName(device),
                                        perform: perform, snapshot: { nil }, environment: .live()),
                    display: nil)
    }

    private func open(_ session: SupportCheckSession, display: UInt32?) {
        closeByItself(reason: "another check was asked for")
        let screen = display.flatMap { id in NSScreen.screens.first { $0.displayID == id } } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: Self.size)
        let frame = CGRect(x: (visible.midX - Self.size.width / 2).rounded(), y: (visible.midY - Self.size.height / 2).rounded(),
                           width: Self.size.width, height: Self.size.height)
        let window = GestureTesterNSWindow(contentRect: frame, styleMask: GestureTesterNSWindow.style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.title = Wording.supportWindowTitle(name: session.name)
        window.delegate = self
        window.onEscape = { [weak window] in window?.performClose(nil) }
        let content = NSHostingView(rootView: SupportCheckView(session: session))
        content.sizingOptions = []
        window.contentView = content
        window.setFrame(frame, display: false)
        self.window = window
        self.session = session
        session.close = { [weak window] in window?.performClose(nil) }
        RegularAppHold.opened(.supportCheck)
        bringForward(window)
    }

    /// In front, with focus: the steps of `ActivationStep`, as Settings and the gesture tester take them.
    private func bringForward(_ window: NSWindow) {
        Task { @MainActor [weak self] in
            var step = ActivationStep.cooperative
            while true {
                let app = NSApplication.shared
                switch step {
                case .cooperative:
                    app.activate()
                case .becomeRegular:
                    RegularAppHold.hold(.supportCheck)
                    app.activate()
                case .force:
                    (app as ForcedActivation).activateIgnoringOtherApps()
                }
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.window === window, window.isVisible else { return }
                guard let next = ActivationStep.next(after: step, isActive: app.isActive, isKey: window.isKeyWindow) else { return }
                step = next
            }
        }
    }

    private func closeByItself(reason: String) {
        guard let window else { return }
        isClosingByItself = true
        window.close()
        isClosingByItself = false
        forget()
        InterfaceLog.log.info("touchscreen check window closed (\(reason, privacy: .public))")
    }

    private func forget() {
        session?.stop()
        if session?.closedWhileSending == .mayHaveBeenSent {
            // The window has gone: the person still hears that the report may have reached the site.
            let alert = NSAlert()
            alert.messageText = Wording.sendingMayHaveBeenSent
            alert.alertStyle = .informational
            alert.runModal()
        }
        session = nil
        window = nil
        if RegularAppHold.release(.supportCheck) {
            InterfaceLog.log.info("touchscreen check closed; back to a menu-bar app")
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !isClosingByItself, let closed = notification.object as? NSWindow, closed === window else { return }
            forget()
            InterfaceLog.log.info("touchscreen check window closed by the person")
        }
    }
}
