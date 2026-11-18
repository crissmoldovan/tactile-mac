import SwiftUI

/// The head of a touchscreen's pane: its tile, its name (renamed in place), its device's own name
/// when it has another, the status line, the notes, and its On switch. For a connected touchscreen
/// that isn't set up, Set Up by Touch… beneath, as the one thing to do: it begins set-up mode.
struct TouchscreenHeader: View {
    var touchscreen: TouchscreenSnapshot
    /// Whether Set Up by Touch… is shown here, and whether it can be used; nil: not shown.
    var setUp: SetUpAvailability? = nil
    var perform: PerformCommand

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TouchscreenTile(isActive: StatusIndicator(touchscreen) != .inactive)
            VStack(alignment: .leading, spacing: 4) {
                TouchscreenName(touchscreen: touchscreen, perform: perform)
                StatusLine(touchscreen: touchscreen)
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
            Toggle(Wording.on, isOn: Binding(
                get: { touchscreen.isOn },
                set: { perform(.setTouchscreenOn(touchscreen.id, $0)) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!touchscreen.onSwitchIsEnabled)
                .accessibilityLabel("\(touchscreen.name) on")
        }
        .padding(.vertical, 4)
    }
}

/// The name, with a pencil that turns it into a field. Return keeps the new name, Escape keeps the
/// old one; an empty name goes back to the device's own.
struct TouchscreenName: View {
    var touchscreen: TouchscreenSnapshot
    var perform: PerformCommand

    @State private var isRenaming = false
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
                    Text(touchscreen.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
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
                if !touchscreen.deviceName.isEmpty, touchscreen.name != touchscreen.deviceName {
                    Text(touchscreen.deviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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

/// The status line: one coloured dot and one quiet line.
struct StatusLine: View {
    var touchscreen: TouchscreenSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            StatusDot(indicator: StatusIndicator(touchscreen))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(Wording.statusLine(for: touchscreen))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
