// The gesture tester's decisions, kept pure so they are tested without drawing anything: when
// Gesture Tester… can be used and why not; where its window goes and how big; which arrangement
// suits the display's shape; which rows a touchscreen gets and in what state; how each row counts
// what Tactile saw; when the window opens, moves and closes; and what the palm tile says.

import CoreGraphics
import Foundation
import TactileGestures
import TactileScreens

// MARK: - Gesture Tester…

/// Whether the tester can be opened for a touchscreen now, and if not, why: the reason is shown
/// beneath the disabled button in the pane, and beneath the item in its details beside the menu.
///
/// One source: the model's own rule, `Resolver.gestureTesterRefusal(for:in:)`, which the model also
/// uses to open the tester and to close it. The button is enabled exactly when the model would open
/// it (the touchscreen driving, and no set-up running), and its reason is the model's refusal, worded
/// from what the touchscreen shows: a refusal for want of a display says whether it was never set up
/// or its display has gone; one for not driving says whether its touches can't be read, macOS also
/// handles it, or a set-up holds it.
enum GestureTesterAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable, CaseIterable {
        case notConnected
        /// A set-up runs, set-up mode or a Calibrate/Test flow, of this touchscreen or another.
        case setUpRunning
        case tactileOff
        case accessibilityMissing
        /// It can't be told apart from an identical touchscreen: it has no record.
        case cannotBeToldApart
        /// Its own switch is off.
        case off
        /// It isn't paired with a display.
        case notSetUp
        /// Its display isn't connected now.
        case displayNotConnected
        case touchesCannotBeRead
        /// In mouse mode, and macOS still sees it: Tactile holds it.
        case macOSAlsoHandlesIt
        /// Connected, paired, on, and still not driving: locked, asleep, the displays settling, or
        /// anything else that holds it.
        case notDriving

        /// The model's refusal, in the words the touchscreen calls for.
        init(_ refusal: GestureTesterRefusal, _ touchscreen: TouchscreenSnapshot) {
            switch refusal {
            case .notConnected: self = .notConnected
            case .settingUp: self = .setUpRunning
            case .tactileOff: self = .tactileOff
            case .accessibilityMissing: self = .accessibilityMissing
            case .cannotBeToldApart: self = .cannotBeToldApart
            case .switchedOff: self = .off
            case .notPaired: self = touchscreen.isPaired ? .displayNotConnected : .notSetUp
            case .touchscreensReleased: self = .notDriving
            case .notDriving:
                if touchscreen.mode == .settingUp {
                    self = .setUpRunning
                } else if touchscreen.notes.contains(.touchesCannotBeRead) {
                    self = .touchesCannotBeRead
                } else if touchscreen.macOSAlsoHandlesIt {
                    self = .macOSAlsoHandlesIt
                } else {
                    self = .notDriving
                }
            }
        }
    }

    var reason: Reason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    /// For `touchscreen` as given, in `snapshot`.
    static func of(_ touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot) -> GestureTesterAvailability {
        var shown = snapshot
        if let index = shown.touchscreens.firstIndex(where: { $0.id == touchscreen.id }) {
            shown.touchscreens[index] = touchscreen
        } else {
            shown.touchscreens.append(touchscreen)
        }
        guard let refusal = Resolver.gestureTesterRefusal(for: touchscreen.id, in: shown) else { return .available }
        return .unavailable(Reason(refusal, touchscreen))
    }
}

// MARK: - The window

/// The tester's arrangement, chosen by the shape of the display it opens on: the strip's 1600 ×
/// 600 wants its three parts short, side by side; a 16:9 or 16:10 screen, or one standing upright,
/// has room for the regular one.
enum GestureTesterLayout: Equatable, Sendable {
    /// For a display at least twice as wide as it is tall: everything in one short band.
    case wide
    /// Room to spare: larger type and controls, the practice area in a grid of three.
    case regular

    /// How much wider than tall a display must be for the wide arrangement.
    static let wideShape: CGFloat = 2

    init(displaySize: CGSize) {
        guard displaySize.width > 0, displaySize.height > 0 else {
            self = .regular
            return
        }
        self = displaySize.width >= Self.wideShape * displaySize.height ? .wide : .regular
    }
}

/// Where the tester's window goes on its display: the part windows can use (the screen's visible
/// frame, without the menu bar and the Dock), less a margin all round that grows with the display,
/// from 8 to 32 points.
enum GestureTesterWindowFrame {
    static let marginRange: ClosedRange<CGFloat> = 8...32

    static func margin(for visible: CGRect) -> CGFloat {
        let scaled = (min(visible.width, visible.height) * 0.025).rounded()
        return min(marginRange.upperBound, max(marginRange.lowerBound, scaled))
    }

    static func frame(in visible: CGRect) -> CGRect {
        let margin = margin(for: visible)
        let frame = visible.insetBy(dx: margin, dy: margin)
        return frame.isEmpty ? visible : frame.integral
    }
}

/// The tester's type, sized so a line of text is at least `smallestLine` tall on the glass, where
/// the display's size is known, and never under a floor for each arrangement: 12-point text and
/// 13-point titles in the wide one, 14 and 17 in the regular one. A line is the type's size times
/// `lineFactor`, the system font's line height. On the strip (12.3″, 1600 × 600: 0.183 mm a point)
/// and on the 23.8″ HDMI (2560 × 1440: 0.206 mm) the floors are larger than the rule needs; on a
/// denser display the rule makes the type larger.
struct GestureTesterType: Equatable, Sendable {
    /// How-tos, hints, readouts, the feed's words.
    var body: CGFloat
    /// Row, tile and feed titles.
    var title: CGFloat

    /// The shortest a line of text may be on the glass, in millimetres.
    static let smallestLine = 2.5
    /// A line's height as a share of the type's size: the system font's, at these sizes.
    static let lineFactor = 1.2
    /// No larger than this, whatever the display.
    static let largestBody: CGFloat = 24

    static func floor(_ layout: GestureTesterLayout) -> (body: CGFloat, title: CGFloat) {
        switch layout {
        case .wide: return (12, 13)
        case .regular: return (14, 17)
        }
    }

    init(body: CGFloat, title: CGFloat) {
        self.body = body
        self.title = title
    }

    init(_ layout: GestureTesterLayout, millimetresPerPoint: Double?) {
        let floor = Self.floor(layout)
        var body = floor.body
        if let millimetresPerPoint, millimetresPerPoint.isFinite, millimetresPerPoint > 0 {
            let needed = CGFloat((Self.smallestLine / (millimetresPerPoint * Self.lineFactor)).rounded(.up))
            body = min(Self.largestBody, max(body, needed))
        }
        self.init(body: body, title: body + (floor.title - floor.body))
    }

    /// Millimetres a point on a display of `points` with a diagonal of `diagonalInches`; nil when
    /// either isn't known.
    static func millimetresPerPoint(points: CGSize, diagonalInches: Double?) -> Double? {
        guard let diagonalInches, diagonalInches.isFinite, diagonalInches > 0, points.width > 0, points.height > 0
        else { return nil }
        return diagonalInches * 25.4 / Double(hypot(points.width, points.height))
    }

    /// How tall a line of type of `size` points is on the glass, in millimetres.
    static func lineMillimetres(_ size: CGFloat, millimetresPerPoint: Double) -> Double {
        Double(size) * lineFactor * millimetresPerPoint
    }
}

// MARK: - What this touchscreen can do

/// One row of "What this touchscreen can do": a gesture, in the order a person learns them, with
/// how to do it (`Wording.testerRowHow`), what Tactile has seen of it, and its state.
struct GestureTesterRow: Equatable, Identifiable, Sendable {
    enum Kind: CaseIterable, Sendable {
        case tap, doubleTap, tripleTap
        /// Press, move, lift; "Hold, then drag" while one finger scrolls.
        case drag
        /// What one moving finger does: the one-finger setting in force, with its picker.
        case oneFinger
        /// Long press: right-click.
        case longPress
        /// Two-finger scroll, and the flick that lets it glide.
        case twoFingerScroll
        case pinch, rotate
        /// Two-finger tap: right-click.
        case twoFingerTap
        case threeFingerSwipes, fourFingerSwipes
        /// Swipes that follow the fingers: General's experimental switch.
        case followedSwipes
        /// Palm and edge rejection.
        case rejection

        /// Whether the gesture needs more than one finger on the glass.
        var needsSeveralFingers: Bool {
            switch self {
            case .twoFingerScroll, .pinch, .rotate, .twoFingerTap, .threeFingerSwipes, .fourFingerSwipes,
                .followedSwipes:
                return true
            case .tap, .doubleTap, .tripleTap, .drag, .oneFinger, .longPress, .rejection:
                return false
            }
        }

        /// The pane's gesture switch that turns it on and off, where it has one.
        var gestureSwitch: GestureRow.Kind? {
            switch self {
            case .longPress: return .longPress
            case .twoFingerScroll: return .twoFingerScroll
            case .pinch: return .pinch
            case .rotate: return .rotate
            case .twoFingerTap: return .twoFingerTap
            case .threeFingerSwipes, .fourFingerSwipes: return .swipes
            case .tap, .doubleTap, .tripleTap, .drag, .oneFinger, .followedSwipes, .rejection: return nil
            }
        }
    }

    enum State: Equatable, Sendable {
        /// Always there: no switch.
        case always
        /// With its switch.
        case on, off
        /// The one-finger setting in force, with its picker; `isDefault`: no choice is stored.
        case oneFinger(OneFingerMode, isDefault: Bool)
        /// On a touchscreen that gives one finger: shown all the same, so the person sees the whole
        /// picture.
        case needsMoreThanOneFinger
        /// Swipes that follow the fingers, on a Mac that can't follow them.
        case notOnThisMac
        /// Swipes that follow the fingers, while three- and four-finger swipes are off.
        case needsSwipes
        /// Rejection on a touchscreen that gives one finger: only the edge margin, in millimetres
        /// (0: off). A resting palm there is a finger: its mouse interface reports no size,
        /// confidence or second contact to tell one by.
        case edgeOnly(Double)
    }

    /// What a row counts in the feed: gestures of these kinds; with `fingers`, only those made with
    /// that many fingers.
    struct Match: Equatable, Sendable {
        var kinds: Set<RecognisedGesture.Kind>
        var fingers: Int?

        init(_ kinds: Set<RecognisedGesture.Kind>, fingers: Int? = nil) {
            self.kinds = kinds
            self.fingers = fingers
        }
    }

    var kind: Kind
    var state: State
    var match: Match
    /// Whether its switch or picker can be used: false for a touchscreen Tactile keeps no settings
    /// for (it can't be told apart from an identical one).
    var isEnabled: Bool
    /// Drag only: true when one finger scrolls, so a drag starts with a hold.
    var dragNeedsHold: Bool = false
    /// The lines of its how-to: none for a gesture this touchscreen can't make (the row is its title
    /// and "Needs more than one finger"), two for palm and edge on a multi-touch touchscreen, else one.
    var howLines: Int = 1
    /// The one-finger row's picker: the pane's own (`OneFingerPicker`), so that the tester offers
    /// what the pane offers, the default first, and sends what the pane sends. Nil on every other
    /// row, and when the rows are made without it.
    var oneFingerPicker: OneFingerPicker?
    var id: Kind { kind }

    /// Whether the gesture can't happen here at all: it needs more than one finger on a touchscreen
    /// that gives one, or this Mac can't follow swipes. Only such a row's how-to is drawn in the
    /// faintest grey; a row that is off, or waits on another switch or a margin, says how to have it,
    /// and that guidance is drawn as every other how-to is.
    var cannotHappenHere: Bool {
        switch state {
        case .needsMoreThanOneFinger, .notOnThisMac: return true
        case .always, .on, .off, .oneFinger, .needsSwipes, .edgeOnly: return false
        }
    }

    /// Every row for `touchscreen`, as the tester's window shows them: its settings, and its
    /// one-finger row with the pane's picker (`OneFingerPicker(touchscreen)`).
    static func rows(
        for touchscreen: TouchscreenSnapshot, multiTouch: Bool, swipesFollowFingers: Bool, canFollowSwipes: Bool
    ) -> [GestureTesterRow] {
        rows(behaviour: touchscreen.behaviour, multiTouch: multiTouch, swipesFollowFingers: swipesFollowFingers,
             canFollowSwipes: canFollowSwipes, canChangeSettings: touchscreen.canChangeSettings,
             oneFingerPicker: OneFingerPicker(touchscreen))
    }

    /// Every row, in the order a person learns them. On a touchscreen that gives one finger the
    /// multi-finger ones say "needs more than one finger", and are not hidden.
    static func rows(
        behaviour: BehaviourSnapshot, multiTouch: Bool, swipesFollowFingers: Bool, canFollowSwipes: Bool,
        canChangeSettings: Bool = true, oneFingerPicker: OneFingerPicker? = nil
    ) -> [GestureTesterRow] {
        let oneFinger = behaviour.oneFinger
        return Kind.allCases.map { kind in
            var row = GestureTesterRow(
                kind: kind, state: state(kind, behaviour: behaviour, multiTouch: multiTouch,
                                         swipesFollowFingers: swipesFollowFingers, canFollowSwipes: canFollowSwipes),
                match: match(kind, oneFinger: oneFinger), isEnabled: canChangeSettings)
            row.dragNeedsHold = kind == .drag && oneFinger == .alwaysScroll
            if kind == .oneFinger { row.oneFingerPicker = oneFingerPicker }
            if row.state == .needsMoreThanOneFinger {
                row.howLines = 0
            } else if kind == .rejection, multiTouch {
                row.howLines = 2
            }
            return row
        }
    }

    private static func state(
        _ kind: Kind, behaviour: BehaviourSnapshot, multiTouch: Bool, swipesFollowFingers: Bool, canFollowSwipes: Bool
    ) -> State {
        if kind.needsSeveralFingers, !multiTouch {
            return .needsMoreThanOneFinger
        }
        if let gestureSwitch = kind.gestureSwitch {
            return behaviour.gestures[keyPath: gestureSwitch.keyPath] ? .on : .off
        }
        switch kind {
        case .oneFinger:
            return .oneFinger(behaviour.oneFinger, isDefault: behaviour.oneFingerChoice == nil)
        case .followedSwipes:
            guard canFollowSwipes else { return .notOnThisMac }
            guard behaviour.gestures.swipes else { return .needsSwipes }
            return swipesFollowFingers ? .on : .off
        case .rejection:
            guard multiTouch else { return .edgeOnly(behaviour.rejection.edgeMarginMM) }
            return behaviour.rejection.palm ? .on : .off
        default:
            return .always
        }
    }

    private static func match(_ kind: Kind, oneFinger: OneFingerMode) -> Match {
        switch kind {
        case .tap: return Match([.tap])
        case .doubleTap: return Match([.doubleTap])
        case .tripleTap: return Match([.tripleTap])
        case .drag: return Match([.drag, .holdThenDrag])
        case .oneFinger:
            return oneFinger == .alwaysDrag ? Match([.drag], fingers: 1) : Match([.scroll, .flick], fingers: 1)
        case .longPress: return Match([.rightClick], fingers: 1)
        case .twoFingerScroll: return Match([.scroll, .flick], fingers: 2)
        case .pinch: return Match([.pinch])
        case .rotate: return Match([.rotate])
        case .twoFingerTap: return Match([.rightClick], fingers: 2)
        case .threeFingerSwipes: return Match([.swipe], fingers: 3)
        case .fourFingerSwipes: return Match([.swipe], fingers: 4)
        case .followedSwipes: return Match([.followedSwipe])
        case .rejection: return Match([.ignored])
        }
    }

    /// How many of its gestures Tactile has seen since the tester opened or was cleared. A row of
    /// whole kinds counts the model's `seen`; a row that tells a kind apart by its fingers (one- and
    /// two-finger scrolls, the two right-clicks, three- and four-finger swipes) counts the feed's
    /// entries, as the window has followed them (`GestureTally`).
    func count(seen: [GestureSeenCount], tally: GestureTally) -> Int {
        if let fingers = match.fingers {
            return tally.count(match.kinds, fingers: fingers)
        }
        return seen.filter { match.kinds.contains($0.id) }.map(\.count).reduce(0, +)
    }

    /// What switching the row sends: the pane's own command for that switch. Nil for a row with no
    /// switch.
    static func command(_ kind: Kind, on: Bool, for id: TouchscreenID, behaviour: BehaviourSnapshot) -> AppCommand? {
        if let gestureSwitch = kind.gestureSwitch {
            return GestureRow.command(gestureSwitch, on: on, for: id, behaviour: behaviour)
        }
        switch kind {
        case .followedSwipes: return FollowedSwipesRow.command(on)
        case .rejection: return PalmRejection.command(on, rules: behaviour.rejection, for: id)
        default: return nil
        }
    }
}

// MARK: - What Tactile saw

/// The feed's entries as the window has followed them since the tester opened or was cleared, by
/// their sequence number: enough to count gestures by their fingers, which `seen` doesn't. A scroll
/// updated in place is one entry. It starts again when the tester is for another touchscreen, when
/// it is cleared (nothing in `recent` or `seen`), or when the numbers start again.
struct GestureTally: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var kind: RecognisedGesture.Kind
        var fingers: Int
    }

    private(set) var touchscreen: TouchscreenID?
    private(set) var entries: [Int: Entry] = [:]

    init() {}

    mutating func follow(_ tester: GestureTesterSnapshot?) {
        guard let tester else {
            self = GestureTally()
            return
        }
        let cleared = tester.recent.isEmpty && tester.seen.isEmpty
        let restarted = tester.recent.map(\.id).max().map { newest in entries.keys.contains { $0 > newest } } ?? false
        if tester.touchscreen != touchscreen || cleared || restarted {
            self = GestureTally()
            touchscreen = tester.touchscreen
        }
        for gesture in tester.recent {
            entries[gesture.id] = Entry(kind: gesture.kind, fingers: gesture.fingers)
        }
    }

    func count(_ kinds: Set<RecognisedGesture.Kind>, fingers: Int) -> Int {
        entries.values.filter { kinds.contains($0.kind) && $0.fingers == fingers }.count
    }
}

// MARK: - The window, following the snapshot

/// When the tester's window opens, moves and closes, kept pure. It follows the snapshot's
/// `gestureTester`: opened for it on its display; closed when it goes, and opened again on the other
/// display when it is for another touchscreen or display. The person's close (the close button,
/// Esc) closes it at once and sends `closeGestureTester`; until the model has caught up, the tester
/// it still names stays closed. Gesture Tester… pressed for the tester that is up brings it forward.
struct GestureTesterPresenter: Equatable, Sendable {
    /// Which tester a window is for: the touchscreen, and the display it opens on.
    struct Shown: Equatable, Sendable {
        var touchscreen: TouchscreenID
        var displayID: UInt32
    }

    enum Action: Equatable, Sendable {
        case nothing
        case open(Shown)
        /// Close the window that is up and open one for this, on its display.
        case replace(Shown)
        /// Take the window down, saying why in the log.
        case close(String)
        /// Bring the window that is up to the front, with focus.
        case bringForward
        /// The person closed it: send `closeGestureTester`.
        case send(AppCommand)

        /// Whether the window that was up goes for good, so Tactile may stop being a regular app
        /// (`RegularAppHold`). A window replaced by another, for the other touchscreen or display,
        /// keeps the hold: the Dock icon doesn't blink, and the new window doesn't start from a
        /// menu-bar app.
        var releasesHold: Bool {
            switch self {
            case .close, .send: return true
            case .nothing, .open, .replace, .bringForward: return false
            }
        }
    }

    private(set) var shown: Shown?
    /// The tester the person closed, while the model still names it.
    private(set) var dismissed: Shown?
    /// The model's tester, as last told.
    private(set) var latest: Shown?

    init() {}

    mutating func told(_ tester: GestureTesterSnapshot?) -> Action {
        let wanted = tester.map { Shown(touchscreen: $0.touchscreen, displayID: $0.displayID) }
        latest = wanted
        guard let wanted else {
            dismissed = nil
            guard shown != nil else { return .nothing }
            shown = nil
            return .close("the tester closed")
        }
        if wanted == dismissed { return .nothing }
        dismissed = nil
        guard wanted != shown else { return .nothing }
        let before = shown
        shown = wanted
        return before == nil ? .open(wanted) : .replace(wanted)
    }

    /// The person closed the window: its close button, or Esc.
    mutating func closedByPerson() -> Action {
        guard let closed = shown else { return .nothing }
        shown = nil
        dismissed = closed
        return .send(.closeGestureTester)
    }

    /// Gesture Tester… was pressed for `touchscreen` (the open command is sent beside this). The
    /// window up for it comes forward; one the person closed while the model still names it opens
    /// again. Anything else waits for the snapshot.
    mutating func asked(toOpen touchscreen: TouchscreenID) -> Action {
        if shown?.touchscreen == touchscreen { return .bringForward }
        guard shown == nil, let latest, latest.touchscreen == touchscreen else { return .nothing }
        dismissed = nil
        shown = latest
        return .open(latest)
    }

    /// The window went without the person or the snapshot (Tactile quitting): nothing is sent.
    mutating func closedQuietly() {
        shown = nil
    }
}

// MARK: - The palm tile

/// What the practice area's palm tile is for: what this touchscreen can recognise of a touch that
/// Tactile ignores.
enum PalmTileKind: Equatable, Sendable {
    /// A multi-touch touchscreen that doesn't report how big a touch is: only a whole hand, the
    /// contact filter's five fingers or more that all land within a fifth of a second.
    case wholeHand
    /// One that reports the size of a touch, or whether it is a finger: a resting palm, and a whole
    /// hand.
    case palm
    /// One that gives one finger: only a touch that starts within the edge margin.
    case edge

    init(multiTouch: Bool, reportsPalms: Bool) {
        self = !multiTouch ? .edge : reportsPalms ? .palm : .wholeHand
    }

    /// How many fingers landing at once are a whole hand: the contact filter's own number.
    static let handFingers = GestureConstants.standard.handContactCount
}

/// What the palm tile has seen of the touch on the glass, or of the last one: the most fingers it
/// had, and what Tactile ignored of it, newest. Followed from the fingers on the glass and the
/// feed's count of ignored entries, which change only when a finger lands or lifts and when
/// something is ignored, never with each frame of a gesture.
struct PalmTileReading: Equatable, Sendable {
    /// What the tile follows, from the window's store.
    struct Inputs: Equatable, Sendable {
        var fingers: Int
        var ignored: Int
    }

    /// What Tactile ignored: the reason the narrator worded it from, where its words name one; else
    /// its words.
    enum Ignored: Equatable, Sendable {
        case reason(IgnoredBecause)
        case words(String)

        init(_ entry: RecognisedGesture) {
            if let reason = IgnoredBecause.allCases.first(where: { GestureNarrator.ignored($0) == entry.summary }) {
                self = .reason(reason)
            } else {
                self = .words(entry.summary)
            }
        }
    }

    /// The most fingers on the glass in the touch, or in the last one.
    private(set) var mostFingers = 0
    /// What was ignored in the touch, or in the last one, newest.
    private(set) var ignored: Ignored?

    /// As the tile appears: the touch under way, if any, and the newest thing the feed says was
    /// ignored, if anything was.
    init(_ inputs: Inputs = Inputs(fingers: 0, ignored: 0), newest: RecognisedGesture? = nil) {
        mostFingers = inputs.fingers
        if inputs.ignored > 0, let newest {
            ignored = Ignored(newest)
        }
    }

    /// The fingers or the ignored count changed from `old` to `new`. A touch begins when a finger
    /// lands on clear glass; the feed cleared clears what was seen. `newest` is the feed's newest
    /// ignored entry, read only when the count rose.
    mutating func follow(from old: Inputs, to new: Inputs, newest: () -> RecognisedGesture?) {
        if new.ignored < old.ignored {
            self = PalmTileReading()
        }
        if new.fingers > 0 {
            if old.fingers == 0 {
                mostFingers = new.fingers
                ignored = nil
            } else {
                mostFingers = max(mostFingers, new.fingers)
            }
        }
        if new.ignored > old.ignored, let entry = newest() {
            ignored = Ignored(entry)
        }
    }

    /// The feed's newest ignored entry.
    static func newestIgnored(in recent: [RecognisedGesture]) -> RecognisedGesture? {
        recent.first { $0.kind == .ignored }
    }
}

/// The line beneath the palm tile's drawing: that the rejection it is for is off; what Tactile
/// ignored of the touch, or the last one; for a whole hand, how far the fingers on the glass are
/// from one; else what the tile recognises.
struct PalmTileFeedback: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        /// What the tile recognises, while nothing has happened.
        case rule
        /// Fingers down, short of a whole hand.
        case notYet
        /// Something ignored.
        case ignored
        /// The rejection the tile is for is off.
        case off
    }

    var text: String
    var tone: Tone

    init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    init(_ kind: PalmTileKind, palmIsOn: Bool, edgeMarginMM: Double, fingersDown: Int, reading: PalmTileReading) {
        switch kind {
        case .edge where edgeMarginMM <= 0:
            self.init(text: Wording.practiceEdgeOff, tone: .off)
            return
        case .palm where !palmIsOn, .wholeHand where !palmIsOn:
            self.init(text: Wording.practicePalmOff, tone: .off)
            return
        default:
            break
        }
        if let ignored = reading.ignored {
            self.init(text: Wording.practiceIgnored(ignored), tone: .ignored)
            return
        }
        if kind == .wholeHand {
            // Five fingers or more, and nothing ignored: they didn't all land at once.
            let most = max(fingersDown, reading.mostFingers)
            if most >= PalmTileKind.handFingers {
                self.init(text: Wording.practiceNotAtOnce(most), tone: .notYet)
                return
            }
            if fingersDown >= 2 {
                self.init(text: Wording.practiceNotAHandYet(fingersDown), tone: .notYet)
                return
            }
        }
        self.init(text: Wording.practicePalmRule(kind, edgeMarginMM: edgeMarginMM), tone: .rule)
    }
}
