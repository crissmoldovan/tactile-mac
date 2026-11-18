import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens

public enum TouchscreenMode: String, Codable, Sendable {
    case driving, held, released
    case settingUp
}

public enum AppWarning: String, Codable, Sendable, CaseIterable {
    case accessibilityMissing, touchUpRunning, missionControlShortcutsOff, settingsSetAside
}

/// The one line under a touchscreen's name.
public enum TouchscreenStatus: Equatable, Codable, Sendable {
    case notConnected
    case tactileOff
    case accessibilityMissing
    case off
    case notSetUp
    /// Paired, and its display is not connected now. The name is the display's last known name.
    case displayNotConnected(name: String)
    /// Paired and working. The two strings are the display's label: its name and its telling-apart line.
    case pairedWith(name: String, detail: String)
}

public enum TouchscreenNote: String, Codable, Sendable {
    case oneFingerOnly, macOSMayAlsoRespond, touchesCannotBeRead, rememberedByPort
    case macOSIgnoresIt        // "Leave it to macOS" would do nothing: macOS ignores this touchscreen by itself
    case cannotBeToldApart     // no USB location, and another connected touchscreen is identical: it has no record
}

public struct BehaviourSnapshot: Equatable, Codable, Sendable {
    /// The one-finger mode in force.
    public var oneFinger: OneFingerMode
    /// The person's one-finger choice; nil: the default for this touchscreen.
    public var oneFingerChoice: OneFingerMode?
    public var pointerReturn: PointerReturn
    public var showsCircles: Bool
    /// As stored, long-press and rotate included. On a one-finger-only touchscreen the multi-finger
    /// ones are stored but not in force.
    public var gestures: GestureOptions
    public var rejection: RejectionRules
    /// Whether this touchscreen reports contact size or confidence. When false, palm rejection can
    /// only act on a whole hand, and the pane says so.
    public var reportsPalms: Bool
    /// False on a one-finger-only touchscreen: its gesture switches are shown off and disabled.
    public var multiFingerAvailable: Bool

    public init(
        oneFinger: OneFingerMode,
        oneFingerChoice: OneFingerMode?,
        pointerReturn: PointerReturn,
        showsCircles: Bool,
        gestures: GestureOptions,
        rejection: RejectionRules,
        reportsPalms: Bool,
        multiFingerAvailable: Bool
    ) {
        self.oneFinger = oneFinger
        self.oneFingerChoice = oneFingerChoice
        self.pointerReturn = pointerReturn
        self.showsCircles = showsCircles
        self.gestures = gestures
        self.rejection = rejection
        self.reportsPalms = reportsPalms
        self.multiFingerAvailable = multiFingerAvailable
    }
}

public struct DisplayChoice: Equatable, Codable, Sendable, Identifiable {
    public var id: UInt32            // the connected display's ID
    public var name: String
    public var detail: String
    /// The other touchscreen this display is paired with now, if any. Choosing it moves the pairing.
    public var inUseBy: String?

    public init(id: UInt32, name: String, detail: String, inUseBy: String?) {
        self.id = id
        self.name = name
        self.detail = detail
        self.inUseBy = inUseBy
    }
}

public struct TouchscreenSnapshot: Equatable, Codable, Sendable, Identifiable {
    public var id: TouchscreenID
    public var name: String              // custom name, else the device's own
    public var deviceName: String
    public var isConnected: Bool
    public var isOn: Bool
    public var whenOff: WhenOff
    public var mode: TouchscreenMode?    // nil when not connected
    public var status: TouchscreenStatus
    public var notes: [TouchscreenNote]
    public var pairedDisplayID: UInt32?  // the connected display it is paired with now
    /// The display it is paired with, by name: its custom name, else its last known macOS name.
    /// Filled whenever it is paired, whether or not the display or the touchscreen is connected;
    /// nil when it is unpaired.
    public var pairedDisplayName: String?
    public var displayChoices: [DisplayChoice]
    public var orientation: Orientation? // nil when unpaired
    public var diagonalInches: Double?   // the override; nil means as reported
    public var reportedDiagonalInches: Double?  // what its display reports, when paired and connected
    public var usbID: String             // "222a:0001"
    public var serial: String
    public var location: String?         // "01141000" when connected
    public var device: String?           // input mode, touch origin and exclusive access, for diagnostics
    public var behaviour: BehaviourSnapshot
    public var isCalibrated: Bool          // its alignment is not the whole glass
    /// Set-up mode could begin now (`AppSnapshot.setUpModeRefusal` is nil), and this touchscreen
    /// could be set up in it: connected, told apart from the others, its touches readable, and macOS
    /// not acting on them too. No display need be free: the person chooses one in the mode, and may
    /// take it from another touchscreen.
    public var canBeSetUp: Bool

    public init(
        id: TouchscreenID,
        name: String,
        deviceName: String,
        isConnected: Bool,
        isOn: Bool,
        whenOff: WhenOff,
        mode: TouchscreenMode?,
        status: TouchscreenStatus,
        notes: [TouchscreenNote],
        pairedDisplayID: UInt32?,
        pairedDisplayName: String?,
        displayChoices: [DisplayChoice],
        orientation: Orientation?,
        diagonalInches: Double?,
        reportedDiagonalInches: Double?,
        usbID: String,
        serial: String,
        location: String?,
        device: String?,
        behaviour: BehaviourSnapshot,
        isCalibrated: Bool,
        canBeSetUp: Bool
    ) {
        self.id = id
        self.name = name
        self.deviceName = deviceName
        self.isConnected = isConnected
        self.isOn = isOn
        self.whenOff = whenOff
        self.mode = mode
        self.status = status
        self.notes = notes
        self.pairedDisplayID = pairedDisplayID
        self.pairedDisplayName = pairedDisplayName
        self.displayChoices = displayChoices
        self.orientation = orientation
        self.diagonalInches = diagonalInches
        self.reportedDiagonalInches = reportedDiagonalInches
        self.usbID = usbID
        self.serial = serial
        self.location = location
        self.device = device
        self.behaviour = behaviour
        self.isCalibrated = isCalibrated
        self.canBeSetUp = canBeSetUp
    }
}

public enum SetUpPurpose: String, Codable, Sendable {
    case full          // corners, size, check, on the display chosen in set-up mode (no pair step)
    case calibrate     // corners, check: the display is already known
    case test          // check only, with the mapping it has
}

public enum SetUpStep: Equatable, Codable, Sendable {
    /// One target at a time, at a point of the display's picture (0…1). `problem` says why the last round was refused.
    case corners(display: UInt32, target: CGPoint, index: Int, problem: SetUpProblem?)
    /// The two reported diagonals, in inches, where each is known and plausible; and the override in force.
    case size(display: UInt32, displayReports: Double?, touchscreenReports: Double?, current: Double?)
    /// Touches are shown where they land. Nothing is stored until Done.
    case check(display: UInt32)
}

public enum SetUpProblem: String, Codable, Sendable { case tapsDidNotFit, ambiguous, tooManyFingers, moved }

public struct SetUpSnapshot: Equatable, Codable, Sendable {
    public var touchscreen: TouchscreenID
    public var touchscreenName: String
    public var purpose: SetUpPurpose
    public var step: SetUpStep

    public init(touchscreen: TouchscreenID, touchscreenName: String, purpose: SetUpPurpose, step: SetUpStep) {
        self.touchscreen = touchscreen
        self.touchscreenName = touchscreenName
        self.purpose = purpose
        self.step = step
    }
}

/// Set-up mode, while it is on: every touchscreen in a single pass. Every candidate display offers
/// itself; the person clicks the display that has a touchscreen, then touches it (or touches first,
/// then clicks); the corners, size and check follow, one touchscreen at a time; each finished
/// touchscreen is confirmed on its card; **Finish** or Esc leaves. No timer decides anything about
/// pairing: which display comes only from a click, which touchscreen only from a touch.
public struct SetUpModeSnapshot: Equatable, Codable, Sendable {
    public enum Stage: Equatable, Codable, Sendable {
        /// Every candidate display offers itself.
        case choosing
        /// "Now touch this screen": the display chosen, waiting for a touch.
        case waitingForTouch(display: UInt32)
        /// "You touched …: click the screen you touched".
        case touchedFirst(touchscreen: TouchscreenID, name: String)
        /// A flow runs: `AppSnapshot.setUp` has it.
        case running
    }

    public var stage: Stage
    public var displays: [SetUpDisplayCard]          // the candidate displays, in screen order
    public var touchscreens: [SetUpTouchscreenLine]  // every connected touchscreen
    public var justSetUp: TouchscreenID?             // the last one Done in this session
    public var notice: SetUpModeNotice?              // the latest thing to tell, until the next stage change

    public init(
        stage: Stage,
        displays: [SetUpDisplayCard],
        touchscreens: [SetUpTouchscreenLine],
        justSetUp: TouchscreenID?,
        notice: SetUpModeNotice?
    ) {
        self.stage = stage
        self.displays = displays
        self.touchscreens = touchscreens
        self.justSetUp = justSetUp
        self.notice = notice
    }
}

/// One candidate display in set-up mode's overview: a connected display that is not built in. Its
/// card offers it (**This one**), or, when a touchscreen is paired with it, says so and offers
/// **Test** and **Set Up Again Here**.
public struct SetUpDisplayCard: Equatable, Codable, Sendable, Identifiable {
    public var id: UInt32                    // display ID
    public var name: String
    public var detail: String
    public var touchscreen: TouchscreenID?   // paired with it now, if any
    public var touchscreenName: String?

    public init(id: UInt32, name: String, detail: String, touchscreen: TouchscreenID?, touchscreenName: String?) {
        self.id = id
        self.name = name
        self.detail = detail
        self.touchscreen = touchscreen
        self.touchscreenName = touchscreenName
    }
}

/// One connected touchscreen's line on set-up mode's session card: set up on a display, not set up,
/// or can't be set up (with the reason).
public struct SetUpTouchscreenLine: Equatable, Codable, Sendable, Identifiable {
    public enum State: Equatable, Codable, Sendable {
        case setUp(displayName: String)
        case notSetUp
        case cannotBeSetUp
    }

    public var id: TouchscreenID
    public var name: String
    public var state: State
    public var reason: String?               // for cannotBeSetUp: why, as the pane words it

    public init(id: TouchscreenID, name: String, state: State, reason: String?) {
        self.id = id
        self.name = name
        self.state = state
        self.reason = reason
    }
}

/// The latest thing set-up mode has to tell: one line on the session card, until the stage changes.
public enum SetUpModeNotice: Equatable, Codable, Sendable {
    /// A touch from a touchscreen that can't be set up.
    case cannotBeSetUp(touchscreen: TouchscreenID, name: String)
    /// The chosen display went away.
    case displayGone(name: String)
    /// The answering touchscreen went away.
    case touchscreenGone(name: String)
}

public struct DisplaySnapshot: Equatable, Codable, Sendable, Identifiable {
    public var id: UInt32
    public var uuid: String
    public var name: String              // custom name, else the macOS name
    public var detail: String
    public var frame: CGRect             // global, origin top-left of the main display
    public var isBuiltIn: Bool
    public var isMain: Bool
    public var pairedTouchscreen: String?

    public init(
        id: UInt32,
        uuid: String,
        name: String,
        detail: String,
        frame: CGRect,
        isBuiltIn: Bool,
        isMain: Bool,
        pairedTouchscreen: String?
    ) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.detail = detail
        self.frame = frame
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.pairedTouchscreen = pairedTouchscreen
    }
}

/// Why set-up mode can't begin now, as the model found it (`Resolver.setUpModeRefusal`), so that the
/// menu's Set Up Touchscreens… and a pane's Set Up by Touch… say the model's reason rather than
/// guess it. The cases are in the order the model asks.
public enum SetUpModeRefusal: String, Codable, Sendable, Equatable {
    /// It passes: Tactile is quitting, the session isn't active (locked, or switched out), the Mac
    /// is asleep, or the displays are reconfiguring.
    case notNow
    case tactileOff
    case accessibilityMissing
    /// No display is connected.
    case noDisplay
    /// Set-up mode is on, or a Calibrate or Test flow runs.
    case running
    /// No connected touchscreen can be set up.
    case noTouchscreenCanBeSetUp
    /// Displays are connected, and none can have a card: the built-in display never does, nor does
    /// a member of a mirror set, which a click can't tell apart from the others.
    case noDisplayToChoose
}

public enum LaunchAtLogin: String, Codable, Sendable {
    case off, on
    case needsApproval      // registered, and waiting for the person in System Settings › Login Items
    case notInstalled       // Tactile is not running from the Applications folder
    case unavailable        // the system refused, or can't say
}

public struct AppSnapshot: Equatable, Codable, Sendable {
    public var appVersion: String
    public var isOn: Bool
    public var warnings: [AppWarning]
    /// Connected touchscreens first, in the order they connected; then remembered ones, by name.
    public var touchscreens: [TouchscreenSnapshot]
    public var displays: [DisplaySnapshot]
    public var debugLogging: Bool
    /// The running flow, in set-up mode or outside it.
    public var setUp: SetUpSnapshot?
    /// Set-up mode; nil when the mode is off.
    public var setUpMode: SetUpModeSnapshot?
    /// The touchscreens the first-run window names; empty: no window.
    public var offerSetUpTo: [TouchscreenID]
    /// Why set-up mode can't begin now; nil when it can.
    public var setUpModeRefusal: SetUpModeRefusal?
    /// The gesture tester; nil when it is closed.
    public var gestureTester: GestureTesterSnapshot?
    public var recordsFrames: Bool
    /// The setting: three- and four-finger swipes left and right follow the fingers, where they can.
    public var swipesFollowFingers: Bool
    /// The sender is available for horizontal swipes on this Mac.
    public var canFollowSwipes: Bool
    public var launchAtLogin: LaunchAtLogin

    public init(
        appVersion: String,
        isOn: Bool,
        warnings: [AppWarning],
        touchscreens: [TouchscreenSnapshot],
        displays: [DisplaySnapshot],
        debugLogging: Bool,
        setUp: SetUpSnapshot?,
        setUpMode: SetUpModeSnapshot?,
        offerSetUpTo: [TouchscreenID],
        setUpModeRefusal: SetUpModeRefusal?,
        gestureTester: GestureTesterSnapshot?,
        recordsFrames: Bool,
        swipesFollowFingers: Bool,
        canFollowSwipes: Bool,
        launchAtLogin: LaunchAtLogin
    ) {
        self.appVersion = appVersion
        self.isOn = isOn
        self.warnings = warnings
        self.touchscreens = touchscreens
        self.displays = displays
        self.debugLogging = debugLogging
        self.setUp = setUp
        self.setUpMode = setUpMode
        self.offerSetUpTo = offerSetUpTo
        self.setUpModeRefusal = setUpModeRefusal
        self.gestureTester = gestureTester
        self.recordsFrames = recordsFrames
        self.swipesFollowFingers = swipesFollowFingers
        self.canFollowSwipes = canFollowSwipes
        self.launchAtLogin = launchAtLogin
    }
}
