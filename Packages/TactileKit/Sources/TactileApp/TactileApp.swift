// The composition root: the one place where the live pieces are made and joined.

import AppKit
import Foundation
import TactileDevices
import TactileScreens
import os

/// Where Tactile keeps its files, defined once: the composition root gives them to the model, and
/// the interface names them (General's Record frames sentence).
public enum TactileFolders {
    /// `~/Library/Application Support/Tactile/`: `settings.json`, and `state.json` while Tactile runs.
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tactile", isDirectory: true)
    }

    /// `~/Library/Logs/Tactile/`: the recorded frames.
    public static var frames: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Tactile", isDirectory: true)
    }

    /// `frames` as a person reads it: "~/Library/Logs/Tactile".
    public static var framesShown: String {
        (frames.path as NSString).abbreviatingWithTildeInPath
    }
}

/// Tactile's application delegate. The app's entry point (`TactileMain`, in the Xcode target) is a
/// SwiftUI `App` that adapts this delegate and whose body is `TactileScenes(model: delegate.model)`.
///
/// It makes the live touchscreen source, displays, system conditions and pipeline outputs, the
/// settings store at `~/Library/Application Support/Tactile/settings.json`, and the model, with the
/// state file `state.json` beside the settings. The model is made when it is first asked for (the
/// scenes ask for it as the app starts) and touches no device until it is started, in
/// `applicationDidFinishLaunching`.
///
/// - Another copy of Tactile already running: this one logs it and quits before anything is started.
///   Two readers would make every touch happen twice.
/// - Quitting (Quit in the menu, ⌘Q, a quit request from the system, or `SIGTERM` or `SIGINT`):
///   the model shuts down, which cancels every touch, lets every touchscreen go, saves, and removes
///   the state file; then the touch circles are taken down.
/// - Opened again while it runs (from Finder, Spotlight or the Dock): Settings opens, or comes to
///   the front, through the same path as Settings… in the menu. With the menu-bar icon hidden (a
///   notch, a crowded menu bar) it is the way to Settings.
/// - It never asks macOS for a permission. Only the button in Settings or the menu does.
/// - Once the model has started, so does the updater (`AppUpdates`): a check a minute later, then
///   daily. Installing an update quits through `NSApplication.terminate`, the same path as Quit.
@MainActor
public final class TactileAppDelegate: NSObject, NSApplicationDelegate {

    /// The live model, made on first use. Held here for the app's life: the touchscreen source
    /// holds its delegate, the model, only weakly.
    public private(set) lazy var model: TactileModel = makeModel()

    private static let log = Logger(subsystem: "com.crissmoldovan.tactile", category: "app")

    /// The outputs the model was given, kept to take the circles down at quit.
    private var outputs: LivePipelineOutputs?
    private var hasStartedModel = false
    private var signalSources: [DispatchSourceSignal] = []

    // MARK: - NSApplicationDelegate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Self.appVersion
        let pid = ProcessInfo.processInfo.processIdentifier
        if let other = Self.otherRunningCopy() {
            Self.log.error("Tactile \(version, privacy: .public) (pid \(pid, privacy: .public)): another Tactile is already running (pid \(other.processIdentifier, privacy: .public), \(other.bundleURL?.path ?? "unknown path", privacy: .public)); quitting without touching any device")
            NSApplication.shared.terminate(nil)
            return
        }
        Self.log.info("Tactile \(version, privacy: .public) starting (pid \(pid, privacy: .public), \(Bundle.main.bundleURL.path, privacy: .public))")
        quitOnSignals()
        model.start()
        hasStartedModel = true
        AppUpdates.shared.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // A copy that quit because another was running started nothing, and must not remove the
        // other copy's state file.
        guard hasStartedModel else { return }
        Self.log.info("Quitting")
        model.shutDown()
        outputs?.closeEveryOverlay()
        hasStartedModel = false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Tactile again opens Settings. Returns false: Tactile has handled it, and neither
    /// AppKit nor SwiftUI should do anything of their own, such as opening a window of their choosing.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.log.info("Opened again (windows visible \(flag, privacy: .public)): opening Settings")
        SettingsWindow.requestFromOutside(reason: .reopen)
        return false
    }

    // MARK: - Making the pieces

    /// Every live piece, given explicitly: the support folder (the store and the state file create it
    /// when they first write), the frames folder, macOS's version and the general pasteboard.
    private func makeModel() -> TactileModel {
        let folder = TactileFolders.support
        let outputs = LivePipelineOutputs()
        self.outputs = outputs
        return TactileModel(
            appVersion: Self.appVersion,
            source: HIDTouchscreenSource(),
            displays: LiveDisplaySource(),
            conditions: LiveSystemConditions(),
            store: SettingsStore(fileURL: folder.appendingPathComponent("settings.json")),
            stateFileURL: folder.appendingPathComponent("state.json"),
            outputs: outputs,
            now: { ProcessInfo.processInfo.systemUptime },
            framesFolder: TactileFolders.frames,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            copyToPasteboard: LivePasteboard.copy, logs: true)
    }

    /// The version in the bundle, `CFBundleShortVersionString` ("0.5.0").
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Another running process with this app's bundle identifier, if there is one.
    private static func otherRunningCopy() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// `SIGTERM` and `SIGINT` quit the app the ordinary way, so a quit from a terminal (`kill`, or
    /// Ctrl-C on the binary) also lets the touchscreens go, writes their Input Mode back and removes
    /// the state file. Without this, either signal would end the process at once.
    private func quitOnSignals() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    Self.log.info("Signal \(number, privacy: .public): quitting")
                    NSApplication.shared.terminate(nil)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
