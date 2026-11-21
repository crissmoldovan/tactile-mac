import SwiftUI
import TactileDevices

/// Touchscreen Check, after General in the sidebar: what the check is for, in a line; every
/// connected touchscreen Tactile lists, with its name, its device's own name and Check…; then the
/// touch devices Tactile doesn't list (Touchscreen Not Listed?), each with Check…, or a line saying
/// there are none. What it lists, and whether each Check… can be used, is `TouchscreenCheckList`.
/// The devices Tactile doesn't list are watched while this pane is shown, and not otherwise.
struct TouchscreenCheckPane: View {
    var snapshot: AppSnapshot
    var perform: PerformCommand
    /// The touch devices Tactile doesn't list; nil where there are none to show.
    var notListed: NotListedDevices? = nil

    var body: some View {
        let list = TouchscreenCheckList(
            snapshot, devices: notListed?.devices ?? [], finishing: SupportChecksFinishing.shared)
        Form {
            Section {
                TouchscreenCheckHeader()
            }
            Section {
                if list.listed.isEmpty {
                    Text(Wording.noTouchscreens)
                        .foregroundStyle(.secondary)
                }
                ForEach(list.listed) { listed in
                    CheckRow(title: listed.name, detail: listed.deviceName, reason: listed.reason,
                             availability: listed.availability) {
                        SupportCheckWindow.open(listed.target, perform: perform)
                    }
                }
            } header: {
                Text(Wording.touchscreens)
            }
            Section {
                if list.unlisted.isEmpty {
                    Text(Wording.notListedNone)
                        .foregroundStyle(.secondary)
                }
                ForEach(list.unlisted) { unlisted in
                    CheckRow(title: unlisted.name, detail: unlisted.detail, reason: unlisted.reason,
                             availability: unlisted.availability) {
                        SupportCheckWindow.open(unlisted.device, perform: perform)
                    }
                }
            } header: {
                Text(Wording.notListedTitle)
            } footer: {
                Footnote(Wording.notListedExplanation)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Wording.touchscreenCheck)
        .onAppear { notListed?.start() }
        .onDisappear { notListed?.stop() }
    }
}

/// The pane's head, as a touchscreen's pane has one: a tile with the sidebar's symbol, the name, and
/// what the check is for.
private struct TouchscreenCheckHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: SidebarItem.touchscreenCheckSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white))
                .shadow(color: .black.opacity(0.18), radius: 0.75, y: 0.5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(Wording.touchscreenCheck)
                    .font(.title3.weight(.semibold))
                Text(Wording.checkIntro)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// A touchscreen or device to check: its name, a quieter line beneath, Check… beside them, and why
/// Check… can't be used when it can't.
private struct CheckRow: View {
    var title: String
    var detail: String?
    var reason: String?
    var availability: SupportCheckAvailability
    var check: @MainActor () -> Void

    var body: some View {
        LabeledContent {
            Button(Wording.checkButton) { check() }
                .disabled(availability != .available)
                .help(reason ?? "")
        } label: {
            Text(title)
            if let detail {
                Text(detail)
            }
            if let reason {
                Text(reason)
            }
        }
    }
}
