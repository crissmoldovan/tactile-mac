import AppKit
import SwiftUI
import TactileScreens

/// A touchscreen's pane. Connected: its display, orientation, alignment and diagonal; its behaviour,
/// gestures and accidental touches; what it does when off; Copy Settings From… and Reset.
/// Remembered and not connected: the same head, its pairing read-only, and Forget. While a set-up
/// runs, the controls that change a fit are disabled, and one line says why (`FitControls`).
struct TouchscreenPane: View {
    var touchscreen: TouchscreenSnapshot
    var snapshot: AppSnapshot
    var perform: PerformCommand
    /// The model's snapshot as it is when called: what the model holds after a command was sent,
    /// which `snapshot`, the one this pane was drawn from, doesn't say yet. Nil where nothing is
    /// sent (the renders): `snapshot`.
    var snapshotNow: (@MainActor () -> AppSnapshot)? = nil

    /// What the Diagonal field shows. Kept here, so that a set-up begun from this pane commits a
    /// diagonal being typed first.
    @State private var diagonal = DiagonalField()

    var body: some View {
        // Set Up by Touch… is the header's while it is the one thing to do, else the Display row's.
        let setUp = SetUpAvailability.full(touchscreen, in: snapshot)
        let setUpInHeader = touchscreen.isConnected && touchscreen.status == .notSetUp && touchscreen.mode != .settingUp
        let fit = FitControls(touchscreen, in: snapshot)
        Form {
            Section {
                TouchscreenHeader(touchscreen: touchscreen, setUp: setUpInHeader ? setUp : nil, perform: send)
            }
            if touchscreen.isConnected {
                Section {
                    DisplayRow(touchscreen: touchscreen, displays: snapshot.displays,
                               setUp: setUpInHeader ? nil : setUp, fit: fit, perform: send)
                    OrientationRow(touchscreen: touchscreen, fit: fit, perform: send)
                    AlignmentRow(touchscreen: touchscreen,
                                 onItsDisplay: SetUpAvailability.onItsDisplay(touchscreen, in: snapshot), fit: fit,
                                 perform: send)
                    DiagonalRow(touchscreen: touchscreen, field: $diagonal, isEnabled: fit.isEnabled,
                                commit: commitDiagonal)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if fit.reason == .setUpRunning {
                            Footnote(Wording.setUpRunning)
                        }
                        Footnote(Wording.diagonalFootnote)
                    }
                }
                BehaviourSection(touchscreen: touchscreen, perform: perform)
                GesturesSection(touchscreen: touchscreen, warnings: snapshot.warnings, perform: perform)
                GestureTesterSection(touchscreen: touchscreen, snapshot: snapshot, perform: perform)
                SupportSection(touchscreen: touchscreen, snapshot: snapshot, perform: perform)
                AccidentalTouchesSection(touchscreen: touchscreen, perform: perform)
                WhenOffSection(touchscreen: touchscreen, perform: perform)
                Section {
                    BehaviourActions(
                        touchscreen: touchscreen, sources: CopySource.sources(for: touchscreen, in: snapshot),
                        perform: perform)
                } footer: {
                    Footnote(Wording.behaviourFootnote)
                }
            } else {
                Section {
                    LabeledContent(Wording.display) {
                        Text(Wording.rememberedPairing(displayName: touchscreen.pairedDisplayName))
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 14) {
                        Footnote(Wording.rememberedFootnote)
                        VStack(alignment: .trailing, spacing: 6) {
                            ForgetButton(touchscreen: touchscreen, fit: fit, perform: send)
                            if fit.reason == .setUpRunning {
                                Text(Wording.setUpRunning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(touchscreen.name)
    }

    /// Sends a command from this pane. A set-up begun here first commits a diagonal being typed,
    /// while the model still takes it (see `DiagonalField.send`).
    private func send(_ command: AppCommand) {
        if !diagonal.send(command, for: touchscreen.id, inForce: diagonalInForce, perform: perform) {
            NSSound.beep()
        }
    }

    /// Commits what is typed in the Diagonal field; a beep when it isn't a diagonal.
    private func commitDiagonal() {
        if !diagonal.commit(for: touchscreen.id, inForce: diagonalInForce, perform: perform) {
            NSSound.beep()
        }
    }

    /// This touchscreen's diagonal in force, as the model has it now.
    private func diagonalInForce() -> Double? {
        (snapshotNow?() ?? snapshot).touchscreens.first { $0.id == touchscreen.id }?.diagonalInches
    }
}

/// When off: ignore its touches, or leave it to macOS.
struct WhenOffRow: View {
    var touchscreen: TouchscreenSnapshot
    var perform: PerformCommand

    var body: some View {
        Picker(Wording.whenOffLabel, selection: Binding(
            get: { touchscreen.whenOff },
            set: { perform(.setWhenOff(touchscreen.id, $0)) }
        )) {
            ForEach(WhenOff.allCases, id: \.self) { choice in
                Text(Wording.whenOff(choice)).tag(choice)
            }
        }
    }
}

/// Forget, for a touchscreen that isn't connected, after asking. It waits while a set-up runs, and
/// its question closes if one begins.
struct ForgetButton: View {
    var touchscreen: TouchscreenSnapshot
    var fit: FitControls
    var perform: PerformCommand

    @State private var isAsking = false

    var body: some View {
        Button(Wording.forgetButton) { isAsking = true }
            .disabled(!fit.isEnabled)
            .confirmationDialog(Wording.forgetQuestion(name: touchscreen.name), isPresented: $isAsking) {
                Button(Wording.forgetConfirm, role: .destructive) { perform(.forget(touchscreen.id)) }
                Button(Wording.cancel, role: .cancel) {}
            } message: {
                Text(Wording.forgetMessage)
            }
            .onChange(of: fit.isEnabled) {
                // The model would refuse the answer now.
                if !fit.isEnabled { isAsking = false }
            }
    }
}
