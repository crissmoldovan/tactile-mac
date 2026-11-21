import SwiftUI

/// The head of a touchscreen's pane (`TouchscreenHeaderContent`):
/// - its tile; its status dot and its name (renamed in place), with its On switch at the right;
/// - beneath, its device's own name when it has another, with Check This Touchscreen… at the right,
///   under the switch, for a connected touchscreen;
/// - then, the whole width, the status line (unless it says what the Display row says), the notes,
///   and for a connected touchscreen that isn't set up, Set Up by Touch…, as the one thing to do: it
///   begins set-up mode.
/// Only the name's row and the device name's row give up width to the switch and the button.
struct TouchscreenHeader: View {
    var touchscreen: TouchscreenSnapshot
    var content: TouchscreenHeaderContent
    /// Whether Set Up by Touch… is shown here, and whether it can be used; nil: not shown.
    var setUp: SetUpAvailability? = nil
    var perform: PerformCommand

    @State private var isRenaming = false

    /// From the dot's leading edge to the name's: the dot and the space after it. The lines beneath
    /// start where the name does.
    static let nameIndent: CGFloat = 15

    var body: some View {
        let showsDeviceName = !isRenaming && !touchscreen.deviceName.isEmpty && touchscreen.name != touchscreen.deviceName
        HStack(alignment: .top, spacing: 12) {
            TouchscreenTile(isActive: content.indicator != .inactive)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    TouchscreenName(touchscreen: touchscreen, indicator: content.indicator, isRenaming: $isRenaming,
                                    perform: perform)
                    Spacer(minLength: 0)
                    Toggle(Wording.on, isOn: Binding(
                        get: { touchscreen.isOn },
                        set: { perform(.setTouchscreenOn(touchscreen.id, $0)) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!touchscreen.onSwitchIsEnabled)
                        .accessibilityLabel("\(touchscreen.name) on")
                }
                if showsDeviceName || content.check != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if showsDeviceName {
                            Text(touchscreen.deviceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.leading, Self.nameIndent)
                        }
                        Spacer(minLength: 0)
                        if let check = content.check {
                            Button(Wording.checkThisTouchscreen) {
                                SupportCheckWindow.open(SupportTarget(touchscreen), perform: perform)
                            }
                            .disabled(check != .available)
                            .help(check == .available ? "" : Wording.supportUnavailable(check))
                        }
                    }
                }
                if content.showsStatusLine {
                    StatusLine(touchscreen: touchscreen)
                        .padding(.leading, Self.nameIndent)
                }
                ForEach(touchscreen.headerNotes, id: \.self) { note in
                    NoteLine(note: note)
                }
                if let setUp {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(Wording.setUpByTouch) { perform(.beginSetUpMode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(setUp != .available)
                            .help(setUp.reason.map(Wording.setUpUnavailable) ?? "")
                        if let reason = setUp.reason {
                            UnavailableReason(reason: reason)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// The status dot and the name, with a pencil that turns the name into a field. Return keeps the new
/// name, Escape keeps the old one; an empty name goes back to the device's own.
struct TouchscreenName: View {
    var touchscreen: TouchscreenSnapshot
    /// The dot, as the sidebar has it, whatever the status.
    var indicator: StatusIndicator
    @Binding var isRenaming: Bool
    var perform: PerformCommand

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isRenaming {
                TextField(Wording.rename, text: $draft, prompt: Text(Wording.namePrompt(deviceName: touchscreen.deviceName)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: 260)
                    .focused($isFocused)
                    .onAppear {
                        // Focus set while the field is being put in place doesn't take in a Form.
                        Task { @MainActor in isFocused = true }
                    }
                    .onSubmit(commit)
                    .onKeyPress(.escape) {
                        isRenaming = false
                        return .handled
                    }
                    .onChange(of: isFocused) {
                        if !isFocused, isRenaming { commit() }
                    }
                Text(Wording.renameFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    HStack(spacing: TouchscreenHeader.nameIndent - StatusDot.size) {
                        StatusDot(indicator: indicator)
                        Text(touchscreen.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityValue(Wording.menuState(for: touchscreen))
                    }
                    Button {
                        draft = touchscreen.name
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(!touchscreen.canChangeSettings)
                    .help(Wording.rename)
                    .accessibilityLabel("\(Wording.rename) \(touchscreen.name)")
                }
            }
        }
    }

    private func commit() {
        isRenaming = false
        if let command = NameEntry.touchscreen(
            draft, current: touchscreen.name, deviceName: touchscreen.deviceName, id: touchscreen.id)
        {
            perform(command)
        }
    }
}

/// The status line: one quiet line. Its dot is beside the name.
struct StatusLine: View {
    var touchscreen: TouchscreenSnapshot

    var body: some View {
        Text(Wording.statusLine(for: touchscreen))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .font(.callout)
    }
}

/// A note beneath the status line.
struct NoteLine: View {
    var note: TouchscreenNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            icon
            Text(Wording.note(note))
                .foregroundStyle(note == .macOSMayAlsoRespond || note == .cannotBeToldApart ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    @ViewBuilder private var icon: some View {
        switch note {
        case .oneFingerOnly, .rememberedByPort, .macOSIgnoresIt:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .macOSMayAlsoRespond, .cannotBeToldApart:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .touchesCannotBeRead:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
