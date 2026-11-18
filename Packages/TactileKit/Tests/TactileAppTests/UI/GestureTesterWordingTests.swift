import TactileGestures
import XCTest

@testable import TactileApp

/// The gesture tester's words: its window, every row in every state, the practice area's labels,
/// and the names of what Tactile saw. Every case of every enum.
final class GestureTesterWordingTests: XCTestCase {

    func testTheWindow() {
        XCTAssertEqual(Wording.gestureTesterWindowTitle(name: "ILITEK-TP"), "Gesture Tester — ILITEK-TP")
        XCTAssertEqual(Wording.gestureTesterSubheading(name: "TouchScreen", displayName: "12.3FHD"), "TouchScreen on 12.3FHD")
        XCTAssertEqual(Wording.gestureTesterSubheading(name: "TouchScreen", displayName: nil), "TouchScreen")
        XCTAssertEqual(Wording.gestureTesterKind(multiTouch: true), "Full touch")
        XCTAssertEqual(Wording.gestureTesterKind(multiTouch: false), "One finger only")
        XCTAssertEqual(Wording.gestureTesterKindExplanation(multiTouch: true), "Every gesture can be made on it.")
        XCTAssertEqual(
            Wording.gestureTesterKindExplanation(multiTouch: false),
            "It stayed in mouse mode, so macOS passes on one finger. The gestures that need more are listed, and can’t happen here.")
        XCTAssertEqual(Wording.gestureTesterEscCloses, "Esc closes the tester.")
        XCTAssertEqual(Wording.gestureTesterLabel, "Gesture tester")
    }

    func testEveryRow() {
        let titles: [GestureTesterRow.Kind: String] = [
            .tap: "Tap", .doubleTap: "Double tap", .tripleTap: "Triple tap", .drag: "Drag",
            .oneFinger: "One finger moving", .longPress: "Long press: right-click",
            .twoFingerScroll: "Two-finger scroll and flick", .pinch: "Pinch to zoom", .rotate: "Rotate",
            .twoFingerTap: "Two-finger tap: right-click", .threeFingerSwipes: "Three-finger swipes",
            .fourFingerSwipes: "Four-finger swipes", .followedSwipes: "Swipes that follow the fingers",
            .rejection: "Palm and edge",
        ]
        for kind in GestureTesterRow.Kind.allCases {
            XCTAssertEqual(Wording.gestureTesterRow(kind), titles[kind], "\(kind)")
            for mode in OneFingerMode.allCases {
                XCTAssertFalse(Wording.gestureTesterHow(kind, oneFinger: mode).isEmpty, "\(kind)")
            }
        }
        XCTAssertEqual(Wording.gestureTesterRow(.drag, dragNeedsHold: true), "Hold, then drag")
        XCTAssertEqual(Wording.gestureTesterHow(.drag, oneFinger: .alwaysScroll, dragNeedsHold: true),
                       "Rest a finger until the ring fills, then move it.")
        XCTAssertEqual(Wording.gestureTesterHow(.oneFinger, oneFinger: .automatic), "Scrolls lists and text; drags the rest.")
        XCTAssertEqual(Wording.gestureTesterHow(.oneFinger, oneFinger: .alwaysScroll),
                       "Scrolls, as on a phone. Hold first to drag.")
        XCTAssertEqual(Wording.gestureTesterHow(.oneFinger, oneFinger: .alwaysDrag), "Drags, as a mouse would.")
        XCTAssertEqual(Wording.gestureTesterHow(.threeFingerSwipes, oneFinger: .automatic),
                       "← → Desktops · ↑ Mission Control · ↓ App Exposé.")
        XCTAssertEqual(Wording.gestureTesterState(.edgeOnly(0)), "Off")
        XCTAssertEqual(Wording.gestureTesterState(.edgeOnly(2.5)), "2.5 mm")

        XCTAssertEqual(Wording.gestureTesterState(.always), "Always on")
        XCTAssertEqual(Wording.gestureTesterState(.needsMoreThanOneFinger), "Needs more than one finger")
        XCTAssertEqual(Wording.gestureTesterState(.notOnThisMac), "Not on this Mac")
        XCTAssertEqual(Wording.gestureTesterState(.needsSwipes), "Needs swipes on")
        XCTAssertNil(Wording.gestureTesterState(.on))
        XCTAssertNil(Wording.gestureTesterState(.off))
        XCTAssertNil(Wording.gestureTesterState(.oneFinger(.automatic, isDefault: true)))
        XCTAssertEqual(Wording.gestureTesterEdge(0), "Edge: off")
        XCTAssertEqual(Wording.gestureTesterEdge(4), "Edge: 4 mm")
        XCTAssertEqual(Wording.gestureTesterSeen(0), "Not seen yet")
        XCTAssertEqual(Wording.gestureTesterSeen(1), "Seen once")
        XCTAssertEqual(Wording.gestureTesterSeen(7), "Seen 7 times")
    }

    func testThePracticeArea() {
        XCTAssertEqual(Wording.practiceTapped(0), "Not tapped yet")
        XCTAssertEqual(Wording.practiceTapped(1), "Tapped once")
        XCTAssertEqual(Wording.practiceTapped(5), "Tapped 5 times")
        XCTAssertEqual(Wording.practiceClickCount(0), "No tap yet")
        XCTAssertEqual(Wording.practiceClickCount(1), "Single click")
        XCTAssertEqual(Wording.practiceClickCount(2), "Double click")
        XCTAssertEqual(Wording.practiceClickCount(3), "Triple click")
        XCTAssertEqual(Wording.practiceClickCount(4), "4 clicks")
        XCTAssertTrue(Wording.practiceClickPad.contains("It shows the click count macOS received."),
                      "a control that only shows says so")
        XCTAssertEqual(Wording.practiceSelection(""), "Nothing selected")
        XCTAssertEqual(Wording.practiceSelection(" Tactile\n"), "Selected: “Tactile”")
        XCTAssertEqual(Wording.practiceSelection("Double-tap any word"), "Selected: 3 words")
        XCTAssertEqual(Wording.practicePhotoState(scale: 1, degrees: 0), "Zoom 1× · turned 0°")
        XCTAssertEqual(Wording.practicePhotoState(scale: 1.42, degrees: 29.6), "Zoom 1.4× · turned 30°")
        XCTAssertEqual(Wording.practicePhotoState(scale: 0.5, degrees: -45), "Zoom 0.5× · turned -45°")
        XCTAssertEqual(Wording.practiceMenuChosen(nil), "Nothing chosen yet")
        XCTAssertEqual(Wording.practiceMenuChosen("Or Me"), "Chose “Or Me”")
        XCTAssertEqual(Wording.practiceSwipesState(performsSwipes: false),
                       "Held: each swipe shows in the feed, and nothing moves.")
        XCTAssertEqual(Wording.practiceSwipesState(performsSwipes: true),
                       "Let through: a swipe switches Desktops or opens Mission Control. The tester waits here.")
        XCTAssertEqual(Wording.practiceLastSwipe("left: next Desktop"), "Last swipe: left: next Desktop")
        XCTAssertEqual(Wording.practiceLetSwipesThrough, "Let swipes through")
        for mode in OneFingerMode.allCases {
            XCTAssertTrue(Wording.gestureTesterPracticeHint(oneFinger: mode).hasPrefix("Real controls."))
        }
    }

    /// Where one finger scrolls (Always scroll, and Automatic over a text area), selecting by dragging
    /// starts with a hold; where one finger drags, a drag selects.
    func testTheTextHintFollowsWhatOneFingerDoes() {
        let hold = "Double-tap a word, triple-tap a paragraph. To select by dragging, hold until the ring fills, then drag."
        XCTAssertEqual(Wording.practiceTextHint(oneFinger: .alwaysScroll), hold)
        XCTAssertEqual(Wording.practiceTextHint(oneFinger: .automatic), hold)
        XCTAssertEqual(Wording.practiceTextHint(oneFinger: .alwaysDrag),
                       "Double-tap a word, triple-tap a paragraph, or drag across to select.")
        XCTAssertFalse(Wording.practiceText.contains("drag across"), "the sample text asks only for taps")
    }

    /// On a touchscreen that gives one finger the tiles say what needs more, as the rows do; the
    /// accidental-touch area invites only what this touchscreen can recognise.
    func testTheTilesFollowTheKindOfTouchscreen() {
        XCTAssertEqual(Wording.practicePhotoHint(multiTouch: true),
                       "Pinch to zoom, turn two fingers to rotate. Double-tap to put it back.")
        XCTAssertEqual(Wording.practicePhotoHint(multiTouch: false), "Pinch and rotate need more than one finger.")
        XCTAssertEqual(Wording.practiceRightClickHint(multiTouch: true),
                       "Long press here, or tap with two fingers: a menu opens.")
        XCTAssertEqual(Wording.practiceRightClickHint(multiTouch: false), "Long press here: a menu opens.")

        XCTAssertEqual(PalmTileKind(multiTouch: true, reportsPalms: true), .palm)
        XCTAssertEqual(PalmTileKind(multiTouch: true, reportsPalms: false), .wholeHand)
        XCTAssertEqual(PalmTileKind(multiTouch: false, reportsPalms: false), .edge)
        XCTAssertEqual(PalmTileKind(multiTouch: false, reportsPalms: true), .edge, "one finger: a palm is a finger")
        XCTAssertEqual(Wording.practicePalmTitle(.palm), "Palm")
        XCTAssertEqual(Wording.practicePalmTitle(.wholeHand), "Whole hand")
        XCTAssertEqual(Wording.practicePalmTitle(.edge), "Edge")
        XCTAssertEqual(Wording.practicePalmHint(.wholeHand, edgeMarginMM: 0),
                       "Lay your whole hand flat here, fingers spread, all at once.")
        XCTAssertEqual(Wording.practicePalmHint(.palm, edgeMarginMM: 0), "Rest your palm here, then tap with a finger.")
        XCTAssertEqual(Wording.practicePalmHint(.edge, edgeMarginMM: 4),
                       "Start a touch within 4 mm of an edge of the screen.")
        XCTAssertEqual(Wording.practicePalmHint(.edge, edgeMarginMM: 0), "Start a touch at the very edge of the screen.")
        for kind in [PalmTileKind.edge] {
            for edge in [0.0, 4.0] {
                let words = [Wording.practicePalmTitle(kind), Wording.practicePalmHint(kind, edgeMarginMM: edge),
                             Wording.practicePalmRule(kind, edgeMarginMM: edge)]
                for text in words {
                    XCTAssertFalse(text.lowercased().contains("palm"), "one finger: nothing about a palm: \(text)")
                }
            }
        }
    }

    /// The line beneath the palm tile's drawing, with the contact filter's own numbers.
    func testThePalmTilesLine() {
        XCTAssertEqual(Wording.practicePalmRule(.wholeHand, edgeMarginMM: 0), "5 fingers or more landing at once are ignored")
        XCTAssertEqual(Wording.practicePalmRule(.palm, edgeMarginMM: 0), "A resting palm, or a whole hand, is ignored")
        XCTAssertEqual(Wording.practicePalmRule(.edge, edgeMarginMM: 4), "Touches that start within 4 mm of an edge are ignored")
        XCTAssertEqual(Wording.practiceNotAHandYet(1), "1 finger: not a whole hand yet")
        XCTAssertEqual(Wording.practiceNotAHandYet(3), "3 fingers: not a whole hand yet")
        XCTAssertEqual(Wording.practiceNotAtOnce(5), "5 fingers, not all at once: lift, then lay the hand down in one go")
        XCTAssertEqual(Wording.practiceIgnored(.reason(.hand)), "Whole hand: ignored ✓")
        XCTAssertEqual(Wording.practiceIgnored(.reason(.palm)), "A palm: ignored ✓")
        XCTAssertEqual(Wording.practiceIgnored(.reason(.edge)), "A touch at the edge: ignored ✓")
        XCTAssertEqual(Wording.practiceIgnored(.reason(.beyondOneFinger)), "A second finger: ignored ✓")
        XCTAssertEqual(Wording.practiceIgnored(.reason(.otherTouchscreenHasThePointer)),
                       "Ignored: the other touchscreen has the pointer")
        XCTAssertEqual(Wording.practiceIgnored(.words("something else")), "Ignored: something else")
        XCTAssertEqual(Wording.practicePalmOff, "Palm rejection is off: switch it on in the list")
        XCTAssertEqual(Wording.practiceEdgeOff, "Edge rejection is off: its margin is under Accidental touches in Settings")
    }

    func testWhatTactileSaw() {
        let names: [RecognisedGesture.Kind: String] = [
            .tap: "Tap", .doubleTap: "Double tap", .tripleTap: "Triple tap", .drag: "Drag",
            .holdThenDrag: "Hold, then drag", .scroll: "Scroll", .flick: "Flick", .pinch: "Pinch", .rotate: "Rotate",
            .rightClick: "Right-click", .swipe: "Swipe", .followedSwipe: "Swipe that follows", .ignored: "Ignored",
            .cancelled: "Cancelled",
        ]
        for kind in RecognisedGesture.Kind.allCases {
            XCTAssertEqual(Wording.recognisedGesture(kind), names[kind], "\(kind)")
            XCTAssertFalse(GestureSymbol.name(kind).isEmpty)
        }
        XCTAssertEqual(Wording.fingers(0), nil)
        XCTAssertEqual(Wording.fingers(1), "1 finger")
        XCTAssertEqual(Wording.fingers(4), "4 fingers")
        XCTAssertEqual(Wording.gestureTesterSaw, "What Tactile saw")
        XCTAssertEqual(Wording.gestureTesterFingersNow, "Fingers on the glass")
        XCTAssertEqual(Wording.gestureTesterClear, "Clear")
        XCTAssertEqual(Wording.gestureTesterNothingYet, "Nothing yet. Touch the screen.")
    }
}
