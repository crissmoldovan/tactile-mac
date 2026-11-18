import AppKit
import SwiftUI
import TactileScreens

/// The menu-bar panel, for a `MenuBarExtra` in the `.window` style, as the owner chose it from the
/// mockups: Tactile with its switch; Update to <version>…, prominent, while a newer version is
/// known; any warning, with its button; one row for each touchscreen, with its dot, its name, its
/// display's name or its state, and a chevron; Set Up Touchscreens…, with why it can't be used when
/// it can't; Check for Updates…, with what is under way beneath it; Settings…; Quit Tactile. The
/// pointer resting on a touchscreen's row, as on a submenu's item, or choosing the row, opens its
/// details beside the panel (`TouchscreenDetailsWindow`): its quick controls, Gesture Tester…, its
/// set-up and its pane.
///
/// SwiftUI has no API to close a `.window`-style extra from code. Choosing Settings… asks SwiftUI's
/// own `dismiss` to close it, and the window that then comes forward takes the focus from it (Check
/// for Updates… and Update to <version>… close it the same way before the update window shows); if
/// the panel stays open on the first run, `MenuBarMenu` below is the same content as a plain menu,
/// and `TactileScenes` switches to it by using it with `.menuBarExtraStyle(.menu)`.
public struct MenuBarView<Model: AppModel>: View {
    private let model: Model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        // The steady snapshot: the gesture tester's feed doesn't draw the panel again.
        let snapshot = model.steadySnapshot
        let details = TouchscreenDetailsWindow.shared
        let content = MenuBarContent(snapshot)
        MenuBarPanel(
            content: content,
            perform: { model.perform($0) },
            openSettings: {
                closeMenu()
                SettingsWindow.open(openWindow, reason: .menu)
            },
            close: { closeMenu() },
            quit: { NSApplication.shared.terminate(nil) },
            detailsShown: details.shown,
            choose: { id, anchor in
                details.choose(id, anchor: anchor) {
                    TouchscreenDetailsRoot(model: model, id: id, actions: actions)
                }
            },
            updates: AppUpdates.shared.menuContent,
            checkForUpdates: {
                closeMenu()
                AppUpdates.shared.check()
            },
            openUpdate: {
                closeMenu()
                AppUpdates.shared.showUpdate()
            })
            .onChange(of: content) { details.follow(content) }
            .onDisappear { details.close() }
    }

    /// What the details do beyond sending a command: close the menu, open Settings on a pane.
    private var actions: TouchscreenDetailsActions {
        let openWindow = openWindow
        let dismiss = dismiss
        return TouchscreenDetailsActions(
            closeMenu: {
                TouchscreenDetailsWindow.shared.close()
                dismiss()
            },
            openSettings: { pane in
                TouchscreenDetailsWindow.shared.close()
                dismiss()
                SettingsWindow.open(openWindow, reason: .menu, pane: pane)
            })
    }

    private func closeMenu() {
        TouchscreenDetailsWindow.shared.close()
        dismiss()
    }
}

/// The panel itself, from the menu's content: drawn here, and rendered in tests.
struct MenuBarPanel: View {
    var content: MenuBarContent
    var perform: PerformCommand
    var openSettings: @MainActor () -> Void
    var close: @MainActor () -> Void
    var quit: @MainActor () -> Void
    /// The touchscreen whose details are open: its row stays highlighted, as a submenu's item does.
    var detailsShown: TouchscreenID? = nil
    /// A touchscreen's row chosen, or the pointer resting on it, with the view its row is drawn in,
    /// for the details to sit beside.
    var choose: @MainActor (TouchscreenID, NSView?) -> Void = { _, _ in }
    /// The updater's rows; nil while there is no updater (tests, previews), when they aren't shown.
    var updates: UpdateMenuContent? = nil
    var checkForUpdates: @MainActor () -> Void = {}
    var openUpdate: @MainActor () -> Void = {}

    static let width: CGFloat = 336

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Wording.tactile).fontWeight(.semibold)
                Spacer(minLength: 12)
                Toggle(Wording.tactile, isOn: Binding(get: { content.isOn }, set: { perform(.setOn($0)) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

            PanelSeparator()

            if let title = updates?.updateTitle {
                PanelUpdateRow(title: title, action: openUpdate)
                PanelSeparator()
            }

            if !content.warnings.isEmpty {
                ForEach(content.warnings, id: \.warning) { warning in
                    PanelWarningRow(warning: warning)
                    if let action = warning.action {
                        PanelRowButton(title: action.title, indent: 25) {
                            WarningActions.run(action.kind, perform: perform)
                            close()
                        }
                    }
                }
                PanelSeparator()
            }

            Text(Wording.touchscreens)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 3)
                .padding(.bottom, 2)
            ForEach(content.touchscreens) { touchscreen in
                PanelTouchscreenRow(
                    touchscreen: touchscreen, detailsShown: detailsShown,
                    choose: { anchor in choose(touchscreen.id, anchor) })
            }
            if content.touchscreens.isEmpty {
                Text(Wording.noTouchscreens)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }

            PanelSeparator()
            PanelRowButton(title: Wording.setUpTouchscreens, isEnabled: content.setUp == .available) {
                perform(SetUpModeAvailability.command)
                close()
            }
            if let reason = content.setUp.reason {
                PanelReason(text: Wording.setUpModeUnavailable(reason))
            }

            PanelSeparator()
            if let updates {
                PanelCheckForUpdatesRows(updates: updates, check: checkForUpdates)
            }
            PanelRowButton(title: Wording.menuSettings, shortcut: "⌘,", action: openSettings)
                .keyboardShortcut(",")
            PanelSeparator()
            PanelRowButton(title: Wording.menuQuit, shortcut: "⌘Q", action: quit)
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: Self.width)
        // The pointer followed over the whole panel, for the details to open and close as it goes.
        .background(MenuPointerArea())
    }
}

/// A touchscreen in the panel: one row, its dot, its name, its display's name or its state, and a
/// chevron. The pointer resting on it opens its details beside the panel, as a submenu opens
/// (`MenuDetailsHover`); clicking it, tapping it, or Return while it has the keyboard's focus shows
/// them at once. Highlighted while its details are open, and under the pointer unless another row's
/// details are; greyed, as the menu has always greyed a touchscreen whose switch can't be used.
struct PanelTouchscreenRow: View {
    var touchscreen: MenuBarContent.Touchscreen
    /// The touchscreen whose details are open, this one's or another's.
    var detailsShown: TouchscreenID?
    var choose: @MainActor (NSView?) -> Void

    @State private var isHovered = false
    /// The view the row is drawn in, for the details to sit beside.
    @State private var anchor = RowAnchor.Box()

    /// Whether the row of `id` is lit: while its details are open, and under the pointer unless
    /// another row's are. So one row is lit at a time while details are up, the one they are for, as
    /// a submenu's item stays lit while the pointer crosses other items on its way to the submenu;
    /// the lit row follows the details when they move.
    static func isLit(_ id: TouchscreenID, hovered: Bool, detailsShown: TouchscreenID?) -> Bool {
        detailsShown == id || (hovered && detailsShown == nil)
    }

    var body: some View {
        let isShowingDetails = detailsShown == touchscreen.id
        let isLit = Self.isLit(touchscreen.id, hovered: isHovered, detailsShown: detailsShown)
        Button {
            choose(anchor.view)
        } label: {
            HStack(spacing: 8) {
                if isLit, touchscreen.indicator == .inactive {
                    // The hollow ring, white on the highlight.
                    Circle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: 8, height: 8)
                } else {
                    StatusDot(indicator: touchscreen.indicator)
                }
                Text(touchscreen.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                Text(touchscreen.detail)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isLit ? Color.white.opacity(0.85) : Color(nsColor: touchscreen.isDimmed ? .tertiaryLabelColor : .secondaryLabelColor))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isLit ? Color.white : Color.secondary)
            }
            .foregroundStyle(isLit ? Color.white : touchscreen.isDimmed ? Color(nsColor: .tertiaryLabelColor) : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isLit ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RowAnchor(id: touchscreen.id, box: anchor, choose: choose))
        .anchorPreference(key: DetailsRowBounds.self, value: .bounds) { isShowingDetails ? $0 : nil }
        .onHover { isHovered = $0 }
        .onKeyPress(.return) {
            choose(anchor.view)
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(touchscreen.name)
        .accessibilityValue(touchscreen.detail)
        .accessibilityHint(Wording.menuShowsDetails)
        .accessibilityAddTraits(.isButton)
    }
}

/// Where the row whose details are open is, for drawing the details beside it as the window puts
/// them (`MenuDetailsPlacement`), in the renders.
struct DetailsRowBounds: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A quiet line beneath an item that can't be used: why.
struct PanelReason: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.bottom, 3)
    }
}

/// A warning in the panel: its title, and what it means beneath.
struct PanelWarningRow: View {
    var warning: MenuBarContent.Warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                Text(warning.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

/// A row that acts like a menu item: highlighted under the pointer, with its shortcut on the right.
struct PanelRowButton: View {
    var title: String
    var shortcut: String?
    /// Lines the title up with text further in, such as a warning's title.
    var indent: CGFloat
    /// A row that can't be used is greyed and never highlighted.
    var isEnabled: Bool
    var action: @MainActor () -> Void

    @State private var isHovered = false

    init(title: String, shortcut: String? = nil, indent: CGFloat = 0, isEnabled: Bool = true,
         action: @escaping @MainActor () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.indent = indent
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        let isHovered = isHovered && isEnabled
        Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 18)
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .foregroundStyle(isHovered ? Color.white : isEnabled ? Color.primary : Color(nsColor: .tertiaryLabelColor))
            .padding(.leading, indent)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isHovered ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { self.isHovered = $0 }
    }
}

struct PanelSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }
}

/// The same content as a plain menu, for `.menuBarExtraStyle(.menu)`: the fallback should the
/// `.window` panel misbehave on the first run. Checkmarks stand in for the switches, and each
/// touchscreen's details are its submenu.
struct MenuBarMenu<Model: AppModel>: View {
    let model: Model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let content = MenuBarContent(model.steadySnapshot)
        let updates = AppUpdates.shared.menuContent
        Toggle(Wording.menuTactileOn, isOn: Binding(get: { content.isOn }, set: { model.perform(.setOn($0)) }))
        if let title = updates?.updateTitle {
            Button(title) { AppUpdates.shared.showUpdate() }
        }
        if !content.warnings.isEmpty {
            Divider()
            ForEach(content.warnings, id: \.warning) { warning in
                Text(warning.title)
                if let action = warning.action {
                    Button(action.title) { WarningActions.run(action.kind, perform: { model.perform($0) }) }
                }
            }
        }
        Divider()
        Section(Wording.touchscreens) {
            ForEach(content.touchscreens) { touchscreen in
                Menu(Wording.menuRow(name: touchscreen.name, detail: touchscreen.detail)) {
                    TouchscreenDetailsMenu(
                        details: touchscreen.details, perform: { model.perform($0) },
                        openSettings: { SettingsWindow.open(openWindow, reason: .menu, pane: $0) })
                }
            }
        }
        Divider()
        Button(Wording.setUpTouchscreens) { model.perform(SetUpModeAvailability.command) }
            .disabled(content.setUp != .available)
        if let reason = content.setUp.reason {
            Text(Wording.setUpModeUnavailable(reason))
        }
        Divider()
        if let updates {
            Button(Wording.checkForUpdates) { AppUpdates.shared.check() }
                .disabled(!updates.canCheck)
            if let line = updates.line {
                Text(line)
            }
        }
        Button(Wording.menuSettings) { SettingsWindow.open(openWindow, reason: .menu) }
            .keyboardShortcut(",")
        Divider()
        Button(Wording.menuQuit) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The menu-bar icon, which also runs the launch check (see `LaunchCheck`) and answers requests
/// for Settings from outside the scenes (see `SettingsRequests`): the label is the one view that
/// exists from launch, and only it can reach SwiftUI's `openWindow`. The set-up screens and the
/// first-run window don't depend on it: they follow the snapshot themselves (`SnapshotFollower`).
struct MenuBarLabel<Model: AppModel>: View {
    let model: Model
    @Environment(\.openWindow) private var openWindow
    private let requests = SettingsRequests.shared

    var body: some View {
        // The steady snapshot: the gesture tester's feed doesn't set the icon again.
        let state = MenuBarIcon.State(model.steadySnapshot)
        Image(nsImage: MenuBarIcon.image(state))
            .accessibilityLabel(state.accessibilityDescription)
            // `initial`: a request posted before the label was ready, or while it was rebuilt, is
            // still answered, once; with none waiting, the first call does nothing.
            .onChange(of: requests.count, initial: true) {
                guard let reason = requests.takeUnanswered() else { return }
                SettingsWindow.open(openWindow, reason: reason)
            }
            .task {
                await LaunchCheck.shared.run(
                    wait: { try await Task.sleep(for: LaunchCheck.delay) },
                    snapshot: { model.snapshot },
                    open: { SettingsWindow.open(openWindow, reason: .launch) })
            }
    }
}
