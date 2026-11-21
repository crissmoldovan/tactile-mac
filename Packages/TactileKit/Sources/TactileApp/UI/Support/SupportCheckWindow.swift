// The touchscreen check's window: an ordinary titled window, like the gesture tester's, on the
// touchscreen's own display when Tactile knows it (else the main one), never larger than what that
// display shows (`SupportCheckWindowFrame`: it can be a short bar), brought to the front and made
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
            MainActor.assumeIsolated { self?.closeByItself(reason: "Tactile is quitting", isQuitting: true) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.session?.sleep() }
        })
    }

    /// The app's model, once: the check asks it to let go of a touchscreen and to take it back.
    static func startForTheApp(_ model: any AppModel) {
        shared.model = model
    }

    /// Check This Touchscreen… (a touchscreen's header, its details beside the menu, the set-up
    /// screens' cards) and Check… (Touchscreen Check, set-up mode's session card), for a touchscreen
    /// Tactile lists.
    static func open(_ touchscreen: SupportTarget, perform: @escaping PerformCommand) {
        InterfaceLog.log.info("touchscreen check: Check This Touchscreen… or Check… pressed for \(touchscreen.usbID, privacy: .public)")
        let model = shared.model
        shared.open(SupportCheckSession(deviceID: nil, touchscreen: touchscreen, name: touchscreen.name,
                                        perform: model.map { model in { model.perform($0) } } ?? perform,
                                        snapshot: { model?.snapshot }, environment: .live()),
                    display: touchscreen.pairedDisplayID)
    }

    /// Check… in Touchscreen Check, for a device Tactile doesn't list.
    static func open(_ device: SupportDevice, perform: @escaping PerformCommand) {
        InterfaceLog.log.info("touchscreen check: Check… pressed for \(device.usbID, privacy: .public)")
        shared.open(SupportCheckSession(deviceID: device.id, touchscreen: nil, name: Wording.supportDeviceName(device),
                                        perform: perform, snapshot: { nil }, environment: .live()),
                    display: nil)
    }

    private func open(_ session: SupportCheckSession, display: UInt32?) {
        closeByItself(reason: "another check was asked for")
        let screen = display.flatMap { id in NSScreen.screens.first { $0.displayID == id } } ?? NSScreen.main ?? NSScreen.screens.first
        let titleBar = Self.titleBarHeight(GestureTesterNSWindow.style)
        let visible = screen?.visibleFrame
            ?? CGRect(origin: .zero, size: CGSize(width: SupportCheckWindowFrame.content.width,
                                                  height: SupportCheckWindowFrame.content.height + titleBar + 2 * SupportCheckWindowFrame.margin))
        let frame = SupportCheckWindowFrame.frame(in: visible, titleBar: titleBar)
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
        InterfaceLog.log.info(
            """
            touchscreen check window: \(Int(frame.width), privacy: .public) × \(Int(frame.height), privacy: .public) \
            in a visible frame of \(Int(visible.width), privacy: .public) × \(Int(visible.height), privacy: .public)
            """)
        bringForward(window)
    }

    /// The height of a title bar of a window of `style`, on this macOS.
    static func titleBarHeight(_ style: NSWindow.StyleMask) -> CGFloat {
        let content = CGRect(x: 0, y: 0, width: 100, height: 100)
        return NSWindow.frameRect(forContentRect: content, styleMask: style).height - content.height
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

    private func closeByItself(reason: String, isQuitting: Bool = false) {
        guard let window else { return }
        isClosingByItself = true
        window.close()
        isClosingByItself = false
        forget(isQuitting: isQuitting)
        InterfaceLog.log.info("touchscreen check window closed (\(reason, privacy: .public))")
    }

    private func forget(isQuitting: Bool = false) {
        session?.stop()
        if let notice = SupportClosingNotice.alert(closedWhileSending: session?.closedWhileSending, isQuitting: isQuitting) {
            // The window has gone: the person still hears that the report may have reached the site.
            let alert = NSAlert()
            alert.messageText = notice.title
            alert.informativeText = notice.detail
            alert.alertStyle = .informational
            alert.runModal()
        } else if isQuitting, session?.closedWhileSending == .mayHaveBeenSent {
            InterfaceLog.log.notice("touchscreen check: Tactile quit while a report was being sent; it may already have reached the site")
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
