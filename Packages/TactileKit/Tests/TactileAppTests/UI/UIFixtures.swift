import Foundation
import TactileScreens

@testable import TactileApp

/// The preview desk's snapshots, for the interface's tests.
enum UIFixtures {
    static let ilitek = TouchscreenID(rawValue: "222a:0001:V06.00.00.00")
    static let strip = TouchscreenID(rawValue: "27c0:0859:TEST-SERIAL-0001")
    static let oldPanel = TouchscreenID(rawValue: "0eef:0001:")

    static var desk: AppSnapshot { snapshot(.desk) }

    static func snapshot(_ variant: PreviewModel.Variant) -> AppSnapshot {
        PreviewDesk(variant).snapshot()
    }

    static func touchscreen(_ id: TouchscreenID, in snapshot: AppSnapshot) -> TouchscreenSnapshot? {
        snapshot.touchscreens.first { $0.id == id }
    }

    static func displayID(named name: String, in snapshot: AppSnapshot) -> UInt32? {
        snapshot.displays.first { $0.name == name }?.id
    }
}
