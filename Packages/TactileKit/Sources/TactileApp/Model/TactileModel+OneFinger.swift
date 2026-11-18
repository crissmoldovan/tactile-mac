// The one-finger default in the model: what each touchscreen gives, remembered in its settings.

import Foundation
import TactileScreens

extension TactileModel {

    /// Brings each connected touchscreen's `TouchscreenSettings.lastGaveOneFinger` up to date with
    /// what it says while taken (`Resolver.rememberingWhatTouchscreensGive`), and saves the settings
    /// only when that changed it. So the one-finger default holds from a touchscreen's first touch
    /// after a launch: the strip scrolls before it has said where its touches come from. Called at
    /// every round.
    func rememberWhatTouchscreensGive() {
        let settings = Resolver.rememberingWhatTouchscreensGive(inputs)
        guard settings != inputs.settings else { return }
        ModelLog.model.info("What each touchscreen gives, remembered: \(Self.describeGiving(settings), privacy: .public)")
        inputs.settings = settings
        save()
    }

    private static func describeGiving(_ settings: TactileSettings) -> String {
        settings.touchscreens.sorted { $0.key.rawValue < $1.key.rawValue }.compactMap { id, screen in
            screen.lastGaveOneFinger.map { "\(id.rawValue) \($0 ? "one finger" : "every finger")" }
        }.joined(separator: ", ")
    }
}
