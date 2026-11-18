import SwiftUI

/// Tactile's scenes: the menu-bar item and the Settings window. The app's `body` is
/// `TactileScenes(model:)`. Three more kinds of window are AppKit's, following the snapshot through
/// their own observers, started here once: the set-up screens on every display while set-up mode is
/// on or a set-up runs (`SetUpOverlay`), and the first-run window while set-up is offered to
/// touchscreens and can run (`FirstRunWindow`), both through `SnapshotFollower`; and the gesture
/// tester's window, on its touchscreen's display while the tester is open (`GestureTesterWindow`).
///
/// Settings opens only when asked: from the menu, or by itself once shortly after launch when
/// Accessibility access is missing (`shouldOpenSettingsAtLaunch`, `LaunchCheck`). It is never opened by SwiftUI at
/// launch nor restored from the last run: on macOS 15 and later SwiftUI is told so; on macOS 14,
/// which has no way to say it, `SettingsWindow` closes a window that appears unrequested in the
/// first seconds and turns its restoration off. The window sits at the normal level.
public struct TactileScenes<Model: AppModel>: Scene {
    private let model: Model

    @MainActor
    public init(model: Model) {
        self.model = model
        SnapshotFollower.startForTheApp(model)
        GestureTesterWindow.startForTheApp(model)
        SupportCheckWindow.startForTheApp(model)
    }

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window(Wording.settingsWindowTitle, id: SettingsWindow.id) {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 600)
        .defaultPosition(.center)
        .openedOnlyWhenAsked()
    }
}

extension Scene {
    /// Not presented at launch and not restored, where SwiftUI can be told (macOS 15 and later).
    func openedOnlyWhenAsked() -> some Scene {
        if #available(macOS 15, *) {
            return self.defaultLaunchBehavior(.suppressed).restorationBehavior(.disabled)
        } else {
            return self
        }
    }
}
