// Every word the interface shows, as pure functions of what the snapshot says. The views hold no
// wording of their own beyond a control's label, so a change of wording is a change here, and every
// case is tested.
//
// Capitalisation follows macOS: buttons and menu items in title case ("Open Accessibility
// Settings…"); labels, status lines, notes and explanations in sentence case.

import Foundation
import TactileGestures
import TactileScreens

/// A button that answers a warning: its title and what it does.
public struct WarningAction: Equatable, Sendable {
    /// What a warning's button does: a command to the model, or something the interface does
    /// itself through `NSWorkspace` (see `WarningActions`).
    public enum Kind: Equatable, Sendable {
        case command(AppCommand)
        /// Opens System Settings at Keyboard, where the Mission Control shortcuts are.
        case openKeyboardSettings
        /// Asks Touch Up to quit.
        case quitTouchUp
    }

    public var title: String
    public var kind: Kind

    public init(title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }
}

public enum Wording {

    // MARK: - A touchscreen's status line

    /// The one line under a touchscreen's name. While it is being set up, that is what it says,
    /// whatever its status: its touches go to the set-up screens.
    public static func statusLine(for touchscreen: TouchscreenSnapshot) -> String {
        if touchscreen.mode == .settingUp {
            return beingSetUp
        }
        return statusLine(touchscreen.status, whenOff: touchscreen.whenOff)
    }

    public static let beingSetUp = "Being set up. Its touches go to the set-up screens."

    /// The one line under a touchscreen's name. `whenOff` says which of the two "off" lines applies.
    public static func statusLine(_ status: TouchscreenStatus, whenOff: WhenOff) -> String {
        switch status {
        case .notConnected:
            return "Not connected"
        case .tactileOff:
            return "Left to macOS while Tactile is off."
        case .accessibilityMissing:
            return "Left to macOS until Tactile has Accessibility access."
        case .off:
            switch whenOff {
            case .ignoreTouches: return "Off. Its touches are ignored."
            case .leaveToMacOS: return "Off. Its touches are left to macOS."
            }
        case .notSetUp:
            return "Not set up. It does nothing until it is paired with a display."
        case .displayNotConnected(let name):
            return "Display not connected: \(name). It resumes when the display returns."
        case .pairedWith(let name, let detail):
            return "Paired with \(displayLabel(name: name, detail: detail))"
        }
    }

    /// A line beneath the status line, for something that limits how a touchscreen works; for
    /// `macOSIgnoresIt`, the footnote beside When off.
    public static func note(_ note: TouchscreenNote) -> String {
        switch note {
        case .oneFingerOnly: return "One finger only: this touchscreen stayed in mouse mode"
        case .macOSMayAlsoRespond: return "macOS may also respond to touches"
        case .touchesCannotBeRead: return "Touches can’t be read"
        case .rememberedByPort: return "Remembered by its USB port: another touchscreen has the same ID"
        case .macOSIgnoresIt:
            return "macOS ignores this touchscreen by itself, so “Leave it to macOS” does nothing here."
        case .cannotBeToldApart:
            return "It can’t be told apart from an identical touchscreen, so Tactile can’t keep settings for it."
        }
    }

    /// The Display row of a touchscreen that isn't connected: its display's name, or Unpaired.
    public static func rememberedPairing(displayName: String?) -> String {
        displayName ?? unpaired
    }

    /// The rename field's prompt: the device's own name, which an empty field goes back to.
    public static func namePrompt(deviceName: String) -> String {
        deviceName.trimmingCharacters(in: .whitespaces).isEmpty ? "Name" : deviceName
    }

    public static let rememberedFootnote = "Its pairing and settings are kept until it is connected again or forgotten."

    // MARK: - The menu

    /// A touchscreen's state in the menu: shorter than the status line, with the notes that limit it.
    public static func menuState(for touchscreen: TouchscreenSnapshot) -> String {
        if touchscreen.mode == .settingUp {
            return menuBeingSetUp
        }
        return menuState(touchscreen.status, notes: touchscreen.notes)
    }

    public static let menuBeingSetUp = "Being set up"

    /// The notes are left out while Tactile isn't handling the touchscreen's touches (not connected,
    /// off, or left to macOS), where they limit nothing.
    public static func menuState(_ status: TouchscreenStatus, notes: [TouchscreenNote]) -> String {
        let state: String
        switch status {
        case .notConnected: state = "Not connected"
        case .tactileOff, .accessibilityMissing: state = "Left to macOS"
        case .off: state = "Off"
        case .notSetUp: state = "Not set up"
        case .displayNotConnected(let name): state = "Display not connected: \(name)"
        case .pairedWith(let name, _): state = "Paired with \(name)"
        }
        return ([state] + menuNotes(status, notes: notes)).joined(separator: " · ")
    }

    /// The notes that limit a touchscreen, in a few words each: none while Tactile isn't handling its
    /// touches (not connected, off, or left to macOS), where they limit nothing.
    static func menuNotes(_ status: TouchscreenStatus, notes: [TouchscreenNote]) -> [String] {
        switch status {
        case .notConnected, .tactileOff, .accessibilityMissing, .off: return []
        case .notSetUp, .displayNotConnected, .pairedWith: return notes.compactMap(menuNote)
        }
    }

    /// Beside a touchscreen's name in the menu: its display's name while it works with one; else its
    /// state. A touchscreen Tactile can't use says so, whatever its status.
    static func menuRowDetail(for touchscreen: TouchscreenSnapshot) -> String {
        if touchscreen.mode == .settingUp {
            return menuBeingSetUp
        }
        if MenuTouchscreenDetails.Unusable(touchscreen) != nil {
            return menuCannotBeUsed
        }
        switch touchscreen.status {
        case .pairedWith(let name, _): return name
        case .displayNotConnected(let name): return missingDisplay(name: name)
        case .notSetUp: return "Not set up"
        case .off: return "Off"
        case .notConnected: return "Not connected"
        case .tactileOff, .accessibilityMissing: return "Left to macOS"
        }
    }

    static let menuCannotBeUsed = "Can’t be used"

    /// The line beneath a touchscreen's name in its details: its display, its size (the diagonal in
    /// force, as the pane's Diagonal field has it), its state, and the notes that limit it.
    /// "HDMI · 23.8″ · driving".
    static func menuSummary(for touchscreen: TouchscreenSnapshot) -> String {
        var parts: [String] = []
        if let display = touchscreen.pairedDisplayName {
            parts.append(display)
        }
        if let diagonal = touchscreen.diagonalInches ?? touchscreen.reportedDiagonalInches {
            parts.append(inches(diagonal))
        }
        parts.append(menuSummaryState(touchscreen))
        parts += menuNotes(touchscreen.status, notes: touchscreen.notes)
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    private static func menuSummaryState(_ touchscreen: TouchscreenSnapshot) -> String {
        if touchscreen.mode == .settingUp {
            return "being set up"
        }
        switch touchscreen.status {
        case .notConnected: return "not connected"
        case .tactileOff, .accessibilityMissing: return "left to macOS"
        case .off: return "off"
        case .notSetUp: return "not set up"
        case .displayNotConnected: return "display not connected"
        case .pairedWith: return touchscreen.mode == .driving ? "driving" : "not driving"
        }
    }

    /// Why a connected touchscreen can't be used, in its details.
    static func menuCannotBeUsed(_ reason: MenuTouchscreenDetails.Unusable) -> String {
        switch reason {
        case .cannotBeToldApart: return note(.cannotBeToldApart)
        case .touchesCannotBeRead: return "Tactile can’t read its touches."
        case .macOSAlsoHandlesIt:
            return "macOS is also handling this touchscreen, so Tactile doesn’t drive it. Quit any other app that reads it, then unplug it and plug it back in."
        }
    }

    /// The details' last item: its pane in Settings.
    static func settingsFor(name: String) -> String { "Settings for \(name)…" }
    /// What choosing a touchscreen's row does, for VoiceOver.
    static let menuShowsDetails = "Shows its details"

    /// A touchscreen's submenu in the plain menu: "ILITEK-TP — HDMI".
    static func menuRow(name: String, detail: String) -> String { "\(name) \u{2014} \(detail)" }
    /// The details' switch for the touch circles: the same words as the pane's, so the person finds
    /// one name for one switch.
    public static let showTouches = touchCircles

    private static func menuNote(_ note: TouchscreenNote) -> String? {
        switch note {
        case .oneFingerOnly: return "one finger only"
        case .macOSMayAlsoRespond: return "macOS may also respond"
        case .touchesCannotBeRead: return "touches can’t be read"
        case .cannotBeToldApart: return "can’t be told apart"
        case .rememberedByPort, .macOSIgnoresIt: return nil
        }
    }

    public static let menuTactileOn = "Tactile On"
    public static let menuSettings = "Settings…"
    public static let menuQuit = "Quit Tactile"
    public static let touchscreens = "Touchscreens"
    public static let noTouchscreens = "None connected"

    // MARK: - Warnings

    public static func warningTitle(_ warning: AppWarning) -> String {
        switch warning {
        case .accessibilityMissing: return "Accessibility access missing"
        case .touchUpRunning: return "Touch Up is running"
        case .missionControlShortcutsOff: return "The Mission Control shortcuts are off"
        case .settingsSetAside: return "The settings file couldn’t be read"
        }
    }

    public static func warningDetail(_ warning: AppWarning) -> String {
        switch warning {
        case .accessibilityMissing:
            // The second sentence is for a stale entry: after a build signed differently (an
            // install.sh build, then a download, or the other way round), macOS keeps the old
            // entry, switched on, and refuses Tactile. Only removing it and adding it again helps.
            return "Tactile can’t drive touchscreens without it, so it leaves them all to macOS. If Tactile is already listed and switched on in Accessibility settings, remove it with − and add it again with +."
        case .touchUpRunning:
            return "Quit it, or both apps will act on the same touches."
        case .missionControlShortcutsOff:
            return "Swipes need them. Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control."
        case .settingsSetAside:
            return "It was set aside as settings.json.broken, and Tactile started from the defaults."
        }
    }

    /// The button beside a warning, when there is something Tactile can do about it.
    public static func warningAction(_ warning: AppWarning) -> WarningAction? {
        switch warning {
        case .accessibilityMissing:
            return WarningAction(title: "Open Accessibility Settings…", kind: .command(.askForAccessibility))
        case .missionControlShortcutsOff:
            return WarningAction(title: "Open Keyboard Settings…", kind: .openKeyboardSettings)
        case .touchUpRunning:
            return WarningAction(title: "Quit Touch Up", kind: .quitTouchUp)
        case .settingsSetAside:
            return nil
        }
    }

    // MARK: - Displays

    /// A display's label: its name, then the line that tells it apart.
    /// `HDMI — 23.8″ · 2560 × 1440 · above the main display`.
    public static func displayLabel(name: String, detail: String) -> String {
        detail.isEmpty ? name : "\(name) \u{2014} \(detail)"
    }

    /// A display in the Display pop-up, with the touchscreen that has it now, if another has.
    public static func displayChoice(_ choice: DisplayChoice) -> String {
        let label = displayLabel(name: choice.name, detail: choice.detail)
        guard let other = choice.inUseBy else { return label }
        return "\(label) (in use by \(other))"
    }

    /// The Display pop-up's selection while the paired display is away. It can't be chosen.
    public static func missingDisplay(name: String) -> String { "\(name) (not connected)" }

    public static let unpaired = "Unpaired"
    public static let identify = "Identify"
    public static let renameDisplay = "Rename…"

    public static func renameDisplayTitle(name: String) -> String { "Rename “\(name)”" }
    public static let renameDisplayMessage = "Empty uses the name macOS gives it."

    // MARK: - The controls of a touchscreen's pane

    public static let display = "Display"
    public static let orientation = "Orientation"
    public static let diagonal = "Diagonal"
    public static let whenOffLabel = "When off"
    public static let on = "On"

    public static func whenOff(_ choice: WhenOff) -> String {
        switch choice {
        case .ignoreTouches: return "Ignore touches"
        case .leaveToMacOS: return "Leave it to macOS"
        }
    }

    /// A turn of the glass, in degrees: "0°" … "270°".
    public static func quarterTurns(_ turns: Int) -> String { "\((turns & 3) * 90)°" }
    public static let flip = "Flip"

    /// A diagonal in inches to one decimal, the decimal dropped when it is 0: "23.8″", "27″".
    public static func inches(_ value: Double) -> String {
        guard value.isFinite, let tenths = Int(exactly: (value * 10).rounded()) else { return "?″" }
        let whole = tenths / 10, decimal = abs(tenths % 10)
        return (decimal == 0 ? "\(whole)" : "\(whole).\(decimal)") + "\u{2033}"
    }

    /// What the paired display reports, beside the Diagonal field: "HDMI reports 27″".
    public static func reportedDiagonal(displayName: String?, inches value: Double?) -> String? {
        guard let value else { return nil }
        return "\(displayName ?? "The display") reports \(inches(value))"
    }

    public static let diagonalPrompt = "As reported"
    public static let inchesUnit = "inches"
    public static let diagonalFootnote =
        "Gestures are measured in millimetres on the glass, so this needs to be right. Leave it empty to use what the display reports."

    public static let rename = "Rename"
    public static let renameFootnote = "Empty uses the touchscreen’s own name."

    // MARK: - Set-up by touch, alignment and test

    public static let setUpByTouch = "Set Up by Touch…"

    /// Why Set Up by Touch…, Calibrate Corners… or Test can't be used now.
    static func setUpUnavailable(_ reason: SetUpAvailability.Reason) -> String {
        switch reason {
        case .notConnected: return "It isn’t connected."
        case .beingSetUp: return "It is being set up now."
        case .anotherBeingSetUp: return "Another touchscreen is being set up."
        case .setUpModeOn: return "Set-up is running on the screens."
        case .tactileOff: return "Turn Tactile on to set it up."
        case .accessibilityMissing: return "Tactile needs Accessibility access to set it up."
        case .cannotBeToldApart: return "Tactile can’t keep settings for it."
        case .touchesCannotBeRead: return "Its touches can’t be read."
        case .macOSAlsoHandlesIt:
            return "macOS is also handling this touchscreen, so it can’t be set up. Quit any other app that reads it, then unplug it and plug it back in."
        case .noExternalDisplay: return "Connect an external display first."
        case .notNow: return "Set-up can’t begin just now. Try again in a moment."
        case .noDisplayToChoose: return setUpNoDisplayToChoose
        case .unpaired: return "Pair it with a display first."
        case .displayNotConnected: return "Its display isn’t connected."
        }
    }

    /// Beneath the controls that change a fit (Display, Orientation, Diagonal, Use Whole Glass,
    /// Forget) while set-up mode is on or a set-up runs, of any touchscreen.
    public static let setUpRunning = "A set-up is running. Finish or cancel it to change these."

    public static let alignment = "Alignment"

    /// Beneath Alignment: whether the picture's edges were fitted to the glass by four taps.
    public static func alignmentState(isCalibrated: Bool) -> String {
        isCalibrated ? "Calibrated" : "Whole glass"
    }

    public static let calibrateCorners = "Calibrate Corners…"
    public static let test = "Test"
    public static let useWholeGlass = "Use Whole Glass"
    public static func useWholeGlassQuestion(name: String) -> String { "Use the whole glass for “\(name)”?" }
    public static let useWholeGlassMessage =
        "Its calibration is forgotten, and touches map to the whole glass until it is calibrated again."

    // MARK: - Behaviour

    public static let behaviour = "Behaviour"
    public static let oneFingerLabel = "One finger"

    public static func oneFinger(_ mode: OneFingerMode) -> String {
        switch mode {
        case .automatic: return "Automatic"
        case .alwaysDrag: return "Always drag"
        case .alwaysScroll: return "Always scroll"
        }
    }

    /// The One finger pop-up's first choice: the default, with the mode it gives on this
    /// touchscreen.
    public static func oneFingerDefault(_ mode: OneFingerMode) -> String { "Default (\(oneFinger(mode)))" }

    /// Beneath One finger, for the mode in force. Always scroll says how to drag: a finger that
    /// rests, then moves, drags whatever the mode; `ringShows` says whether a ring marks the moment
    /// (long-press on, and the touch circles shown).
    public static func oneFingerExplanation(_ mode: OneFingerMode, ringShows: Bool) -> String {
        switch mode {
        case .automatic: return "Drags or scrolls depending on what’s under it"
        case .alwaysDrag: return "Drags, as a mouse would"
        case .alwaysScroll:
            return ringShows
                ? "Scrolls, as on a phone. To drag, rest a finger until the ring appears, then move it."
                : "Scrolls, as on a phone. To drag, rest a finger for a moment, then move it."
        }
    }

    public static let pointerReturnLabel = "After a touch, the pointer"

    public static func pointerReturn(_ choice: PointerReturn) -> String {
        switch choice {
        case .backWhereItWas: return "Goes back where it was"
        case .staysWhereTouched: return "Stays where you touched"
        }
    }

    public static let touchCircles = "Touch circles"

    // MARK: - Gestures

    public static let gestures = "Gestures"

    static func gesture(_ kind: GestureRow.Kind) -> String {
        switch kind {
        case .twoFingerScroll: return "Two-finger scroll"
        case .pinch: return "Pinch to zoom"
        case .twoFingerTap: return "Two-finger tap for right-click"
        case .swipes: return "Three- and four-finger swipes"
        case .rotate: return "Two-finger rotate"
        case .longPress: return "Long-press for right-click"
        }
    }

    static func gestureExplanation(_ kind: GestureRow.Kind) -> String? {
        switch kind {
        case .swipes: return "Desktops, Mission Control and App Exposé"
        case .longPress: return "Rest a finger for a moment, then lift it"
        case .twoFingerScroll, .pinch, .twoFingerTap, .rotate: return nil
        }
    }

    /// Beneath the gestures of a touchscreen that reads one finger.
    public static let oneFingerOnlyGestures =
        "One finger only: this touchscreen stayed in mouse mode. Long-press is its right-click."
    /// Beneath the gestures while the Mission Control shortcuts are off.
    public static let swipesNeedShortcuts =
        "Swipes need the Mission Control shortcuts, which are off. Turn them on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control."

    // MARK: - Accidental touches

    public static let accidentalTouches = "Accidental touches"
    public static let palmRejection = "Palm rejection"

    public static func palmExplanation(reportsPalms: Bool) -> String {
        reportsPalms
            ? "Ignores a resting palm, and a whole hand on the glass."
            : "This touchscreen doesn’t report the size of a touch, so only a whole hand can be recognised."
    }

    public static let edgeMargin = "Ignore touches starting near the edge"

    /// The margin beside its slider: "Off", "4 mm", "2.5 mm".
    public static func edgeMarginValue(_ millimetres: Double) -> String {
        guard millimetres.isFinite, millimetres > 0 else { return "Off" }
        let tenths = (millimetres * 10).rounded() / 10
        let text = tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
        return "\(text) mm"
    }

    // MARK: - Copy and Reset

    public static let copySettingsFrom = "Copy Settings From…"

    /// A touchscreen in the Copy Settings From… menu.
    public static func copySource(name: String, isConnected: Bool) -> String {
        isConnected ? name : "\(name) (not connected)"
    }

    public static let reset = "Reset"
    public static func resetQuestion(name: String) -> String { "Reset the behaviour of “\(name)”?" }
    public static let resetMessage =
        "One finger, the pointer, touch circles, gestures, accidental touches and When off go back to their defaults. The display, orientation and diagonal stay as they are."
    public static let behaviourFootnote = "Copy and Reset change the behaviour settings only, never the pairing."

    // MARK: - Forget

    public static let forgetButton = "Forget This Touchscreen…"
    public static func forgetQuestion(name: String) -> String { "Forget “\(name)”?" }
    public static let forgetMessage =
        "Tactile forgets its pairing and settings. If it is connected again, it starts as a new touchscreen."
    public static let forgetConfirm = "Forget"
    public static let cancel = "Cancel"

    // MARK: - General

    public static let general = "General"
    public static let tactile = "Tactile"
    public static let tactileExplanation = "Turns every touchscreen on or off. Also in the menu bar."
    public static let diagnostics = "Diagnostics"
    public static let debugLogging = "Debug logging"
    public static let debugLoggingExplanation = "Adds every frame to the log."
    public static let diagnosticsFootnote =
        "Tactile logs to the unified log under its own subsystem, and keeps the current state in ~/Library/Application Support/Tactile/state.json."

    public static let launchAtLogin = "Launch at login"

    /// Beneath Launch at login, for the states that need a word: what is wrong, or what to do.
    public static func launchAtLoginNote(_ state: LaunchAtLogin) -> String? {
        switch state {
        case .off, .on: return nil
        case .needsApproval: return "Allow Tactile in Login Items."
        case .notInstalled: return "Install Tactile in the Applications folder first."
        case .unavailable: return "macOS wouldn’t register Tactile to open at login."
        }
    }

    public static let openLoginItemsSettings = "Open Login Items Settings…"

    /// The heading of General's last group: what may change or go.
    public static let experimental = "Experimental"
    public static let swipesFollowFingers = "Swipes follow the fingers"
    /// Beneath Swipes follow the fingers: what it does, and the way back if a Desktop sticks. The
    /// command is in backticks, shown as code.
    public static let swipesFollowFingersExplanation =
        "Three- and four-finger swipes left and right slide between Desktops with your fingers. If a Desktop gets stuck half way, switch this off and run `killall Dock` in Terminal."
    /// Why it can't be switched on here, true of every cause: the Dock-swipe sender knows macOS up
    /// to 26 (Tactile itself needs 14), and needs the person's trackpad gesture for switching Spaces
    /// on, which a Mac that has never had a trackpad doesn't have (`DockSwipeSender.isAvailable`).
    public static let swipesFollowFingersUnavailable =
        "Needs macOS 26 or earlier, and a trackpad’s “Swipe between full-screen applications” switched on in System Settings › Trackpad › More Gestures."

    public static let recordFrames = "Record frames"
    /// Names the folder the app records to, from the one definition (`TactileFolders.frames`).
    public static var recordFramesExplanation: String {
        "Writes each touchscreen’s frames to a file in \(TactileFolders.framesShown), for use as tests."
    }
    public static let copyDiagnosticsLabel = "Copy diagnostics"
    public static let copyDiagnosticsExplanation = "Touchscreens, displays, pairings, states and warnings."
    public static let copyDiagnosticsButton = "Copy"
    /// What the Copy button says for a moment after it is pressed.
    public static let copied = "Copied"

    public static func version(_ version: String) -> String { "Version \(version)" }
    /// As NOTICE.md says: Touch Up, by Sebastian Hueber, under the MIT licence.
    public static let credit = "Inspired by Touch Up by Sebastian Hueber"

    public static let settingsWindowTitle = "Tactile Settings"
}
