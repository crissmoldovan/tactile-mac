// The update window: what a check found, or a newer version's notes with Install and Relaunch and
// Later, and the progress of an install.
//
// The first-run window's kind: a small titled, non-activating panel at the floating level, in the
// middle of the main display's upper part, whose buttons act on the first click. It is opened from
// the menu-bar panel the way Settings is, the panel closing first because the person chose an item
// that opens a window; showing it never closes the panel by itself. Closing it is Later or OK, and
// stops nothing under way.

import AppKit
import SwiftUI
import TactileUpdates

@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    static let shared = UpdateWindow()

    static let width: CGFloat = 440

    private var panel: NSPanel?
    private weak var controller: UpdateController?
    /// Set while Tactile closes the window itself.
    private var isClosingByItself = false

    /// Shows the window for `controller`'s state, or brings it forward.
    func show(_ controller: UpdateController) {
        self.controller = controller
        if let panel {
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }
        let panel = makePanel()
        let view = FirstClickHostingView(rootView: UpdateWindowView(
            controller: controller,
            act: { [weak self] action in self?.act(action) },
            fit: { [weak self] in self?.fit() }))
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        if let main = NSScreen.screens.first {
            let visible = main.visibleFrame
            panel.setFrameOrigin(CGPoint(
                x: (visible.midX - panel.frame.width / 2).rounded(),
                y: (visible.minY + visible.height * 0.62 - panel.frame.height / 2).rounded()))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        InterfaceLog.log.info("update window opened")
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = Wording.updateWindowTitle
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

    /// A button.
    private func act(_ action: UpdateWindowContent.Action) {
        guard let controller else { return }
        switch action {
        case .install:
            controller.install()
        case .cancel:
            let wasChecking = controller.state.phase == .checking(manual: true)
            controller.cancel()
            if wasChecking { closeByItself() }
        case .later, .ok:
            controller.dismissNotice()
            closeByItself()
        }
    }

    /// Fits the window to its content after a change, keeping its top edge where it was.
    private func fit() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let view = panel.contentView else { return }
            let size = view.fittingSize
            var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - frame.height)
            panel.setFrame(frame, display: true)
        }
    }

    private func closeByItself() {
        guard let panel else { return }
        isClosingByItself = true
        panel.close()
        isClosingByItself = false
        self.panel = nil
    }

    // MARK: - NSWindowDelegate

    /// The person closed the window (its close button, ⌘W): Later or OK, unless something is under
    /// way, which goes on.
    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard !isClosingByItself else { return }
            panel = nil
            if let controller, UpdateWindowContent(controller.state).closingDismisses {
                controller.dismissNotice()
            }
        }
    }
}

/// The window's content, following the updater's state.
struct UpdateWindowView: View {
    let controller: UpdateController
    var act: @MainActor (UpdateWindowContent.Action) -> Void
    var fit: @MainActor () -> Void

    var body: some View {
        let content = UpdateWindowContent(controller.state)
        UpdateWindowLayout(content: content, act: act)
            .onChange(of: content) { fit() }
    }
}

/// The window drawn from its content: the app's tile; the title, the version running, the notes;
/// what is under way or went wrong; the buttons.
struct UpdateWindowLayout: View {
    var content: UpdateWindowContent
    var act: @MainActor (UpdateWindowContent.Action) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.gradient)
                    .frame(width: 52, height: 52)
                    .overlay(TouchGlyphView(color: .white).frame(width: 32, height: 32))
                    .shadow(color: .black.opacity(0.18), radius: 0.75, y: 0.5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                    if !content.notes.isEmpty {
                        UpdateNotes(paragraphs: content.notes)
                            .padding(.top, 4)
                    }
                    if let line = content.line {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if content.isBusy {
                                ProgressView().controlSize(.small)
                            } else if content.lineIsProblem {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text(line)
                                .foregroundStyle(content.lineIsProblem ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    } else if content.isBusy {
                        ProgressView().controlSize(.small).padding(.top, 4)
                    }
                }
                .frame(width: UpdateWindow.width - 22 * 2 - 52 - 14, alignment: .leading)
            }
            HStack(spacing: 10) {
                if let secondary = content.secondary {
                    Button(secondary.title) { act(secondary) }
                        .keyboardShortcut(.cancelAction)
                }
                if let primary = content.primary {
                    Button(primary.title) { act(primary) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!content.primaryIsEnabled)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .fixedSize()
    }
}

/// The release notes: a paragraph a line, in a box that scrolls, at a fixed height, when they are
/// long.
struct UpdateNotes: View {
    var paragraphs: [String]

    static let scrollingHeight: CGFloat = 180

    /// Whether the notes are short enough to show whole: five paragraphs, 420 characters.
    static func fitWhole(_ paragraphs: [String]) -> Bool {
        paragraphs.count <= 5 && paragraphs.reduce(0) { $0 + $1.count } <= 420
    }

    var body: some View {
        Group {
            if Self.fitWhole(paragraphs) {
                text
            } else {
                ScrollView { text }
                    .frame(height: Self.scrollingHeight)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
        .textSelection(.enabled)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
    }
}
