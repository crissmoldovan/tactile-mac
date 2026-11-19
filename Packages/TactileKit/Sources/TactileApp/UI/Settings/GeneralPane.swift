import SwiftUI

/// General, in `order`: the warnings, when there are any, each with its button; Tactile on or off,
/// and Launch at login; Touchscreen Not Listed? (`NotListedSection`), near the top, where a person
/// whose touchscreen Tactile doesn't list looks first; diagnostics (debug logging, recording frames,
/// Copy diagnostics); Experimental (Swipes follow the fingers); Updates (`UpdatesSection`); the
/// version.
struct GeneralPane: View {
    var snapshot: AppSnapshot
    var perform: PerformCommand
    /// The touch devices Tactile doesn't list, in the app; nil where nothing is watched.
    var notListed: NotListedDevices? = nil

    /// General's groups.
    enum Group: CaseIterable, Hashable {
        case warnings, tactile, notListed, diagnostics, experimental, updates, version
    }

    /// The order the groups are shown in.
    static let order: [Group] = [.warnings, .tactile, .notListed, .diagnostics, .experimental, .updates, .version]

    var body: some View {
        Form {
            ForEach(Self.order, id: \.self) { group in
                section(group)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Wording.general)
    }

    @ViewBuilder
    private func section(_ group: Group) -> some View {
        switch group {
        case .warnings:
            if !snapshot.warnings.isEmpty {
                Section {
                    ForEach(snapshot.warnings, id: \.self) { warning in
                        WarningRow(warning: warning, perform: perform)
                    }
                }
            }
        case .tactile:
            Section {
                Toggle(isOn: Binding(get: { snapshot.isOn }, set: { perform(.setOn($0)) })) {
                    Text(Wording.tactile)
                    Text(Wording.tactileExplanation)
                }
                .toggleStyle(.switch)
                LaunchAtLoginRowView(row: LaunchAtLoginRow(snapshot.launchAtLogin), perform: perform)
            }
        case .notListed:
            NotListedSection(snapshot: snapshot, perform: perform, list: notListed)
        case .diagnostics:
            Section {
                Toggle(isOn: Binding(get: { snapshot.debugLogging }, set: { perform(.setDebugLogging($0)) })) {
                    Text(Wording.debugLogging)
                    Text(Wording.debugLoggingExplanation)
                }
                .toggleStyle(.switch)
                Toggle(isOn: Binding(get: { snapshot.recordsFrames }, set: { perform(.setRecordsFrames($0)) })) {
                    Text(Wording.recordFrames)
                    Text(Wording.recordFramesExplanation)
                }
                .toggleStyle(.switch)
                CopyDiagnosticsRow(perform: perform)
            } header: {
                Text(Wording.diagnostics)
            } footer: {
                Footnote(Wording.diagnosticsFootnote)
            }
        case .experimental:
            Section {
                FollowedSwipesRowView(row: FollowedSwipesRow(snapshot), perform: perform)
            } header: {
                Text(Wording.experimental)
            }
        case .updates:
            UpdatesSection()
        case .version:
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Wording.version(snapshot.appVersion))
                        .textSelection(.enabled)
                    Text(Wording.credit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Launch at login: the switch, and beneath it what macOS says when it needs saying, with Open Login
/// Items Settings… while Tactile waits for the person's approval there.
struct LaunchAtLoginRowView: View {
    var row: LaunchAtLoginRow
    var perform: PerformCommand

    /// Bumped after every click, so the switch is drawn again from the snapshot: where macOS refuses,
    /// the snapshot doesn't change, and the switch would otherwise stay where it was clicked.
    @State private var redraws = 0

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Toggle(isOn: Binding(
                get: { row.isOn },
                set: { _ in
                    row.toggleCommand.map { perform($0) }
                    redraws &+= 1
                }
            )) {
                Text(Wording.launchAtLogin)
                    .foregroundStyle(row.isEnabled ? .primary : .tertiary)
                if let note = row.note {
                    Text(note)
                }
            }
            .toggleStyle(.switch)
            .disabled(!row.isEnabled)
            .id(redraws)
            if row.offersLoginItemsSettings {
                Button(Wording.openLoginItemsSettings) { perform(LaunchAtLoginRow.openSettingsCommand) }
            }
        }
    }
}

/// Swipes follow the fingers: the switch, what it does and the way back if a Desktop sticks, and
/// why it is off here when this Mac can't follow swipes.
struct FollowedSwipesRowView: View {
    var row: FollowedSwipesRow
    var perform: PerformCommand

    /// Bumped after every click, so the switch is drawn again from the snapshot (see
    /// `LaunchAtLoginRowView`).
    @State private var redraws = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { row.isOn },
                set: { _ in
                    row.toggleCommand.map { perform($0) }
                    redraws &+= 1
                }
            )) {
                Text(Wording.swipesFollowFingers)
                    .foregroundStyle(row.isEnabled ? .primary : .tertiary)
                Text(Self.markdown(Wording.swipesFollowFingersExplanation))
            }
            .toggleStyle(.switch)
            .disabled(!row.isEnabled)
            .id(redraws)
            if let reason = row.reason {
                Label(reason, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The text with its backticked command shown as code.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// Copy diagnostics: the button, which says "Copied" for a moment after it is pressed.
struct CopyDiagnosticsRow: View {
    var perform: PerformCommand

    @State private var copiedAt: Date?

    var body: some View {
        LabeledContent {
            Button(copiedAt == nil ? Wording.copyDiagnosticsButton : Wording.copied) {
                perform(.copyDiagnostics)
                let now = Date()
                copiedAt = now
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if copiedAt == now { copiedAt = nil }
                }
            }
        } label: {
            Text(Wording.copyDiagnosticsLabel)
            Text(Wording.copyDiagnosticsExplanation)
        }
    }
}

/// A warning: what is wrong, what it means, and a button when Tactile can do something about it.
struct WarningRow: View {
    var warning: AppWarning
    var perform: PerformCommand

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(Wording.warningTitle(warning))
                Text(Wording.warningDetail(warning))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = Wording.warningAction(warning) {
                Button(action.title) { WarningActions.run(action.kind, perform: perform) }
            }
        }
        .padding(.vertical, 2)
    }
}
