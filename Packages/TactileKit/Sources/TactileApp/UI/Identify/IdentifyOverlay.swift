import AppKit
import SwiftUI

/// Identify: for a few seconds, each display's label in large type on that display, in a
/// borderless, click-through window over everything. Called by the Identify button directly; it
/// changes nothing in the app.
@MainActor
public final class IdentifyOverlay {
    public static let shared = IdentifyOverlay()

    /// How long the labels stay.
    public var duration: TimeInterval = 4

    private var windows: [NSWindow] = []
    private var hideTask: Task<Void, Never>?
    /// While labels are shown: displays changing take them away, since AppKit would move the
    /// label of a display that went to another one.
    private var screenObserver: NSObjectProtocol?

    public init() {}

    /// Shows each display's label on it. Pressing Identify again starts the time again. A display
    /// with no screen of its own (one that mirrors another) shows nothing.
    public func show(_ displays: [DisplaySnapshot]) {
        hide(animated: false)
        for display in displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.id }) else { continue }
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: IdentifyCard(
                name: display.name, detail: display.detail, screenSize: screen.frame.size))
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide(animated: false) }
        }
        hideTask = Task { [weak self, duration] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    /// Takes the labels away.
    public func hide(animated: Bool = true) {
        hideTask?.cancel()
        hideTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        let leaving = windows
        windows = []
        guard animated else {
            leaving.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            leaving.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            Task { @MainActor in leaving.forEach { $0.orderOut(nil) } }
        }
    }
}

extension NSScreen {
    /// The CoreGraphics display ID of this screen.
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// One display's label, as Identify shows it: the name large, the telling-apart line beneath.
struct IdentifyCard: View {
    var name: String
    var detail: String
    /// The size of the display it is shown on, in points; the type scales with it.
    var screenSize: CGSize

    /// Large enough to read from across the desk, and never wider than the display.
    private var nameSize: CGFloat {
        min(max(min(screenSize.width * 0.05, screenSize.height * 0.12), 36), 180)
    }

    var body: some View {
        VStack(spacing: nameSize * 0.18) {
            Text(name)
                .font(.system(size: nameSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: nameSize * 0.42))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, nameSize * 0.55)
        .padding(.vertical, nameSize * 0.4)
        .background(
            RoundedRectangle(cornerRadius: nameSize * 0.4, style: .continuous)
                .fill(Color.black.opacity(0.72)))
        .frame(maxWidth: screenSize.width * 0.88)
        .frame(width: screenSize.width, height: screenSize.height)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}
