// The interface's small decisions, kept pure so they are tested without drawing anything: when
// Settings opens itself, what the sidebar selects, the status dots, what the menu lists and what a
// touchscreen's details beside it offer, when those open and close as the pointer goes, what the
// Diagonal field accepts and what committing it sends.

import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens

// MARK: - The first-run moment

/// Whether Settings opens itself shortly after launch: only when Accessibility access is missing.
/// Touchscreens that aren't set up get the small first-run window instead, once (`FirstRunOffer`),
/// and after Not Now they wait in their panes and in the menu. Nothing else interrupts the person.
public func shouldOpenSettingsAtLaunch(_ snapshot: AppSnapshot) -> Bool {
    snapshot.warnings.contains(.accessibilityMissing)
}

// MARK: - The sidebar

/// What the Settings window's sidebar can select.
enum SidebarItem: Hashable, Sendable {
    case touchscreen(TouchscreenID)
    case general

    /// The selection when Settings opens: General when Accessibility access is missing (its button
    /// is there); else the first connected touchscreen that isn't set up; else the first
    /// touchscreen; else General.
    static func initial(for snapshot: AppSnapshot) -> SidebarItem {
        if snapshot.warnings.contains(.accessibilityMissing) {
            return .general
        }
        if let waiting = snapshot.touchscreens.first(where: { $0.isConnected && $0.status == .notSetUp }) {
            return .touchscreen(waiting.id)
        }
        if let first = snapshot.touchscreens.first {
            return .touchscreen(first.id)
        }
        return .general
    }

    /// `current` while it still exists. A selection cleared by a click in the sidebar's empty space
    /// keeps `previous`, the pane shown until then. Otherwise what Settings selects on opening.
    static func resolve(_ current: SidebarItem?, previous: SidebarItem? = nil, in snapshot: AppSnapshot) -> SidebarItem {
        for item in [current, previous].compactMap({ $0 }) where item.exists(in: snapshot) {
            return item
        }
        return initial(for: snapshot)
    }

    /// The selection after the snapshot changes: the pane shown stays while it exists, so a
    /// touchscreen the person has just paired stays in view. One move is made for them: General,
    /// shown for missing Accessibility access before they chose any pane, gives way to the
    /// touchscreen that isn't set up once access is granted.
    static func following(_ current: SidebarItem?, chosenByPerson: Bool, in snapshot: AppSnapshot) -> SidebarItem {
        if !chosenByPerson, current == .general, !snapshot.warnings.contains(.accessibilityMissing),
            let waiting = snapshot.touchscreens.first(where: { $0.isConnected && $0.status == .notSetUp })
        {
            return .touchscreen(waiting.id)
        }
        return resolve(current, in: snapshot)
    }

    private func exists(in snapshot: AppSnapshot) -> Bool {
        switch self {
        case .general: return true
        case .touchscreen(let id): return snapshot.touchscreens.contains { $0.id == id }
        }
    }
}

// MARK: - Status dots

/// The coloured dot beside a touchscreen, in the sidebar and on its status line.
enum StatusIndicator: Equatable, Sendable {
    /// Paired and working: green.
    case working
    /// Connected and not set up: orange.
    case needsSetUp
    /// Paired, and its display is away: grey.
    case waiting
    /// Its touches can't be read, or it is paired and connected but Tactile only holds it: red.
    case problem
    /// Not connected, off, or left to macOS: a hollow ring.
    case inactive
    /// Being set up: its touches go to the set-up screens. The accent colour.
    case settingUp

    init(_ touchscreen: TouchscreenSnapshot) {
        guard touchscreen.isConnected else {
            self = .inactive
            return
        }
        if touchscreen.mode == .settingUp {
            self = .settingUp
            return
        }
        if touchscreen.notes.contains(.touchesCannotBeRead) {
            self = .problem
            return
        }
        switch touchscreen.status {
        // A mouse-mode panel macOS still sees is held, not driven: something stops it working.
        case .pairedWith: self = touchscreen.mode == .held ? .problem : .working
        case .notSetUp: self = .needsSetUp
        case .displayNotConnected: self = .waiting
        case .notConnected, .off, .tactileOff, .accessibilityMissing: self = .inactive
        }
    }
}

// MARK: - The Display pop-up

extension TouchscreenSnapshot {
    /// Whether it is paired with a display, connected or not.
    var isPaired: Bool { pairedDisplayName != nil }
}

/// What the Display pop-up shows as selected. A paired touchscreen never shows "Unpaired",
/// whatever its status line says.
enum DisplayPick: Hashable {
    case unpaired
    case display(UInt32)
    /// Paired with a display that isn't connected now, by its name: shown, and not choosable.
    case missing(String)

    init(_ touchscreen: TouchscreenSnapshot) {
        if let id = touchscreen.pairedDisplayID {
            self = .display(id)
        } else if let name = touchscreen.pairedDisplayName {
            self = .missing(name)
        } else {
            self = .unpaired
        }
    }

    /// The command for choosing this, or nil when it changes nothing.
    func command(for touchscreen: TouchscreenSnapshot) -> AppCommand? {
        guard self != DisplayPick(touchscreen) else { return nil }
        switch self {
        case .unpaired: return .unpair(touchscreen.id)
        case .display(let id): return .pair(touchscreen.id, displayID: id)
        case .missing: return nil
        }
    }
}

extension DisplaySnapshot {
    /// Whether it can be given a name of its own: only with a UUID, which names are stored against.
    /// A display without one would share its name with every other such display, so the model
    /// ignores renaming it, and the interface doesn't offer it.
    var canBeRenamed: Bool { !uuid.isEmpty }
}

// MARK: - The menu

extension TouchscreenSnapshot {
    /// Whether its On switch can be used: connected, and not left to macOS by Tactile as a whole
    /// (Tactile off, or no Accessibility access), where switching it would change nothing visible.
    var canBeSwitched: Bool {
        isConnected && status != .tactileOff && status != .accessibilityMissing
    }

    /// Whether its On switch is enabled, in its pane's header and in its details in the menu: it can
    /// be switched, and Tactile keeps settings for it.
    var onSwitchIsEnabled: Bool { canBeSwitched && canChangeSettings }
}

/// What the menu-bar menu lists, from a snapshot: Tactile's switch, the warnings, one row for each
/// touchscreen, Set Up Touchscreens…. It is made from the steady snapshot, which has no tester feed,
/// so nothing in it changes while a gesture goes on in the tester.
struct MenuBarContent: Equatable {
    struct Warning: Equatable {
        var warning: AppWarning
        var title: String
        var detail: String
        var action: WarningAction?
    }

    /// A touchscreen's row: its dot, its name, beside it its display's name or its state, and a
    /// chevron. The pointer resting on it, or choosing it, opens its details beside the menu
    /// (`MenuTouchscreenDetails`), where its controls are.
    struct Touchscreen: Equatable, Identifiable {
        var id: TouchscreenID
        var name: String
        /// The dot, as the sidebar and the pane's status line have it.
        var indicator: StatusIndicator
        /// Beside the name: its display's name while it works with one; else its state
        /// (`Wording.menuRowDetail`).
        var detail: String
        /// Greyed, as the menu has always greyed a touchscreen whose switch can't be used: not
        /// connected, left to macOS while Tactile is off or lacks Accessibility access, or one Tactile
        /// keeps no settings for.
        var isDimmed: Bool
        var details: MenuTouchscreenDetails
    }

    var isOn: Bool
    var warnings: [Warning]
    /// Connected first, then remembered, as the snapshot orders them.
    var touchscreens: [Touchscreen]
    /// Set Up Touchscreens…: whether set-up mode could begin now, and why not.
    var setUp: SetUpModeAvailability

    init(_ snapshot: AppSnapshot) {
        isOn = snapshot.isOn
        warnings = snapshot.warnings.map {
            Warning(warning: $0, title: Wording.warningTitle($0), detail: Wording.warningDetail($0),
                    action: Wording.warningAction($0))
        }
        touchscreens = snapshot.touchscreens.map { touchscreen in
            Touchscreen(
                id: touchscreen.id, name: touchscreen.name, indicator: StatusIndicator(touchscreen),
                detail: Wording.menuRowDetail(for: touchscreen), isDimmed: !touchscreen.onSwitchIsEnabled,
                details: MenuTouchscreenDetails(touchscreen, in: snapshot))
        }
        setUp = SetUpModeAvailability(snapshot)
    }
}

/// A touchscreen's details, beside the menu while its row is chosen: its name and a line that sums
/// it up; for one Tactile can use, a few quick controls and the ways to its tester, its set-up and
/// its pane; for one it can't, why, and its pane. Every control is the pane's own: the pane's rule
/// enables it, the pane's reason says why not, and it sends the pane's command.
struct MenuTouchscreenDetails: Equatable {
    /// Why a connected touchscreen can't be used: nothing in its details would work, so they say why
    /// and offer its pane.
    enum Unusable: Equatable, Sendable, CaseIterable {
        /// It can't be told apart from an identical touchscreen: Tactile keeps no settings for it,
        /// and drives it in no way the menu could change.
        case cannotBeToldApart
        case touchesCannotBeRead
        /// In mouse mode, and macOS still sees it: Tactile holds it, and doesn't drive it.
        case macOSAlsoHandlesIt

        /// Nil for a touchscreen that can be used, and for one that isn't connected.
        init?(_ touchscreen: TouchscreenSnapshot) {
            guard touchscreen.isConnected else { return nil }
            if !touchscreen.canChangeSettings {
                self = .cannotBeToldApart
            } else if touchscreen.notes.contains(.touchesCannotBeRead) {
                self = .touchesCannotBeRead
            } else if touchscreen.macOSAlsoHandlesIt {
                self = .macOSAlsoHandlesIt
            } else {
                return nil
            }
        }
    }

    /// A switch: where it stands, and whether it can be used.
    struct Switch: Equatable {
        var isOn: Bool
        var isEnabled: Bool
    }

    /// Calibrate Corners… and Test; for a touchscreen that isn't set up, Set Up Touchscreens… in
    /// their place.
    enum SetUp: Equatable {
        /// On its own display: the pane's Alignment buttons (`SetUpAvailability.onItsDisplay`).
        case calibrateAndTest(SetUpAvailability)
        /// Set-up mode: the pane's Set Up by Touch… (`SetUpAvailability.full`).
        case setUpTouchscreens(SetUpAvailability)
    }

    /// The controls of a touchscreen Tactile can use.
    struct Controls: Equatable {
        /// On: the pane's header switch.
        var on: Switch
        /// One finger: the pane's pop-up, the default first.
        var oneFinger: OneFingerPicker
        /// One finger and Show touches can be used, as the pane's Behaviour group.
        var behaviourIsEnabled: Bool
        /// Show touches: the pane's Touch circles.
        var showsTouches: Bool
        /// Gesture Tester…: the pane's button.
        var gestureTester: GestureTesterAvailability
        var setUp: SetUp
    }

    var id: TouchscreenID
    var name: String
    /// Its display, its size and its state, in a line (`Wording.menuSummary`).
    var summary: String
    /// For a connected touchscreen Tactile can use; nil for one it can't, and for one that isn't
    /// connected.
    var controls: Controls?
    /// Why a connected touchscreen can't be used.
    var unusable: Unusable?

    init(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) {
        id = touchscreen.id
        name = touchscreen.name
        summary = Wording.menuSummary(for: touchscreen)
        unusable = Unusable(touchscreen)
        guard touchscreen.isConnected, unusable == nil else {
            controls = nil
            return
        }
        // Set Up by Touch… is the pane's one thing to do for a touchscreen that isn't set up, as here.
        let notSetUp = touchscreen.status == .notSetUp && touchscreen.mode != .settingUp
        controls = Controls(
            on: Switch(isOn: touchscreen.isOn, isEnabled: touchscreen.onSwitchIsEnabled),
            oneFinger: OneFingerPicker(touchscreen),
            behaviourIsEnabled: touchscreen.canChangeSettings,
            showsTouches: touchscreen.behaviour.showsCircles,
            gestureTester: .of(touchscreen, in: snapshot),
            setUp: notSetUp
                ? .setUpTouchscreens(.full(touchscreen, in: snapshot))
                : .calibrateAndTest(.onItsDisplay(touchscreen, in: snapshot)))
    }

    /// Settings for <name>…: its pane.
    var pane: SidebarItem { .touchscreen(id) }

    // MARK: What each control sends: the pane's command

    /// On, switched to `on`.
    func onCommand(_ on: Bool) -> AppCommand { .setTouchscreenOn(id, on) }

    /// One finger, `option` chosen (nil: the default); nil when it is chosen already.
    func oneFingerCommand(_ option: OneFingerMode?) -> AppCommand? {
        controls?.oneFinger.command(option, for: id)
    }

    /// Show touches, switched to `on`.
    func showTouchesCommand(_ on: Bool) -> AppCommand { .setShowsCircles(id, on) }

    var calibrateCommand: AppCommand { .beginSetUp(id, .calibrate) }
    var testCommand: AppCommand { .beginSetUp(id, .test) }
    /// Set Up Touchscreens…: set-up mode, for every touchscreen.
    static let setUpCommand = AppCommand.beginSetUpMode
}

/// Which touchscreen's details are beside the menu. Choosing a row (a click, a tap, Return) shows its
/// details: opens them, moves them there from another row, or keeps them up when they are its. It
/// never closes them: a touch moves the pointer onto a row and clicks it at once, and must not open
/// them on the way (`MenuDetailsHover`) and close them with the click. The pointer resting on a row
/// shows them too; the pointer staying on another item, Esc, a click elsewhere, or the menu closing
/// closes them.
struct MenuDetailsPresenter: Equatable {
    enum Action: Equatable {
        case show(TouchscreenID)
        case close
    }

    private(set) var shown: TouchscreenID?

    mutating func chosen(_ id: TouchscreenID) -> Action {
        shown = id
        return .show(id)
    }

    mutating func closed() {
        shown = nil
    }

    /// The menu again: details for a touchscreen no longer in it close.
    mutating func follow(_ content: MenuBarContent) -> Action? {
        guard let shown, !content.touchscreens.contains(where: { $0.id == shown }) else { return nil }
        self.shown = nil
        return .close
    }
}

/// What a key or a click does to the details beside the menu, decided as it comes in and before it
/// goes on. A click on any touchscreen's row is the row's: nothing changes as the button goes down,
/// and the row's own action shows the details there, moving them to it or keeping them up when they
/// are its (`MenuDetailsPresenter.chosen`), in one step. A click anywhere else in the menu closes
/// them and goes on to what it was for. Esc in the menu or the details closes them and goes no further, so a
/// second Esc closes the menu. Anything else is left alone: a click in the details, or in a pop-up
/// menu opened from them, other keys, other windows.
enum MenuDetailsWatch {
    /// An event as the watch reads it: only what its kind has. A mouse event has no key code, and
    /// asking one for it raises; AppKit then drops the event.
    enum Event: Equatable, Sendable {
        /// A key, in the window it was pressed in.
        case key(code: UInt16, window: Int)
        /// A mouse button pressed, where, in the coordinates of the window it was pressed in.
        case mouseDown(at: CGPoint, window: Int)
        case other
    }

    enum Response: Equatable {
        /// Nothing changes; the event goes on.
        case none
        /// A touchscreen's row: nothing changes before it, and the event goes on to the row.
        case row(TouchscreenID)
        /// The details close, and the event goes on to what it was for.
        case close
        /// The details close, and the event goes no further.
        case closeAndStop
    }

    /// A touchscreen's row in the menu, its frame in the menu window's coordinates (in the screen's,
    /// for `MenuDetailsHover`).
    struct Row: Equatable {
        var id: TouchscreenID
        var frame: CGRect
    }

    /// Esc's key code.
    static let escape: UInt16 = 53

    /// `menu` and `details` are the windows' numbers; `rows` are the menu's touchscreen rows, in the
    /// menu window's coordinates; `shown` is the touchscreen whose details are up.
    static func response(to event: Event, menu: Int, details: Int?, rows: [Row], shown: TouchscreenID?) -> Response {
        switch event {
        case .key(let code, let window):
            guard code == escape, shown != nil, window == menu || window == details else { return .none }
            return .closeAndStop
        case .mouseDown(let point, let window):
            guard window == menu else { return .none }
            if let row = rows.first(where: { $0.frame.contains(point) }) {
                return .row(row.id)
            }
            return shown == nil ? .none : .close
        case .other:
            return .none
        }
    }
}

/// When a touchscreen's details open, move and close as the pointer goes, as a submenu does in a
/// native menu (keys and clicks are `MenuDetailsWatch`'s).
///
/// The pointer resting on a touchscreen's row for `openDelay` opens its details, or moves them there
/// from another row's. Leaving the row whose details are up changes nothing at once, so the pointer
/// can get to them: on another row they move there after `openDelay`; on another item in the menu
/// (Settings…, the Tactile switch, a separator, the margin) they close after `grace`. While the
/// pointer heads for the details, though (each move goes into the triangle from where it began to the
/// ends of their edge facing it), nothing moves or closes until `grace` after its last move that way,
/// so it can cross other rows and the menu's margin on its way to them. The pointer in the details,
/// back on their row, or away from both windows (empty screen, the menu bar) keeps them up, and drops
/// whatever was waiting.
///
/// Pure, on the caller's clock: told where the pointer is and when, it answers what to do now, and
/// when to look again (`nextLook`, then `tick`). Points and frames are in screen coordinates.
struct MenuDetailsHover: Equatable {
    /// Where the pointer is.
    enum Place: Equatable {
        /// On a touchscreen's row.
        case row(TouchscreenID)
        /// In the details' window.
        case details
        /// In the menu, on none of the touchscreens' rows: another item, a separator, the margin.
        case menu
        /// In neither window: empty screen, the menu bar, another app's window.
        case away
    }

    /// A decision waiting for its time.
    struct Pending: Equatable {
        var action: MenuDetailsPresenter.Action
        var due: TimeInterval
    }

    /// How long the pointer rests on a row before its details open or move there. About what a
    /// native menu waits before it opens a submenu: too short to be felt as a wait, long enough that
    /// a row passed over on the way somewhere else opens nothing.
    static let openDelay: TimeInterval = 0.12
    /// How long the pointer can be on another item in the menu, or stopped after heading for the
    /// details, before they close or move. Long enough to get out of the row and across the menu's
    /// margin to them at an easy pace, or to pause on the way; short enough that their closing, or
    /// following the row the pointer stopped on, doesn't feel late. Native menus wait about as long.
    static let grace: TimeInterval = 0.4
    /// How far the pointer moves before which way it goes is judged, in points. A smaller move is a
    /// hand's wobble, whose direction says nothing: one point sideways would look like heading
    /// straight for the details.
    static let step: CGFloat = 3

    private(set) var place: Place = .away
    private(set) var pending: Pending?
    /// Where the pointer was when which way it goes was last judged.
    private var judgedFrom: CGPoint?
    /// Until when nothing moves or closes: `grace` after the pointer last moved toward the details.
    private var headingUntil: TimeInterval = -.infinity

    /// When to look again (`tick`): when the decision waiting is due. Nil when nothing waits.
    var nextLook: TimeInterval? { pending?.due }

    /// Where `point` is: in the details (over anything else), on a touchscreen's row, elsewhere in
    /// the menu, or in neither window. `details` is their window's frame while they are up; `menu`
    /// the menu's content.
    static func place(of point: CGPoint, details: CGRect?, rows: [MenuDetailsWatch.Row], menu: CGRect?) -> Place {
        if let details, details.contains(point) {
            return .details
        }
        if let row = rows.first(where: { $0.frame.contains(point) }) {
            return .row(row.id)
        }
        if let menu, menu.contains(point) {
            return .menu
        }
        return .away
    }

    /// The pointer is at `point`, in `place`, at `time`: it came there, or moved there. `shown` is
    /// the touchscreen whose details are up, `details` their window's frame. A decision whose time
    /// had come is taken first and returned, and the move is judged as if it were done: the caller
    /// does it. The rest waits: nothing in the menu changes the moment the pointer moves.
    mutating func pointer(
        _ place: Place, at point: CGPoint, time: TimeInterval, shown: TouchscreenID?, details: CGRect?
    ) -> MenuDetailsPresenter.Action? {
        let due = tick(at: time, shown: shown)
        var shown = shown
        switch due {
        case .show(let id)?: shown = id
        case .close?: shown = nil
        case nil: break
        }
        judge(point, in: place, time: time, details: shown == nil ? nil : details)
        guard place != self.place else { return due }
        self.place = place
        switch place {
        case .row(let id) where id != shown:
            // Opened after the delay; moved after it too, but not while the pointer heads elsewhere.
            let after = time + Self.openDelay
            pending = Pending(action: .show(id), due: shown == nil ? after : max(after, headingUntil))
        case .menu where shown != nil:
            pending = Pending(action: .close, due: max(time + Self.grace, headingUntil))
        default:
            // Their own row, the details, neither window; or, with no details up, the menu.
            pending = nil
        }
        return due
    }

    /// It is `time`: the decision waiting, if its time has come and it still changes something with
    /// `shown` up.
    mutating func tick(at time: TimeInterval, shown: TouchscreenID?) -> MenuDetailsPresenter.Action? {
        guard let pending, time >= pending.due else { return nil }
        self.pending = nil
        switch pending.action {
        case .show(let id): return id == shown ? nil : .show(id)
        case .close: return shown == nil ? nil : .close
        }
    }

    /// The details closed other than by the pointer (Esc, a click elsewhere, the menu closing):
    /// whatever was waiting goes, and they stay closed until the pointer comes onto a row again.
    mutating func cancel() {
        pending = nil
        headingUntil = -.infinity
    }

    /// Which way the pointer goes, judged once it has moved `step` from where it was last judged;
    /// toward the details puts off what waits, until `grace` after.
    private mutating func judge(_ point: CGPoint, in place: Place, time: TimeInterval, details: CGRect?) {
        guard place != .details, place != .away else {
            // Only moves over the menu are judged, from where the pointer comes back to it.
            judgedFrom = nil
            return
        }
        guard let from = judgedFrom else {
            judgedFrom = point
            return
        }
        guard hypot(point.x - from.x, point.y - from.y) >= Self.step else { return }
        judgedFrom = point
        guard let details, Self.isHeading(from: from, to: point, toward: details) else { return }
        headingUntil = time + Self.grace
        if let due = pending?.due {
            pending?.due = max(due, headingUntil)
        }
    }

    /// Whether a move from `start` to `end` heads for `details`: `end` is in the triangle from
    /// `start` to the two ends of their edge facing it. Not when `start` is level with them across,
    /// where no edge faces it, nor for no move at all.
    static func isHeading(from start: CGPoint, to end: CGPoint, toward details: CGRect) -> Bool {
        guard start != end else { return false }
        let edge: CGFloat
        if start.x < details.minX {
            edge = details.minX
        } else if start.x > details.maxX {
            edge = details.maxX
        } else {
            return false
        }
        let top = CGPoint(x: edge, y: details.maxY)
        let bottom = CGPoint(x: edge, y: details.minY)
        // Which side of each side of the triangle `end` is on: inside when on none's outer side.
        func side(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (b.x - a.x) * (end.y - a.y) - (b.y - a.y) * (end.x - a.x)
        }
        let sides = [side(start, top), side(top, bottom), side(bottom, start)]
        return !(sides.contains { $0 < 0 } && sides.contains { $0 > 0 })
    }
}

/// Where the details go: beside the menu, on the side with room, as a submenu goes (the right, else
/// the left); their top level with the row's top, less `inset`, so their first line sits level with
/// the row's; kept on the screen. All in screen coordinates, whose y grows upwards.
enum MenuDetailsPlacement {
    /// Between the menu and the details.
    static let gap: CGFloat = 4
    /// The details' own top padding, above their first line.
    static let inset: CGFloat = 6

    static func frame(size: CGSize, row: CGRect, menu: CGRect, screen: CGRect) -> CGRect {
        var x = menu.maxX + gap
        if x + size.width > screen.maxX {
            x = max(screen.minX, menu.minX - gap - size.width)
        }
        var y = row.maxY + inset - size.height
        y = min(y, screen.maxY - size.height)
        y = max(y, screen.minY)
        return CGRect(origin: CGPoint(x: x, y: y), size: size).integral
    }
}

// MARK: - Names typed in

/// What typing a name sends: trimmed; blank goes back to the name the thing has of its own; an
/// unchanged name sends nothing.
enum NameEntry {
    /// A touchscreen's name. Typing the device's own name clears the custom one.
    static func touchscreen(_ text: String, current: String, deviceName: String, id: TouchscreenID) -> AppCommand? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == current || (name.isEmpty && current == deviceName) {
            return nil
        }
        return .rename(id, to: name.isEmpty || name == deviceName ? nil : name)
    }

    /// A display's name. A display without a UUID can't be named (see `canBeRenamed`).
    static func display(_ text: String, current: String, uuid: String) -> AppCommand? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uuid.isEmpty, name != current else { return nil }
        return .renameDisplay(uuid: uuid, to: name.isEmpty ? nil : name)
    }
}

// MARK: - The Diagonal field

/// What the Diagonal field accepts: empty for the size the display reports, or a diagonal in inches
/// from 3 to 200, with a decimal point or comma, and an inch mark or "in" after it if the person
/// types one.
enum DiagonalEntry: Equatable {
    case asReported
    case inches(Double)
    case invalid

    static let range = SurfaceSize.plausibleDiagonals

    static func parse(_ text: String) -> DiagonalEntry {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for suffix in ["inches", "inch", "in", "\u{2033}", "\""] where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if trimmed.isEmpty {
            return .asReported
        }
        let number = trimmed.replacingOccurrences(of: ",", with: ".")
        guard number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), let value = Double(number),
            value.isFinite, range.contains(value)
        else { return .invalid }
        return .inches(value)
    }

    /// The field's text for an override: up to two decimals, trailing zeros dropped; empty for none.
    static func text(for inches: Double?) -> String {
        guard let inches, inches.isFinite else { return "" }
        let hundredths = (inches * 100).rounded() / 100
        var text = String(format: "%.2f", hundredths)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The command for what was typed, or nil when it changes nothing or makes no sense (the
    /// field then goes back to the value in force).
    static func command(for text: String, current: Double?, id: TouchscreenID) -> AppCommand? {
        switch parse(text) {
        case .asReported:
            return current == nil ? nil : .setDiagonal(id, inches: nil)
        case .inches(let value):
            return value == current ? nil : .setDiagonal(id, inches: value)
        case .invalid:
            return nil
        }
    }
}

/// The Diagonal field: what it shows, and what committing it sends. The pane keeps it, so that a
/// set-up begun from the pane can commit a diagonal being typed first.
struct DiagonalField: Equatable {
    /// What the field shows: the diagonal in force, or what is being typed.
    var text = ""

    /// Shows `inches`, the diagonal in force, in place of anything typed.
    mutating func show(_ inches: Double?) {
        text = DiagonalEntry.text(for: inches)
    }

    /// Commits what is typed (Return, or leaving the field): sends the command for it, if there is
    /// one, then shows the diagonal in force as the model has it once it has answered, read through
    /// `inForce`. So a diagonal the model refused (a set-up was running) gives way to the one in
    /// force, rather than stay in the field as if it were set. A field that shows the diagonal in
    /// force sends nothing, though the field shows it to two decimals and it may have more. False
    /// when what was typed isn't a diagonal: nothing is sent, and the field beeps.
    @MainActor
    mutating func commit(for id: TouchscreenID, inForce: () -> Double?, perform: PerformCommand) -> Bool {
        let current = inForce()
        if text != DiagonalEntry.text(for: current),
            let command = DiagonalEntry.command(for: text, current: current, id: id)
        {
            perform(command)
        }
        let isDiagonal = DiagonalEntry.parse(text) != .invalid
        show(inForce())
        return isDiagonal
    }

    /// Sends `command` from the pane of touchscreen `id`. A set-up begun there (set-up mode, a
    /// calibration or a test) first commits a diagonal being typed, while the model still takes it:
    /// the person typed it for this touchscreen, and a set-up's size step starts from the diagonal
    /// in force. Left to the field's own commit, it would come when the field loses focus, after the
    /// set-up began, and be refused. Any other command leaves what is typed as it is. False when
    /// what was typed isn't a diagonal (the field beeps; the command is sent all the same).
    @MainActor
    mutating func send(_ command: AppCommand, for id: TouchscreenID, inForce: () -> Double?, perform: PerformCommand) -> Bool {
        var isDiagonal = true
        switch command {
        case .beginSetUp, .beginSetUpMode:
            isDiagonal = commit(for: id, inForce: inForce, perform: perform)
        default:
            break
        }
        perform(command)
        return isDiagonal
    }
}

// MARK: - General: Launch at login

/// The Launch at login row, from what macOS says. Registered and waiting for the person's approval
/// counts as on, with the way to approve it; outside the Applications folder the switch can't be
/// used, so nothing is ever registered from a build folder; a refusal can be tried again.
struct LaunchAtLoginRow: Equatable, Sendable {
    var isOn: Bool
    var isEnabled: Bool
    /// The line beneath the switch, when there is something to say.
    var note: String?
    /// Whether Open Login Items Settings… is beside the line.
    var offersLoginItemsSettings: Bool

    init(isOn: Bool, isEnabled: Bool, note: String?, offersLoginItemsSettings: Bool) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.note = note
        self.offersLoginItemsSettings = offersLoginItemsSettings
    }

    init(_ state: LaunchAtLogin) {
        self.init(
            isOn: state == .on || state == .needsApproval, isEnabled: state != .notInstalled,
            note: Wording.launchAtLoginNote(state), offersLoginItemsSettings: state == .needsApproval)
    }

    static func command(_ on: Bool) -> AppCommand { .setLaunchAtLogin(on) }
    static let openSettingsCommand = AppCommand.openLoginItemsSettings

    /// What a click on the switch sends: the other position from the one shown; nothing while it
    /// is disabled.
    var toggleCommand: AppCommand? {
        isEnabled ? Self.command(!isOn) : nil
    }
}

// MARK: - General: Swipes follow the fingers

/// The experimental switch. Where this Mac can't follow swipes, it is shown off and disabled, with
/// why, whatever is stored: the shortcuts are used there, as with the gestures a one-finger
/// touchscreen can't make.
struct FollowedSwipesRow: Equatable, Sendable {
    var isOn: Bool
    var isEnabled: Bool
    var reason: String?

    init(isOn: Bool, isEnabled: Bool, reason: String?) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.reason = reason
    }

    init(_ snapshot: AppSnapshot) {
        self.init(
            isOn: snapshot.canFollowSwipes && snapshot.swipesFollowFingers, isEnabled: snapshot.canFollowSwipes,
            reason: snapshot.canFollowSwipes ? nil : Wording.swipesFollowFingersUnavailable)
    }

    static func command(_ on: Bool) -> AppCommand { .setSwipesFollowFingers(on) }

    /// What a click on the switch sends: the other position from the one shown; nothing while it
    /// is disabled.
    var toggleCommand: AppCommand? {
        isEnabled ? Self.command(!isOn) : nil
    }
}
