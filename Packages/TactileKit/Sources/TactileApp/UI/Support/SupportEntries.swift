// Where the touchscreen check starts: Help Me Support This Touchscreen… in a connected touchscreen's
// pane and in its details beside the menu; and Touchscreen Not Listed? in General, which lists the
// touch devices Tactile doesn't (digitisers, and touchscreens that only act as a mouse), each with
// Check….

import Observation
import SwiftUI
import TactileDevices
import TactileScreens

/// What the check needs of a touchscreen Tactile lists, to find its device and its display.
struct SupportTarget: Equatable, Sendable {
    var id: TouchscreenID
    var name: String
    var usbID: String
    var serial: String
    var location: String?
    var pairedDisplayID: UInt32?

    init(_ touchscreen: TouchscreenSnapshot) {
        id = touchscreen.id
        name = touchscreen.name
        usbID = touchscreen.usbID
        serial = touchscreen.serial
        location = touchscreen.location
        pairedDisplayID = touchscreen.pairedDisplayID
    }
}

/// The pane's group: what the check is for, and Help Me Support This Touchscreen….
struct SupportSection: View {
    var touchscreen: TouchscreenSnapshot
    var snapshot: AppSnapshot
    var perform: PerformCommand

    var body: some View {
        let availability = SupportCheckAvailability.of(touchscreen, in: snapshot)
        Section {
            LabeledContent {
                Button(Wording.helpMeSupport) { SupportCheckWindow.open(SupportTarget(touchscreen), perform: perform) }
                    .disabled(availability != .available)
                    .help(availability == .available ? "" : Wording.supportUnavailable(availability))
            } label: {
                ExplainedLabel(title: Wording.supportLabel, explanation: Wording.supportExplanation)
            }
        } footer: {
            if availability != .available {
                Footnote(Wording.supportUnavailable(availability))
            }
        }
    }
}

/// The touch devices Tactile doesn't list, as the check's probe finds them: listed while General is
/// shown, and not watched otherwise. Watching opens nothing.
@MainActor
@Observable
final class NotListedDevices {
    static let shared = NotListedDevices()

    private(set) var devices: [SupportDevice] = []
    @ObservationIgnored private var probe: SupportProbe?

    func start() {
        guard probe == nil else { return }
        let probe = SupportProbe()
        probe.onDevicesChanged = { [weak self] in self?.devices = self?.probe?.devices ?? [] }
        probe.start()
        self.probe = probe
        devices = probe.devices
    }

    func stop() {
        probe?.stop()
        probe = nil
        devices = []
    }
}

/// General's Touchscreen Not Listed?. Without a list (renders, previews), it says only what it is for.
struct NotListedSection: View {
    var snapshot: AppSnapshot
    var perform: PerformCommand
    var list: NotListedDevices?

    var body: some View {
        let devices = list.map { SupportDeviceMatching.unlisted($0.devices, in: snapshot) } ?? []
        Section {
            if devices.isEmpty {
                Text(Wording.notListedNone)
                    .foregroundStyle(.secondary)
            }
            ForEach(devices, id: \.id) { device in
                LabeledContent {
                    Button(Wording.checkButton) { SupportCheckWindow.open(device, perform: perform) }
                        .disabled(snapshot.setUp != nil || snapshot.setUpMode != nil)
                } label: {
                    Text(Wording.supportDeviceName(device))
                    Text(Wording.notListedDetail(device))
                }
            }
        } header: {
            Text(Wording.notListedTitle)
        } footer: {
            Footnote(Wording.notListedExplanation)
        }
        .onAppear { list?.start() }
        .onDisappear { list?.stop() }
    }
}
