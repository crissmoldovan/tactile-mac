// The behaviour groups of a connected touchscreen's pane: one finger, the pointer and the circles;
// the gestures; accidental touches; and Copy Settings From… and Reset. Every control reads the
// snapshot and sends a command; none keeps a copy of a setting.

import SwiftUI
import TactileGestures
import TactileScreens

/// Behaviour: what one finger does, where the pointer goes after a touch, and the touch circles.
/// One finger offers the default first, named with the mode it gives on this touchscreen
/// (`OneFingerPicker`).
struct BehaviourSection: View {
    var touchscreen: TouchscreenSnapshot
    var perform: PerformCommand

    var body: some View {
        let behaviour = touchscreen.behaviour
        let id = touchscreen.id
        let oneFinger = OneFingerPicker(touchscreen)
        Section {
            Picker(selection: Binding(
                get: { oneFinger.choice },
                set: { option in oneFinger.command(option, for: id).map { perform($0) } }
            )) {
                ForEach(OneFingerPicker.options, id: \.self) { option in
                    Text(oneFinger.title(option)).tag(option)
                }
            } label: {
                ExplainedLabel(title: Wording.oneFingerLabel, explanation: oneFinger.explanation)
            }
            Picker(Wording.pointerReturnLabel, selection: Binding(
                get: { behaviour.pointerReturn },
                set: { perform(.setPointerReturn(id, $0)) }
            )) {
                ForEach(PointerReturn.allCases, id: \.self) { choice in
                    Text(Wording.pointerReturn(choice)).tag(choice)
                }
            }
            Toggle(Wording.touchCircles, isOn: Binding(
                get: { behaviour.showsCircles },
                set: { perform(.setShowsCircles(id, $0)) }))
                .toggleStyle(.switch)
        } header: {
            Text(Wording.behaviour)
        }
        .disabled(!touchscreen.canChangeSettings)
    }
}

/// Gestures: a switch for each. On a touchscreen that reads one finger, the ones that need more are
/// off and disabled, and long-press stays. Beneath them, why, and the Mission Control shortcuts when
/// they are off.
struct GesturesSection: View {
    var touchscreen: TouchscreenSnapshot
    var warnings: [AppWarning]
    var perform: PerformCommand

    var body: some View {
        let behaviour = touchscreen.behaviour
        Section {
            ForEach(GestureRow.rows(for: behaviour)) { row in
                Toggle(isOn: Binding(
                    get: { row.isOn },
                    set: { perform(GestureRow.command(row.kind, on: $0, for: touchscreen.id, behaviour: behaviour)) }
                )) {
                    ExplainedLabel(title: Wording.gesture(row.kind), explanation: Wording.gestureExplanation(row.kind),
                                   isDimmed: !row.isEnabled)
                }
                .toggleStyle(.switch)
                .disabled(!row.isEnabled)
            }
        } header: {
            Text(Wording.gestures)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !behaviour.multiFingerAvailable {
                    Footnote(Wording.oneFingerOnlyGestures)
                }
                if warnings.contains(.missionControlShortcutsOff), behaviour.multiFingerAvailable {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Footnote(Wording.swipesNeedShortcuts)
                    }
                }
            }
        }
        .disabled(!touchscreen.canChangeSettings)
    }
}

/// Accidental touches: palm rejection, and touches that start near an edge.
struct AccidentalTouchesSection: View {
    var touchscreen: TouchscreenSnapshot
    var perform: PerformCommand

    var body: some View {
        let rules = touchscreen.behaviour.rejection
        let id = touchscreen.id
        Section {
            Toggle(isOn: Binding(
                get: { rules.palm },
                set: { perform(PalmRejection.command($0, rules: rules, for: id)) }
            )) {
                ExplainedLabel(
                    title: Wording.palmRejection,
                    explanation: Wording.palmExplanation(reportsPalms: touchscreen.behaviour.reportsPalms))
            }
            .toggleStyle(.switch)
            LabeledContent(Wording.edgeMargin) {
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { rules.edgeMarginMM },
                            set: { value in EdgeMargin.command(value, rules: rules, for: id).map { perform($0) } }),
                        in: EdgeMargin.range, step: 1
                    )
                    .labelsHidden()
                    .frame(width: 150)
                    .accessibilityLabel(Wording.edgeMargin)
                    .accessibilityValue(Wording.edgeMarginValue(rules.edgeMarginMM))
                    Text(Wording.edgeMarginValue(rules.edgeMarginMM))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        } header: {
            Text(Wording.accidentalTouches)
        }
        .disabled(!touchscreen.canChangeSettings)
    }
}

/// When off, with the note that "Leave it to macOS" does nothing for a touchscreen macOS ignores.
struct WhenOffSection: View {
    var touchscreen: TouchscreenSnapshot
    var perform: PerformCommand

    var body: some View {
        Section {
            WhenOffRow(touchscreen: touchscreen, perform: perform)
                .disabled(!touchscreen.canChangeSettings)
        } footer: {
            if touchscreen.macOSIgnoresIt {
                Footnote(Wording.note(.macOSIgnoresIt))
            }
        }
    }
}

/// Copy Settings From… (a menu of the other touchscreens) and Reset, after asking. Neither touches
/// the pairing.
struct BehaviourActions: View {
    var touchscreen: TouchscreenSnapshot
    var sources: [CopySource]
    var perform: PerformCommand

    @State private var isAskingToReset = false

    var body: some View {
        HStack(spacing: 10) {
            Menu(Wording.copySettingsFrom) {
                ForEach(sources) { source in
                    Button(source.title) { perform(source.command(to: touchscreen.id)) }
                }
            }
            .fixedSize()
            .disabled(sources.isEmpty)
            Button(Wording.reset) { isAskingToReset = true }
            Spacer(minLength: 0)
        }
        .disabled(!touchscreen.canChangeSettings)
        .confirmationDialog(Wording.resetQuestion(name: touchscreen.name), isPresented: $isAskingToReset) {
            Button(Wording.reset, role: .destructive) { perform(.resetBehaviour(touchscreen.id)) }
            Button(Wording.cancel, role: .cancel) {}
        } message: {
            Text(Wording.resetMessage)
        }
    }
}
