// The updater's rows in the menu-bar panel, and its group in General.

import SwiftUI
import TactileUpdates

/// Update to <version>… in the panel: tinted with the accent colour even before the pointer is on it,
/// with its arrow, so a newer version isn't missed; otherwise a row like the others.
struct PanelUpdateRow: View {
    var title: String
    var action: @MainActor () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(isHovered ? Color.white : Color.accentColor)
                Text(title)
                    .fontWeight(.semibold)
                Spacer(minLength: 12)
            }
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovered ? Color.accentColor : Color.accentColor.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Check for Updates… in the panel, near Settings…, and beneath it what is under way or what the
/// last manual check or install said.
struct PanelCheckForUpdatesRows: View {
    var updates: UpdateMenuContent
    var check: @MainActor () -> Void

    var body: some View {
        PanelRowButton(title: Wording.checkForUpdates, isEnabled: updates.canCheck, action: check)
        if let line = updates.line {
            PanelReason(text: line)
        }
    }
}

/// General's Updates group, when the app has an updater (never in tests or previews), or saying that
/// updates are off in a build that doesn't update itself.
struct UpdatesSection: View {
    private let updates = AppUpdates.shared

    var body: some View {
        if let controller = updates.controller {
            UpdatesSectionContent(
                content: UpdatesSettingsContent(controller.state),
                setAutomatic: { controller.setChecksAutomatically($0) },
                press: { opensUpdate in opensUpdate ? updates.showUpdate() : updates.check() })
        } else if updates.isOff {
            UpdatesOffSectionContent()
        }
    }
}

/// General's Updates group in a build that doesn't update itself: that, and nothing else.
struct UpdatesOffSectionContent: View {
    var body: some View {
        Section {
            Text(Wording.updatesOff)
        } header: {
            Text(Wording.updates)
        }
    }
}

/// The group drawn from its content: Check for updates automatically, with what it does; when the
/// last check was, and Check for Updates… (or Update to <version>…).
struct UpdatesSectionContent: View {
    var content: UpdatesSettingsContent
    var setAutomatic: @MainActor (Bool) -> Void
    var press: @MainActor (_ opensUpdate: Bool) -> Void

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { content.checksAutomatically }, set: { setAutomatic($0) })) {
                Text(Wording.checkAutomatically)
                Text(content.explanation)
            }
            .toggleStyle(.switch)
            LabeledContent {
                Button(content.buttonTitle) { press(content.buttonOpensUpdate) }
                    .disabled(!content.buttonIsEnabled)
            } label: {
                Text(content.lastChecked)
                if let line = content.line {
                    Text(line)
                }
            }
        } header: {
            Text(Wording.updates)
        }
    }
}
