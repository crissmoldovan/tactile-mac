// The rows of a connected touchscreen's first group: its display, the orientation of its glass, its
// alignment, and its diagonal. The controls among them that change a fit are disabled while a set-up
// runs (`FitControls`); the group's footer says why.

import AppKit
import SwiftUI
import TactileScreens

/// Display: the pop-up of displays, with Rename… for the display chosen, Identify and Set Up by
/// Touch… beneath it. Set Up by Touch… begins set-up mode; it is left out while it is the header's
/// (a touchscreen that isn't set up); when it can't be used, why is said beneath it.
struct DisplayRow: View {
    var touchscreen: TouchscreenSnapshot
    var displays: [DisplaySnapshot]
    /// Set Up by Touch…, and whether it can be used; nil: not in this row.
    var setUp: SetUpAvailability?
    /// Whether the pop-up can be used.
    var fit: FitControls
    var perform: PerformCommand

    /// The display the Rename… alert was opened for, kept so the alert renames that one.
    @State private var renaming: DisplaySnapshot?
    @State private var draft = ""

    private var pairedDisplay: DisplaySnapshot? {
        displays.first { $0.id == touchscreen.pairedDisplayID }
    }

    var body: some View {
        LabeledContent(Wording.display) {
            VStack(alignment: .trailing, spacing: 8) {
                Picker(Wording.display, selection: Binding(
                    get: { DisplayPick(touchscreen) },
                    set: { pick in pick.command(for: touchscreen).map { perform($0) } }
                )) {
                    Text(Wording.unpaired).tag(DisplayPick.unpaired)
                    Divider()
                    if case .missing(let name) = DisplayPick(touchscreen) {
                        Text(Wording.missingDisplay(name: name)).tag(DisplayPick.missing(name)).disabled(true)
                    }
                    ForEach(touchscreen.displayChoices) { choice in
                        Text(Wording.displayChoice(choice)).tag(DisplayPick.display(choice.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 440, alignment: .trailing)
                .disabled(!fit.isEnabled)
                HStack(spacing: 8) {
                    if let pairedDisplay, pairedDisplay.canBeRenamed {
                        Button(Wording.renameDisplay) {
                            draft = pairedDisplay.name
                            renaming = pairedDisplay
                        }
                        .help(Wording.renameDisplayTitle(name: pairedDisplay.name))
                    }
                    Button(Wording.identify) {
                        IdentifyOverlay.shared.show(displays)
                    }
                    if let setUp {
                        Button(Wording.setUpByTouch) { perform(.beginSetUpMode) }
                            .disabled(setUp != .available)
                            .help(setUp.reason.map(Wording.setUpUnavailable) ?? "")
                    }
                }
                if let reason = setUp?.reason {
                    UnavailableReason(reason: reason)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 440, alignment: .trailing)
                }
            }
        }
        .alert(
            Wording.renameDisplayTitle(name: renaming?.name ?? ""),
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { display in
            TextField(Wording.display, text: $draft)
            Button(Wording.rename) {
                if let command = NameEntry.display(draft, current: display.name, uuid: display.uuid) {
                    perform(command)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button(Wording.cancel, role: .cancel) {}
        } message: { _ in
            Text(Wording.renameDisplayMessage)
        }
    }
}

/// Orientation: four turns and a flip. Disabled while unpaired (the orientation belongs to the
/// glass on its display) and while a set-up runs.
struct OrientationRow: View {
    var touchscreen: TouchscreenSnapshot
    var fit: FitControls
    var perform: PerformCommand

    var body: some View {
        let current = touchscreen.orientation ?? .asFitted
        LabeledContent(Wording.orientation) {
            HStack(spacing: 14) {
                Picker(Wording.orientation, selection: Binding(
                    get: { current.quarterTurns },
                    set: { perform(.setOrientation(touchscreen.id, Orientation(quarterTurns: $0, isFlipped: current.isFlipped))) }
                )) {
                    ForEach(0..<4, id: \.self) { turns in
                        Text(Wording.quarterTurns(turns)).tag(turns)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle(Wording.flip, isOn: Binding(
                    get: { current.isFlipped },
                    set: { perform(.setOrientation(touchscreen.id, Orientation(quarterTurns: current.quarterTurns, isFlipped: $0))) }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .disabled(!fit.orientationIsEnabled)
    }
}

/// Alignment: whether the picture's edges were fitted to the glass by four taps; Calibrate
/// Corners… and Test, on the display it is paired with; and, once calibrated, Use Whole Glass,
/// after asking. Use Whole Glass waits while a set-up runs, and its question closes if one begins.
struct AlignmentRow: View {
    var touchscreen: TouchscreenSnapshot
    /// Whether Calibrate Corners… and Test can be used now.
    var onItsDisplay: SetUpAvailability
    /// Whether Use Whole Glass can be used now.
    var fit: FitControls
    var perform: PerformCommand

    @State private var isAsking = false

    var body: some View {
        let help = onItsDisplay.reason.map(Wording.setUpUnavailable) ?? ""
        LabeledContent {
            HStack(spacing: 8) {
                Button(Wording.calibrateCorners) { perform(.beginSetUp(touchscreen.id, .calibrate)) }
                    .disabled(onItsDisplay != .available)
                    .help(help)
                Button(Wording.test) { perform(.beginSetUp(touchscreen.id, .test)) }
                    .disabled(onItsDisplay != .available)
                    .help(help)
                if touchscreen.isCalibrated {
                    Button(Wording.useWholeGlass) { isAsking = true }
                        .disabled(!fit.isEnabled)
                }
            }
        } label: {
            Text(Wording.alignment)
            Text(Wording.alignmentState(isCalibrated: touchscreen.isCalibrated))
        }
        .confirmationDialog(Wording.useWholeGlassQuestion(name: touchscreen.name), isPresented: $isAsking) {
            Button(Wording.useWholeGlass, role: .destructive) { perform(.clearCalibration(touchscreen.id)) }
            Button(Wording.cancel, role: .cancel) {}
        } message: {
            Text(Wording.useWholeGlassMessage)
        }
        .onChange(of: fit.isEnabled) {
            // The model would refuse the answer now.
            if !fit.isEnabled { isAsking = false }
        }
    }
}

/// Diagonal: a field in inches, empty for the size the display reports, which is named beside it.
/// What it shows is the pane's (`DiagonalField`), so that a set-up begun from the pane commits a
/// diagonal being typed first. Disabled while a set-up runs.
struct DiagonalRow: View {
    var touchscreen: TouchscreenSnapshot
    @Binding var field: DiagonalField
    /// Whether the field can be used (`FitControls.isEnabled`).
    var isEnabled: Bool
    /// Commits what is typed: Return, or leaving the field (see `DiagonalField.commit`).
    var commit: @MainActor () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(Wording.diagonal, text: $field.text, prompt: Text(Wording.diagonalPrompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .disabled(!isEnabled)
                Text(Wording.inchesUnit)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(Wording.diagonal)
            if let reported = Wording.reportedDiagonal(
                displayName: touchscreen.pairedDisplayName, inches: touchscreen.reportedDiagonalInches)
            {
                Text(reported)
            }
        }
        .onAppear { field.show(touchscreen.diagonalInches) }
        .onChange(of: touchscreen.diagonalInches) {
            if !isFocused { field.show(touchscreen.diagonalInches) }
        }
        .onChange(of: isFocused) {
            if !isFocused { commit() }
        }
        .onChange(of: isEnabled) {
            // A set-up began. Begun from this pane, a diagonal being typed was set first; begun
            // anywhere else, the model would refuse it now. Either way the field shows the one in
            // force, and gives up the focus, whose loss then sends nothing.
            if !isEnabled {
                field.show(touchscreen.diagonalInches)
                isFocused = false
            }
        }
    }
}
