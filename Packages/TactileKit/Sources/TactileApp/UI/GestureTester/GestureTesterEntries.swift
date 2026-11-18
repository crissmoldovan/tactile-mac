// Where Gesture Tester… is offered: a group of its own in a connected touchscreen's pane, after its
// gestures; and in a touchscreen's details beside the menu (`TouchscreenDetailsView`). Each is
// enabled when the tester could open now (`GestureTesterAvailability`), with the reason beneath it
// when not.

import SwiftUI

/// The pane's group: what the tester is for, and Gesture Tester….
struct GestureTesterSection: View {
    var touchscreen: TouchscreenSnapshot
    var snapshot: AppSnapshot
    var perform: PerformCommand

    var body: some View {
        let availability = GestureTesterAvailability.of(touchscreen, in: snapshot)
        Section {
            LabeledContent {
                Button(Wording.gestureTester) { GestureTesterWindow.open(touchscreen.id, perform: perform) }
                    .disabled(availability != .available)
                    .help(availability.reason.map(Wording.gestureTesterUnavailable) ?? "")
            } label: {
                ExplainedLabel(title: Wording.gestureTesterLabel, explanation: Wording.gestureTesterExplanation)
            }
        } footer: {
            if let reason = availability.reason {
                Footnote(Wording.gestureTesterUnavailable(reason))
            }
        }
    }
}
