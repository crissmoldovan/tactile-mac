// What the entries to the touchscreen check share: what the check needs of a touchscreen Tactile
// lists, and the touch devices it doesn't list (digitisers, and touchscreens that only act as a
// mouse). The entries are Touchscreen Check in the sidebar (`TouchscreenCheckPane`), Check This
// Touchscreen… in a touchscreen's header (`TouchscreenHeader`) and in its details beside the menu
// (`TouchscreenDetailsView`), and set-up mode's session card (`SetUpModeSessionView`).

import Observation
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

/// The touch devices Tactile doesn't list, as the check's probe finds them: listed while Touchscreen
/// Check is shown, and not watched otherwise. Watching opens nothing.
@MainActor
@Observable
final class NotListedDevices {
    static let shared = NotListedDevices()

    private(set) var devices: [SupportDevice]
    @ObservationIgnored private var probe: SupportProbe?
    /// A list given once, for renders and previews: nothing is watched.
    private let isFixed: Bool

    init() {
        devices = []
        isFixed = false
    }

    /// Always `devices`: no probe is started.
    init(fixed devices: [SupportDevice]) {
        self.devices = devices
        isFixed = true
    }

    func start() {
        guard !isFixed, probe == nil else { return }
        let probe = SupportProbe()
        probe.onDevicesChanged = { [weak self] in self?.devices = self?.probe?.devices ?? [] }
        probe.start()
        self.probe = probe
        devices = probe.devices
    }

    func stop() {
        guard !isFixed else { return }
        probe?.stop()
        probe = nil
        devices = []
    }
}
