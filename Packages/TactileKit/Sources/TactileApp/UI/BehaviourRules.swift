// The interface's decisions for the set-up and behaviour controls, kept pure: when set-up mode can
// begin and why not; when Calibrate Corners… and Test can be used; when the controls that change a
// fit can; a touchscreen that can't be told apart; the one-finger pop-up; the gesture switches; the
// edge margin; what Copy Settings From… lists; and when the first-run window is shown.

import Foundation
import TactileGestures
import TactileScreens

// MARK: - Set-up

/// Whether a set-up can be begun from a touchscreen's pane now, and if not, why: the reason is shown
/// beneath the disabled button. Set Up by Touch… begins set-up mode, which covers every touchscreen,
/// but is disabled with this touchscreen's reason when it is one the mode can't set up; calibration
/// and test need instead its paired display connected. For all three: what the mode table says ends
/// a set-up at once (Tactile off, no Accessibility access), one set-up at a time, a touchscreen with
/// no record, one whose touches can't be read, and one in mouse mode that macOS also handles.
enum SetUpAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case notConnected
        case beingSetUp
        case anotherBeingSetUp
        /// Set-up mode is on, between flows: every touchscreen is in it.
        case setUpModeOn
        case tactileOff
        case accessibilityMissing
        case cannotBeToldApart
        case touchesCannotBeRead
        /// Its touches come from its mouse interface and macOS still sees it (Tactile couldn't take it
        /// for itself): the model refuses every set-up of it, paired or not.
        case macOSAlsoHandlesIt
        /// A touchscreen check found it had stopped answering: it is left released until it is
        /// plugged in again (`TouchscreenStatus.stoppedAnswering`).
        case stoppedAnswering
        /// Set Up by Touch…: there is no external display at all.
        case noExternalDisplay
        /// Set Up by Touch…: everything the interface can see allows it, and the model says the mode
        /// can't begin just now (`SetUpModeRefusal.notNow`): the displays are settling, the session
        /// isn't active, or the Mac is asleep.
        case notNow
        /// Set Up by Touch…: the model says no external display can be chosen
        /// (`SetUpModeRefusal.noDisplayToChoose`): each is in a mirror set.
        case noDisplayToChoose
        /// Calibrate and Test: it isn't paired.
        case unpaired
        /// Calibrate and Test: its display isn't connected.
        case displayNotConnected
    }

    var reason: Reason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    /// Set Up by Touch…: set-up mode, from this touchscreen's pane. Taking a display from another
    /// touchscreen is allowed, so no display has to be free; one external display has to exist.
    static func full(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> SetUpAvailability {
        if let reason = common(touchscreen, in: snapshot) {
            return .unavailable(reason)
        }
        guard snapshot.displays.contains(where: { !$0.isBuiltIn }) else { return .unavailable(.noExternalDisplay) }
        guard touchscreen.canBeSetUp else {
            return .unavailable(snapshot.setUpModeRefusal.map { reason(for: $0, touchscreen, in: snapshot) } ?? .notNow)
        }
        return .available
    }

    /// Set Up by Touch…: the model's reason the mode can't begin (`AppSnapshot.setUpModeRefusal`),
    /// in the pane's words.
    private static func reason(
        for refusal: SetUpModeRefusal, _ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot
    ) -> Reason {
        switch refusal {
        case .notNow: return .notNow
        case .tactileOff: return .tactileOff
        case .accessibilityMissing: return .accessibilityMissing
        case .noDisplay: return .noExternalDisplay
        case .running:
            guard let running = snapshot.setUp else { return .setUpModeOn }
            return running.touchscreen == touchscreen.id ? .beingSetUp : .anotherBeingSetUp
        // The pane has found nothing against this touchscreen, and the model says none can be set
        // up: what it saw, the pane can't name.
        case .noTouchscreenCanBeSetUp: return .notNow
        case .noDisplayToChoose: return .noDisplayToChoose
        }
    }

    /// The first-run window's offer: as `full`, except that whether the mode can begin now is left
    /// to the model's `offerSetUpTo`, which it keeps through a display reconfiguration.
    static func offered(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> SetUpAvailability {
        common(touchscreen, in: snapshot).map { .unavailable($0) } ?? .available
    }

    /// Calibrate Corners… and Test: on the display it is paired with, which must be connected.
    /// `canBeSetUp` is about set-up mode, and plays no part here.
    static func onItsDisplay(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> SetUpAvailability {
        if let reason = common(touchscreen, in: snapshot) {
            return .unavailable(reason)
        }
        guard touchscreen.isPaired else { return .unavailable(.unpaired) }
        guard touchscreen.pairedDisplayID != nil else { return .unavailable(.displayNotConnected) }
        return .available
    }

    private static func common(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> Reason? {
        guard touchscreen.isConnected else { return .notConnected }
        if let running = snapshot.setUp {
            return running.touchscreen == touchscreen.id ? .beingSetUp : .anotherBeingSetUp
        }
        guard snapshot.setUpMode == nil else { return .setUpModeOn }
        guard snapshot.isOn else { return .tactileOff }
        guard !snapshot.warnings.contains(.accessibilityMissing) else { return .accessibilityMissing }
        guard touchscreen.canChangeSettings else { return .cannotBeToldApart }
        guard touchscreen.status != .stoppedAnswering else { return .stoppedAnswering }
        guard !touchscreen.notes.contains(.touchesCannotBeRead) else { return .touchesCannotBeRead }
        guard !touchscreen.macOSAlsoHandlesIt else { return .macOSAlsoHandlesIt }
        return nil
    }
}

extension TouchscreenSnapshot {
    /// Whether it stayed in mouse mode and macOS still sees it: its two notes together. The model
    /// holds it (driving it too would handle every touch twice) and begins no set-up of it.
    var macOSAlsoHandlesIt: Bool {
        notes.contains(.oneFingerOnly) && notes.contains(.macOSMayAlsoRespond)
    }

    /// Whether set-up mode could set it up, as far as the touchscreen itself goes: connected, with a
    /// record, its touches readable, and not also handled by macOS. Whether a display is free plays
    /// no part: taking one from another touchscreen is allowed.
    var canBeSetUpByTouch: Bool {
        isConnected && canChangeSettings && !notes.contains(.touchesCannotBeRead) && !macOSAlsoHandlesIt
    }
}

/// Whether set-up mode could begin now, and if not, why: the menu's Set Up Touchscreens… is enabled
/// by it, with the reason beneath when it isn't. The mode begins when Tactile is on, Accessibility
/// is granted, no set-up runs, a connected touchscreen can be set up and an external display exists;
/// what only the model can see (the displays settling, the displays mirrored) it says through
/// `AppSnapshot.setUpModeRefusal`.
enum SetUpModeAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        /// Set-up mode, or a Calibrate or Test flow, is running.
        case running
        case tactileOff
        case accessibilityMissing
        /// No touchscreen is connected.
        case noTouchscreen
        /// Touchscreens are connected, and none of them can be set up (`canBeSetUpByTouch`).
        case noneCanBeSetUp
        case noExternalDisplay
        /// Everything the interface can see allows it; the model says not just now
        /// (`SetUpModeRefusal.notNow`).
        case notNow
        /// Everything the interface can see allows it, and the model says no external display can be
        /// chosen, each being in a mirror set (`SetUpModeRefusal.noDisplayToChoose`).
        case noDisplayToChoose
    }

    var reason: Reason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    init(_ snapshot: AppSnapshot) {
        self = Self.reason(snapshot).map { .unavailable($0) } ?? .available
    }

    private static func reason(_ snapshot: AppSnapshot) -> Reason? {
        guard snapshot.setUp == nil, snapshot.setUpMode == nil else { return .running }
        guard snapshot.isOn else { return .tactileOff }
        guard !snapshot.warnings.contains(.accessibilityMissing) else { return .accessibilityMissing }
        let connected = snapshot.touchscreens.filter(\.isConnected)
        guard !connected.isEmpty else { return .noTouchscreen }
        let settable = connected.filter(\.canBeSetUpByTouch)
        guard !settable.isEmpty else { return .noneCanBeSetUp }
        guard snapshot.displays.contains(where: { !$0.isBuiltIn }) else { return .noExternalDisplay }
        guard settable.contains(where: \.canBeSetUp) else {
            return snapshot.setUpModeRefusal.map(reason(for:)) ?? .notNow
        }
        return nil
    }

    /// The model's reason the mode can't begin (`AppSnapshot.setUpModeRefusal`), in the menu's words.
    private static func reason(for refusal: SetUpModeRefusal) -> Reason {
        switch refusal {
        case .notNow: return .notNow
        case .tactileOff: return .tactileOff
        case .accessibilityMissing: return .accessibilityMissing
        case .noDisplay: return .noExternalDisplay
        case .running: return .running
        case .noTouchscreenCanBeSetUp: return .noneCanBeSetUp
        case .noDisplayToChoose: return .noDisplayToChoose
        }
    }

    /// What Set Up Touchscreens… sends.
    static let command = AppCommand.beginSetUpMode
}

// MARK: - The controls that change a fit

/// Whether the controls that change how a touchscreen fits its display can be used: Display,
/// Orientation and Flip, Diagonal, Use Whole Glass, and Forget. While set-up mode is on or a set-up
/// runs, the model changes no pairing, orientation, alignment or diagonal of any touchscreen (a
/// set-up's Done stores those), so they are disabled for every touchscreen, the one being set up and
/// the others, and the pane says why in one line. They can be used only when `snapshot.setUp` and
/// `snapshot.setUpMode` are both nil.
struct FitControls: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// Set-up mode is on, or a set-up is running, of this touchscreen or another: the pane says
        /// so in one line.
        case setUpRunning
        /// It can't be told apart from an identical touchscreen, so it has no record: its note
        /// says why, and no line is added.
        case cannotBeToldApart
    }

    /// Why they can't be used now; nil when they can.
    var reason: Reason?
    /// Orientation and Flip, which belong to the glass on its display: only while it is paired.
    var orientationIsEnabled: Bool

    /// Display, Diagonal, Use Whole Glass and Forget.
    var isEnabled: Bool { reason == nil }

    init(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) {
        if !touchscreen.canChangeSettings {
            reason = .cannotBeToldApart
        } else if snapshot.setUp != nil || snapshot.setUpMode != nil {
            reason = .setUpRunning
        } else {
            reason = nil
        }
        orientationIsEnabled = reason == nil && touchscreen.isPaired
    }
}

// MARK: - A touchscreen that can't be told apart

extension TouchscreenSnapshot {
    /// False for a touchscreen that can't be told apart from an identical one: it has no record, so
    /// every control that would change its settings is disabled, and its note says why.
    var canChangeSettings: Bool { !notes.contains(.cannotBeToldApart) }

    /// The notes beneath the status line. `macOSIgnoresIt` is shown beside When off instead.
    var headerNotes: [TouchscreenNote] { notes.filter { $0 != .macOSIgnoresIt } }

    /// Whether "Leave it to macOS" does nothing for it: macOS ignores it by itself.
    var macOSIgnoresIt: Bool { notes.contains(.macOSIgnoresIt) }
}

// MARK: - One finger

/// The One finger pop-up: the default first, named with the mode it gives on this touchscreen
/// ("Default (Always scroll)"), then the three modes. Choosing the default sends nil, so the model
/// keeps following the touchscreen's kind; choosing a mode, even the one the default gives, stores
/// it. Beneath it, the mode in force explained.
struct OneFingerPicker: Equatable, Sendable {
    /// What is chosen: nil for the default.
    var choice: OneFingerMode?
    /// The mode the default gives on this touchscreen.
    var defaultMode: OneFingerMode
    /// The mode in force: the choice, else the default.
    var inForce: OneFingerMode
    /// Whether a finger resting long enough to drag is shown by a ring: long-press on, and the touch
    /// circles shown.
    var ringShows: Bool

    /// The default, then the three modes.
    static let options: [OneFingerMode?] = [nil] + OneFingerMode.allCases.map { $0 }

    init(choice: OneFingerMode?, defaultMode: OneFingerMode, inForce: OneFingerMode, ringShows: Bool) {
        self.choice = choice
        self.defaultMode = defaultMode
        self.inForce = inForce
        self.ringShows = ringShows
    }

    /// With no choice made, the mode in force is the default, as the model says; with one, the
    /// default is the touchscreen kind's: Always scroll where only one finger comes through (it
    /// stayed in mouse mode), Automatic elsewhere.
    init(_ touchscreen: TouchscreenSnapshot) {
        let behaviour = touchscreen.behaviour
        let oneFingerOnly = touchscreen.notes.contains(.oneFingerOnly) || !behaviour.multiFingerAvailable
        self.init(
            choice: behaviour.oneFingerChoice,
            defaultMode: behaviour.oneFingerChoice == nil ? behaviour.oneFinger : (oneFingerOnly ? .alwaysScroll : .automatic),
            inForce: behaviour.oneFinger,
            ringShows: behaviour.gestures.longPress && behaviour.showsCircles)
    }

    /// An option's title in the pop-up.
    func title(_ option: OneFingerMode?) -> String {
        option.map(Wording.oneFinger) ?? Wording.oneFingerDefault(defaultMode)
    }

    /// The line beneath the pop-up.
    var explanation: String { Wording.oneFingerExplanation(inForce, ringShows: ringShows) }

    /// What choosing `option` sends; nil when it is already chosen.
    func command(_ option: OneFingerMode?, for id: TouchscreenID) -> AppCommand? {
        option == choice ? nil : .setOneFinger(id, option)
    }
}

// MARK: - Gestures

/// One gesture switch: what it shows, and whether it can be used. On a touchscreen that reads one
/// finger, every gesture that needs more is shown off and disabled, whatever is stored; long-press
/// stays live, as the only right-click such a touchscreen has.
struct GestureRow: Equatable, Identifiable, Sendable {
    enum Kind: CaseIterable, Sendable {
        case twoFingerScroll, pinch, twoFingerTap, swipes, rotate, longPress

        var keyPath: WritableKeyPath<GestureOptions, Bool> {
            switch self {
            case .twoFingerScroll: return \.twoFingerScroll
            case .pinch: return \.pinch
            case .twoFingerTap: return \.twoFingerTap
            case .swipes: return \.swipes
            case .rotate: return \.rotate
            case .longPress: return \.longPress
            }
        }

        var needsSeveralFingers: Bool { self != .longPress }
    }

    var kind: Kind
    var isOn: Bool
    var isEnabled: Bool
    var id: Kind { kind }

    static func rows(for behaviour: BehaviourSnapshot) -> [GestureRow] {
        Kind.allCases.map { kind in
            let available = behaviour.multiFingerAvailable || !kind.needsSeveralFingers
            return GestureRow(kind: kind, isOn: available && behaviour.gestures[keyPath: kind.keyPath], isEnabled: available)
        }
    }

    /// Switching one gesture: the stored options with that one changed. On a one-finger touchscreen
    /// the multi-finger gestures stored stay as stored.
    static func command(_ kind: Kind, on: Bool, for id: TouchscreenID, behaviour: BehaviourSnapshot) -> AppCommand {
        var options = behaviour.gestures
        options[keyPath: kind.keyPath] = on
        return .setGestures(id, options)
    }
}

// MARK: - Accidental touches

enum PalmRejection {
    static func command(_ on: Bool, rules: RejectionRules, for id: TouchscreenID) -> AppCommand {
        var changed = rules
        changed.palm = on
        return .setRejection(id, changed)
    }
}

/// The edge margin's slider: whole millimetres, 0 to 10.
enum EdgeMargin {
    static let range: ClosedRange<Double> = 0...10

    /// The command for the slider at `millimetres`, rounded to a whole millimetre; nil when that is
    /// the margin in force.
    static func command(_ millimetres: Double, rules: RejectionRules, for id: TouchscreenID) -> AppCommand? {
        let whole = min(range.upperBound, max(range.lowerBound, millimetres.isFinite ? millimetres.rounded() : 0))
        guard whole != rules.edgeMarginMM else { return nil }
        var changed = rules
        changed.edgeMarginMM = whole
        return .setRejection(id, changed)
    }
}

// MARK: - Copy Settings From…

/// A touchscreen whose behaviour can be copied onto another: every other one with a record,
/// connected or remembered, in the snapshot's order.
struct CopySource: Equatable, Identifiable, Sendable {
    var id: TouchscreenID
    var title: String

    static func sources(for touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> [CopySource] {
        snapshot.touchscreens
            .filter { $0.id != touchscreen.id && $0.canChangeSettings }
            .map { CopySource(id: $0.id, title: Wording.copySource(name: $0.name, isConnected: $0.isConnected)) }
    }

    func command(to target: TouchscreenID) -> AppCommand {
        .copyBehaviour(from: id, to: target)
    }
}

// MARK: - The first-run window

/// The first-run window's question, while the model offers set-up to connected touchscreens
/// (`offerSetUpTo`), no set-up is running, and each one named could be set up (as the pane's Set Up
/// by Touch… checks it, but for the display, which is the model's to say). With Accessibility
/// missing, Settings asks first, and the window comes once access is granted. Nil: no window. Set
/// Up… begins set-up mode; Not Now declines each touchscreen named.
struct FirstRunOffer: Equatable, Sendable {
    var touchscreens: [TouchscreenID]
    var names: [String]

    init(touchscreens: [TouchscreenID], names: [String]) {
        self.touchscreens = touchscreens
        self.names = names
    }

    /// The model's offer, when the window could act on it now: the touchscreens it names that are
    /// connected and could be set up (`SetUpAvailability.offered`), in its order; nil when none is.
    init?(_ snapshot: AppSnapshot) {
        guard snapshot.setUp == nil, snapshot.setUpMode == nil else { return nil }
        let offered = snapshot.offerSetUpTo.compactMap { id in
            snapshot.touchscreens.first { $0.id == id && $0.isConnected }
        }
        .filter { SetUpAvailability.offered($0, in: snapshot) == .available }
        guard !offered.isEmpty else { return nil }
        self.init(touchscreens: offered.map(\.id), names: offered.map(\.name))
    }

    /// Set Up…: set-up mode, for every touchscreen.
    var setUpCommand: AppCommand { .beginSetUpMode }
    /// Not Now: each touchscreen named is declined, and not offered again.
    var notNowCommands: [AppCommand] { touchscreens.map { .declineSetUp($0) } }
}
