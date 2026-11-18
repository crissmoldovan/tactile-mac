// The words of the gesture tester: its item in the menu and the pane, its window's three parts, and
// the names of what Tactile saw. Sentence case, except the buttons and the window's title.

import Foundation
import TactileGestures

extension Wording {

    // MARK: - Gesture Tester… in the menu and the pane

    public static let gestureTester = "Gesture Tester…"
    /// The pane's label beside the button, and what the tester is for beneath it.
    public static let gestureTesterLabel = "Gesture tester"
    public static let gestureTesterExplanation =
        "Try every gesture on real controls, on this touchscreen’s own display, and see what Tactile recognised."

    /// Why Gesture Tester… can't be used now: beneath the button in the pane and the item in a
    /// touchscreen's details beside the menu, and their help.
    static func gestureTesterUnavailable(_ reason: GestureTesterAvailability.Reason) -> String {
        switch reason {
        case .notConnected: return "It isn’t connected."
        case .setUpRunning: return "A set-up is running. Finish it first."
        case .tactileOff: return "Turn Tactile on to try its gestures."
        case .accessibilityMissing: return "Tactile needs Accessibility access to drive it."
        case .cannotBeToldApart: return "It can’t be told apart from an identical touchscreen, so Tactile doesn’t drive it."
        case .off: return "Turn it on to try its gestures."
        case .notSetUp: return "Set it up first."
        case .displayNotConnected: return "Its display isn’t connected."
        case .touchesCannotBeRead: return "Its touches can’t be read."
        case .macOSAlsoHandlesIt: return "macOS is also handling this touchscreen, so Tactile doesn’t drive it."
        case .notDriving: return "Tactile isn’t driving it now."
        }
    }

    // MARK: - The window

    /// The window's title: "Gesture Tester — ILITEK-TP".
    public static func gestureTesterWindowTitle(name: String) -> String { "Gesture Tester \u{2014} \(name)" }
    public static let gestureTesterHeading = "Gesture Tester"

    /// Beneath the heading: "ILITEK-TP on HDMI".
    public static func gestureTesterSubheading(name: String, displayName: String?) -> String {
        guard let displayName, !displayName.isEmpty else { return name }
        return "\(name) on \(displayName)"
    }

    /// What kind of touchscreen it is.
    public static func gestureTesterKind(multiTouch: Bool) -> String {
        multiTouch ? "Full touch" : "One finger only"
    }

    public static func gestureTesterKindExplanation(multiTouch: Bool) -> String {
        multiTouch
            ? "Every gesture can be made on it."
            : "It stayed in mouse mode, so macOS passes on one finger. The gestures that need more are listed, and can’t happen here."
    }

    public static let gestureTesterDrivesForReal =
        "Tactile drives this touchscreen as usual, so what you do here happens for real."
    public static let gestureTesterEscCloses = "Esc closes the tester."

    // MARK: - What this touchscreen can do

    public static let gestureTesterCanDo = "What this touchscreen can do"

    static func gestureTesterRow(_ kind: GestureTesterRow.Kind, dragNeedsHold: Bool = false) -> String {
        switch kind {
        case .tap: return "Tap"
        case .doubleTap: return "Double tap"
        case .tripleTap: return "Triple tap"
        case .drag: return dragNeedsHold ? "Hold, then drag" : "Drag"
        case .oneFinger: return "One finger moving"
        case .longPress: return "Long press: right-click"
        case .twoFingerScroll: return "Two-finger scroll and flick"
        case .pinch: return "Pinch to zoom"
        case .rotate: return "Rotate"
        case .twoFingerTap: return "Two-finger tap: right-click"
        case .threeFingerSwipes: return "Three-finger swipes"
        case .fourFingerSwipes: return "Four-finger swipes"
        case .followedSwipes: return "Swipes that follow the fingers"
        case .rejection: return "Palm and edge"
        }
    }

    /// A row's title as shown: "Hold, then drag" while one finger scrolls; the edge alone where a palm
    /// can't be told from a finger.
    static func gestureTesterRowTitle(_ row: GestureTesterRow) -> String {
        if case .edgeOnly = row.state { return "Touches at the edge" }
        return gestureTesterRow(row.kind, dragNeedsHold: row.dragNeedsHold)
    }

    /// A row's how-to as shown. Palm and edge says what this touchscreen can recognise, in the pane's
    /// words (`palmExplanation`), then the edge margin; on a touchscreen that gives one finger, the
    /// edge alone.
    static func gestureTesterRowHow(_ row: GestureTesterRow, behaviour: BehaviourSnapshot) -> String {
        guard row.kind == .rejection else {
            return gestureTesterHow(row.kind, oneFinger: behaviour.oneFinger, dragNeedsHold: row.dragNeedsHold)
        }
        if case .edgeOnly(let millimetres) = row.state {
            return millimetres > 0
                ? "Touches that start within \(edgeMarginValue(millimetres)) of an edge are ignored."
                : "Off. Its margin is under Accidental touches in Settings."
        }
        return "\(palmExplanation(reportsPalms: behaviour.reportsPalms)) \(gestureTesterEdge(behaviour.rejection.edgeMarginMM))."
    }

    /// How to make it, in a few words. The one-finger row says what one finger does in the mode in
    /// force.
    static func gestureTesterHow(_ kind: GestureTesterRow.Kind, oneFinger: OneFingerMode, dragNeedsHold: Bool = false)
        -> String
    {
        switch kind {
        case .tap: return "Touch and lift."
        case .doubleTap: return "Tap twice, quickly, in one place."
        case .tripleTap: return "Tap three times, quickly."
        case .drag: return dragNeedsHold ? "Rest a finger until the ring fills, then move it." : "Touch, move, lift."
        case .oneFinger:
            switch oneFinger {
            case .automatic: return "Scrolls lists and text; drags the rest."
            case .alwaysScroll: return "Scrolls, as on a phone. Hold first to drag."
            case .alwaysDrag: return "Drags, as a mouse would."
            }
        case .longPress: return "Rest a finger until the ring fills, then lift it."
        case .twoFingerScroll: return "Move two fingers together; flick to glide."
        case .pinch: return "Move two fingers apart, or together."
        case .rotate: return "Turn two fingers about each other."
        case .twoFingerTap: return "Tap with two fingers at once."
        case .threeFingerSwipes: return "← → Desktops · ↑ Mission Control · ↓ App Exposé."
        case .fourFingerSwipes: return "The same as three fingers."
        case .followedSwipes: return "← →: the Desktop slides with your fingers."
        case .rejection: return "Rest a palm, or start at the very edge: ignored."
        }
    }

    /// A row's state, where it is words rather than a switch.
    static func gestureTesterState(_ state: GestureTesterRow.State) -> String? {
        switch state {
        case .always: return "Always on"
        case .needsMoreThanOneFinger: return "Needs more than one finger"
        case .notOnThisMac: return "Not on this Mac"
        case .needsSwipes: return "Needs swipes on"
        case .edgeOnly(let millimetres): return edgeMarginValue(millimetres)
        case .on, .off, .oneFinger: return nil
        }
    }

    /// The palm row's edge margin: "Edge: 4 mm", "Edge: off".
    public static func gestureTesterEdge(_ millimetres: Double) -> String {
        "Edge: \(edgeMarginValue(millimetres).lowercased())"
    }

    /// Beside a row's tick: how many it saw. For VoiceOver, the same in words.
    public static func gestureTesterSeen(_ count: Int) -> String {
        switch count {
        case 0: return "Not seen yet"
        case 1: return "Seen once"
        default: return "Seen \(count) times"
        }
    }

    // MARK: - Practice

    public static let gestureTesterPractice = "Practice"
    /// Beneath "Practice": with one finger set to scroll, dragging starts with a hold.
    public static func gestureTesterPracticeHint(oneFinger: OneFingerMode) -> String {
        switch oneFinger {
        case .alwaysScroll: return "Real controls. One finger scrolls: hold until the ring fills, then drag or select."
        case .automatic: return "Real controls. One finger scrolls lists and text, and drags the rest; hold first to drag anywhere."
        case .alwaysDrag: return "Real controls. One finger drags here; scroll with the scroll bars."
        }
    }

    public static let practiceTapTitle = "Tap"
    public static let practiceTapButton = "Tap Me"
    public static func practiceTapped(_ count: Int) -> String {
        switch count {
        case 0: return "Not tapped yet"
        case 1: return "Tapped once"
        default: return "Tapped \(count) times"
        }
    }
    /// Inside the click pad: it only shows what it received.
    public static let practiceClickPad = "Tap, double-tap or triple-tap here. It shows the click count macOS received."
    /// What the click pad shows: the click count macOS delivered with the last press.
    public static func practiceClickCount(_ count: Int) -> String {
        switch count {
        case ...0: return "No tap yet"
        case 1: return "Single click"
        case 2: return "Double click"
        case 3: return "Triple click"
        default: return "\(count) clicks"
        }
    }

    public static let practiceTextTitle = "Text"
    /// What to do in the text: a text area scrolls under one finger unless one finger drags, so
    /// selecting by dragging starts with a hold.
    public static func practiceTextHint(oneFinger: OneFingerMode) -> String {
        oneFinger == .alwaysDrag
            ? "Double-tap a word, triple-tap a paragraph, or drag across to select."
            : "Double-tap a word, triple-tap a paragraph. To select by dragging, hold until the ring fills, then drag."
    }
    public static let practiceText = """
        Tactile

        Double-tap any word of this sentence.

        Triple-tap this paragraph to select all of it. Tactile turns touches into the clicks, drags and scrolls a Mac expects.
        """
    public static func practiceSelection(_ selected: String) -> String {
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Nothing selected" }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        return words == 1 ? "Selected: “\(trimmed)”" : "Selected: \(words) words"
    }

    public static let practiceCardsTitle = "Drag"
    public static let practiceCardsHint = "Drag the cards around."
    public static let practiceCardsHintHold = "Rest a finger on a card until the ring fills, then drag it."

    public static let practiceScrollTitle = "Scroll and flick"
    public static let practiceScrollHint = "The list up and down, the strip sideways. Flick to let it glide."
    public static func practiceListRow(_ number: Int) -> String { "Row \(number)" }

    public static let practicePhotoTitle = "Pinch and rotate"
    public static func practicePhotoHint(multiTouch: Bool) -> String {
        multiTouch
            ? "Pinch to zoom, turn two fingers to rotate. Double-tap to put it back."
            : "Pinch and rotate need more than one finger."
    }
    /// Beneath the photo: "Zoom 1.4× · turned 30°".
    public static func practicePhotoState(scale: Double, degrees: Double) -> String {
        let zoom = (scale * 10).rounded() / 10
        let turned = Int(degrees.rounded())
        let zoomText = zoom == zoom.rounded() ? String(format: "%.0f", zoom) : String(format: "%.1f", zoom)
        return "Zoom \(zoomText)× · turned \(turned)°"
    }

    public static let practiceRightClickTitle = "Right-click"
    public static func practiceRightClickHint(multiTouch: Bool) -> String {
        multiTouch ? "Long press here, or tap with two fingers: a menu opens." : "Long press here: a menu opens."
    }
    public static let practiceRightClickTarget = "Right-click here"
    public static let practiceMenuItems = ["Choose Me", "Or Me", "Or This One"]
    public static func practiceMenuChosen(_ item: String?) -> String {
        guard let item else { return "Nothing chosen yet" }
        return "Chose “\(item)”"
    }

    public static let practiceControlsTitle = "Controls"
    public static let practiceControlsHint = "A slider, a checkbox and a pop-up menu."
    public static let practiceSlider = "Slider"
    public static let practiceCheckbox = "Check me"
    public static let practicePopUp = "Fruit"
    public static let practiceFruits = ["Apple", "Pear", "Plum", "Quince"]

    public static let practiceSwipesTitle = "Swipes"
    public static let practiceSwipesHint = "Three or four fingers: left, right, up or down."
    public static let practiceLetSwipesThrough = "Let swipes through"
    public static func practiceSwipesState(performsSwipes: Bool) -> String {
        performsSwipes
            ? "Let through: a swipe switches Desktops or opens Mission Control. The tester waits here."
            : "Held: each swipe shows in the feed, and nothing moves."
    }

    /// The last swipe the feed has, beneath Let swipes through.
    public static func practiceLastSwipe(_ summary: String) -> String { "Last swipe: \(summary)" }

    /// The area for accidental touches: a palm where this touchscreen reports the size of a touch; a
    /// whole hand where it doesn't; the edge on a touchscreen that gives one finger, where a resting
    /// palm is a finger. It only shows what the feed says was ignored, and says so.
    /// The palm tile's title: what this touchscreen can recognise of a touch Tactile ignores.
    static func practicePalmTitle(_ kind: PalmTileKind) -> String {
        switch kind {
        case .wholeHand: return "Whole hand"
        case .palm: return "Palm"
        case .edge: return "Edge"
        }
    }

    /// What to do on the palm tile.
    static func practicePalmHint(_ kind: PalmTileKind, edgeMarginMM: Double) -> String {
        switch kind {
        case .wholeHand: return "Lay your whole hand flat here, fingers spread, all at once."
        case .palm: return "Rest your palm here, then tap with a finger."
        case .edge:
            return edgeMarginMM > 0
                ? "Start a touch within \(edgeMarginValue(edgeMarginMM)) of an edge of the screen."
                : "Start a touch at the very edge of the screen."
        }
    }

    /// Beneath the palm tile's drawing while nothing has happened: what it recognises, with the
    /// contact filter's numbers.
    static func practicePalmRule(_ kind: PalmTileKind, edgeMarginMM: Double) -> String {
        switch kind {
        case .wholeHand: return "\(PalmTileKind.handFingers) fingers or more landing at once are ignored"
        case .palm: return "A resting palm, or a whole hand, is ignored"
        case .edge: return "Touches that start within \(edgeMarginValue(edgeMarginMM)) of an edge are ignored"
        }
    }

    /// Fingers on the glass, short of a whole hand.
    static func practiceNotAHandYet(_ fingers: Int) -> String {
        "\(fingers) \(fingers == 1 ? "finger" : "fingers"): not a whole hand yet"
    }

    /// Five fingers or more, none ignored: they didn't all land at once.
    static func practiceNotAtOnce(_ fingers: Int) -> String {
        "\(fingers) fingers, not all at once: lift, then lay the hand down in one go"
    }

    /// What Tactile ignored, beneath the palm tile's drawing: ticked for what the tile is for, a
    /// palm, a hand, the edge and a second finger on a one-finger touchscreen; anything else in the
    /// feed's words.
    static func practiceIgnored(_ ignored: PalmTileReading.Ignored) -> String {
        switch ignored {
        case .reason(.hand): return "Whole hand: ignored \u{2713}"
        case .reason(.palm): return "A palm: ignored \u{2713}"
        case .reason(.edge): return "A touch at the edge: ignored \u{2713}"
        case .reason(.beyondOneFinger): return "A second finger: ignored \u{2713}"
        case .reason(let reason): return "Ignored: \(GestureNarrator.ignored(reason))"
        case .words(let words): return "Ignored: \(words)"
        }
    }

    static let practicePalmOff = "Palm rejection is off: switch it on in the list"
    static let practiceEdgeOff = "Edge rejection is off: its margin is under Accidental touches in Settings"

    // MARK: - What Tactile saw

    public static let gestureTesterSaw = "What Tactile saw"
    public static let gestureTesterFingersNow = "Fingers on the glass"
    public static let gestureTesterClear = "Clear"
    public static let gestureTesterNothingYet = "Nothing yet. Touch the screen."

    static func recognisedGesture(_ kind: RecognisedGesture.Kind) -> String {
        switch kind {
        case .tap: return "Tap"
        case .doubleTap: return "Double tap"
        case .tripleTap: return "Triple tap"
        case .drag: return "Drag"
        case .holdThenDrag: return "Hold, then drag"
        case .scroll: return "Scroll"
        case .flick: return "Flick"
        case .pinch: return "Pinch"
        case .rotate: return "Rotate"
        case .rightClick: return "Right-click"
        case .swipe: return "Swipe"
        case .followedSwipe: return "Swipe that follows"
        case .ignored: return "Ignored"
        case .cancelled: return "Cancelled"
        }
    }

    /// "1 finger", "3 fingers"; nothing for none.
    public static func fingers(_ count: Int) -> String? {
        switch count {
        case ...0: return nil
        case 1: return "1 finger"
        default: return "\(count) fingers"
        }
    }
}
