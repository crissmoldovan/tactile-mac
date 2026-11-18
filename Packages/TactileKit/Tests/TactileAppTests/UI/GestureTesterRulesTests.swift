import AppKit
import Foundation
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The gesture tester's window, kept pure: when Gesture Tester… can be used and why not; where the
/// window goes and which arrangement it takes; which rows each kind of touchscreen gets and in what
/// state; how they count; when the window opens, moves and closes; and the Dock icon it may need.
@MainActor
final class GestureTesterRulesTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel

    private func touchscreen(_ id: TouchscreenID, _ snapshot: AppSnapshot) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: snapshot))
    }

    // MARK: - Gesture Tester…: enabled, and why not

    func testOnTheDeskBothTouchscreensCanOpenTheTester() throws {
        let desk = UIFixtures.desk
        XCTAssertEqual(GestureTesterAvailability.of(try touchscreen(ilitek, desk), in: desk), .available)
        XCTAssertEqual(GestureTesterAvailability.of(try touchscreen(strip, desk), in: desk), .available,
                       "the one-finger strip too: its rows say what it can't do")
        XCTAssertEqual(GestureTesterAvailability.of(try touchscreen(oldPanel, desk), in: desk), .unavailable(.notConnected))
    }

    func testWhyTheTesterCanNotOpen() throws {
        var snapshot = UIFixtures.desk
        var ilitek = try touchscreen(self.ilitek, snapshot)
        func reason() -> GestureTesterAvailability.Reason? { GestureTesterAvailability.of(ilitek, in: snapshot).reason }

        snapshot.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .test,
                                       step: .check(display: 5))
        XCTAssertEqual(reason(), .setUpRunning, "another touchscreen's flow")
        snapshot.setUp = nil
        snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertEqual(reason(), .setUpRunning, "set-up mode, no flow yet")
        snapshot.setUpMode = nil
        ilitek.mode = .settingUp
        XCTAssertEqual(reason(), .setUpRunning)
        ilitek.mode = .driving

        snapshot.isOn = false
        XCTAssertEqual(reason(), .tactileOff)
        snapshot.isOn = true
        snapshot.warnings = [.accessibilityMissing]
        XCTAssertEqual(reason(), .accessibilityMissing)
        snapshot.warnings = [.missionControlShortcutsOff]
        XCTAssertNil(reason(), "another warning changes nothing")

        ilitek.isOn = false
        XCTAssertEqual(reason(), .off)
        ilitek.isOn = true

        ilitek.pairedDisplayID = nil
        XCTAssertEqual(reason(), .displayNotConnected)
        ilitek.pairedDisplayName = nil
        XCTAssertEqual(reason(), .notSetUp)
        ilitek = try touchscreen(self.ilitek, snapshot)

        // A touchscreen whose touches can't be read, or that macOS also handles, is held: the
        // model's rule goes by its mode, and the reason by its notes.
        ilitek.notes = [.touchesCannotBeRead]
        XCTAssertNil(reason(), "driving, whatever a note says: the model would open it")
        ilitek.mode = .held
        XCTAssertEqual(reason(), .touchesCannotBeRead)
        ilitek.notes = [.oneFingerOnly, .macOSMayAlsoRespond]
        XCTAssertEqual(reason(), .macOSAlsoHandlesIt)
        ilitek.notes = []
        XCTAssertEqual(reason(), .notDriving)
        ilitek.mode = .driving
        XCTAssertNil(reason())
    }

    /// The variants of the preview desk, as the pane and the menu see them.
    func testTheVariantsOfTheDesk() throws {
        let cases: [(PreviewModel.Variant, GestureTesterAvailability)] = [
            (.desk, .available),
            (.nothingPaired, .unavailable(.notSetUp)),
            (.accessibilityMissing, .unavailable(.accessibilityMissing)),
            (.tactileOff, .unavailable(.tactileOff)),
            (.displayUnplugged, .unavailable(.displayNotConnected)),
            (.tactileOffDisplayUnplugged, .unavailable(.tactileOff)),
            (.allWarnings, .unavailable(.accessibilityMissing)),
        ]
        for (variant, expected) in cases {
            let snapshot = UIFixtures.snapshot(variant)
            XCTAssertEqual(GestureTesterAvailability.of(try touchscreen(ilitek, snapshot), in: snapshot), expected,
                           "\(variant)")
        }
        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertEqual(GestureTesterAvailability.of(twin, in: twins), .unavailable(.cannotBeToldApart))
    }

    /// The menu offers it in each connected touchscreen's details, with the pane's rule and reason.
    func testTheMenuOffersItInEachConnectedTouchscreensDetails() {
        func availability(_ id: TouchscreenID, _ snapshot: AppSnapshot) -> GestureTesterAvailability? {
            MenuBarContent(snapshot).touchscreens.first { $0.id == id }?.details.controls?.gestureTester
        }
        XCTAssertEqual(availability(ilitek, UIFixtures.desk), .available)
        XCTAssertEqual(availability(strip, UIFixtures.desk), .available)
        XCTAssertNil(availability(oldPanel, UIFixtures.desk), "nothing for a touchscreen that isn't connected")

        let off = UIFixtures.snapshot(.tactileOff)
        XCTAssertEqual(availability(ilitek, off), .unavailable(.tactileOff))
        XCTAssertEqual(availability(strip, off), .unavailable(.tactileOff))

        let model = PreviewModel(.desk)
        model.perform(.setTouchscreenOn(strip, false))
        XCTAssertEqual(availability(ilitek, model.snapshot), .available)
        XCTAssertEqual(availability(strip, model.snapshot), .unavailable(.off))
    }

    func testEveryReasonIsWorded() {
        let long: [GestureTesterAvailability.Reason: String] = [
            .notConnected: "It isn’t connected.",
            .setUpRunning: "A set-up is running. Finish it first.",
            .tactileOff: "Turn Tactile on to try its gestures.",
            .accessibilityMissing: "Tactile needs Accessibility access to drive it.",
            .cannotBeToldApart: "It can’t be told apart from an identical touchscreen, so Tactile doesn’t drive it.",
            .off: "Turn it on to try its gestures.",
            .notSetUp: "Set it up first.",
            .displayNotConnected: "Its display isn’t connected.",
            .touchesCannotBeRead: "Its touches can’t be read.",
            .macOSAlsoHandlesIt: "macOS is also handling this touchscreen, so Tactile doesn’t drive it.",
            .notDriving: "Tactile isn’t driving it now.",
        ]
        for reason in GestureTesterAvailability.Reason.allCases {
            XCTAssertEqual(Wording.gestureTesterUnavailable(reason), long[reason], "\(reason)")
        }
        XCTAssertEqual(Wording.gestureTester, "Gesture Tester…")
    }

    // MARK: - The window: where, how big, which arrangement

    func testTheArrangementFollowsTheDisplaysShape() {
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 2560, height: 1440)), .regular, "16:9")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 1600, height: 600)), .wide, "the strip")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 1920, height: 1200)), .regular, "16:10")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 2056, height: 1329)), .regular, "the MacBook's")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 3440, height: 1440)), .wide, "21:9")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 1080, height: 1920)), .regular, "upright")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 3200, height: 1600)), .wide, "exactly twice")
        XCTAssertEqual(GestureTesterLayout(displaySize: CGSize(width: 3199, height: 1600)), .regular, "just under")
        XCTAssertEqual(GestureTesterLayout(displaySize: .zero), .regular, "no size: the regular one")
    }

    func testTheWindowFillsItsDisplayWithAMargin() {
        // HDMI, 2560 × 1440, less a 25-point menu bar.
        let hdmi = CGRect(x: -252, y: 1329, width: 2560, height: 1415)
        XCTAssertEqual(GestureTesterWindowFrame.margin(for: hdmi), 32)
        XCTAssertEqual(GestureTesterWindowFrame.frame(in: hdmi), CGRect(x: -220, y: 1361, width: 2496, height: 1351))
        // The strip, 1600 × 600, less its menu bar.
        let stripVisible = CGRect(x: 228, y: -600, width: 1600, height: 575)
        XCTAssertEqual(GestureTesterWindowFrame.margin(for: stripVisible), 14)
        XCTAssertEqual(GestureTesterWindowFrame.frame(in: stripVisible), CGRect(x: 242, y: -586, width: 1572, height: 547))
        XCTAssertEqual(GestureTesterWindowFrame.margin(for: CGRect(x: 0, y: 0, width: 400, height: 200)), 8, "never under 8")
        XCTAssertEqual(GestureTesterWindowFrame.margin(for: CGRect(x: 0, y: 0, width: 6000, height: 3000)), 32, "never over 32")
        let tiny = CGRect(x: 0, y: 0, width: 12, height: 12)
        XCTAssertEqual(GestureTesterWindowFrame.frame(in: tiny), tiny, "no room for a margin: the whole of it")
    }

    // MARK: - What this touchscreen can do

    private func behaviour(_ touchscreen: TouchscreenID = UIFixtures.ilitek) throws -> BehaviourSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(touchscreen, in: UIFixtures.desk)).behaviour
    }

    func testTheRowsInTheOrderAPersonLearnsThem() throws {
        let rows = GestureTesterRow.rows(behaviour: try behaviour(), multiTouch: true, swipesFollowFingers: false,
                                         canFollowSwipes: true)
        XCTAssertEqual(rows.map(\.kind), [
            .tap, .doubleTap, .tripleTap, .drag, .oneFinger, .longPress, .twoFingerScroll, .pinch, .rotate,
            .twoFingerTap, .threeFingerSwipes, .fourFingerSwipes, .followedSwipes, .rejection,
        ])
        // The preview desk's ILITEK has no one-finger choice stored: Automatic is its default.
        XCTAssertEqual(rows.map(\.state), [
            .always, .always, .always, .always, .oneFinger(.automatic, isDefault: true), .on, .on, .on, .on, .on, .on,
            .on, .off, .on,
        ])
    }

    /// The strip, as it is on the desk: every row is there; the multi-finger ones say they need more
    /// than one finger; long press, its right-click, keeps its switch.
    func testOnAOneFingerTouchscreenTheMultiFingerRowsSaySoAndStay() throws {
        var stripBehaviour = try behaviour(strip)
        XCTAssertFalse(stripBehaviour.multiFingerAvailable)
        stripBehaviour.oneFinger = .alwaysScroll
        stripBehaviour.oneFingerChoice = nil
        let rows = GestureTesterRow.rows(behaviour: stripBehaviour, multiTouch: false, swipesFollowFingers: true,
                                         canFollowSwipes: true)
        XCTAssertEqual(rows.count, GestureTesterRow.Kind.allCases.count, "none hidden")
        XCTAssertEqual(rows.map(\.state), [
            .always, .always, .always, .always, .oneFinger(.alwaysScroll, isDefault: true), .on,
            .needsMoreThanOneFinger, .needsMoreThanOneFinger, .needsMoreThanOneFinger, .needsMoreThanOneFinger,
            .needsMoreThanOneFinger, .needsMoreThanOneFinger, .needsMoreThanOneFinger, .edgeOnly(0),
        ])
        XCTAssertEqual(rows.map(\.howLines), [1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1],
                       "the seven it can't make are one line each: no how-to")
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.kind == .drag }).dragNeedsHold, "one finger scrolls: hold, then drag")
        XCTAssertEqual(Wording.gestureTesterState(.needsMoreThanOneFinger), "Needs more than one finger")
    }

    /// The join, from the fix rounds' re-review: the faintest grey is for a row that can't happen on
    /// this touchscreen or Mac, never for guidance. On the strip with no edge margin, "Off. Its margin
    /// is under Accidental touches in Settings." is guidance, as is a switched-off row's how-to and
    /// followed swipes waiting for swipes.
    func testOnlyARowThatCannotHappenHereIsDrawnFaintest() throws {
        var stripBehaviour = try behaviour(strip)
        stripBehaviour.rejection.edgeMarginMM = 0
        let strip = GestureTesterRow.rows(behaviour: stripBehaviour, multiTouch: false, swipesFollowFingers: false,
                                          canFollowSwipes: true)
        let edge = try XCTUnwrap(strip.first { $0.kind == .rejection })
        XCTAssertEqual(edge.state, .edgeOnly(0))
        XCTAssertFalse(edge.cannotHappenHere, "its margin is guidance")
        XCTAssertEqual(strip.filter(\.cannotHappenHere).map(\.kind), GestureTesterRow.Kind.allCases.filter(\.needsSeveralFingers))

        var ilitekBehaviour = try behaviour()
        ilitekBehaviour.gestures.pinch = false
        ilitekBehaviour.gestures.swipes = false
        let ilitek = GestureTesterRow.rows(behaviour: ilitekBehaviour, multiTouch: true, swipesFollowFingers: true,
                                           canFollowSwipes: true)
        XCTAssertEqual(ilitek.first { $0.kind == .pinch }?.state, .off)
        XCTAssertEqual(ilitek.first { $0.kind == .followedSwipes }?.state, .needsSwipes)
        XCTAssertEqual(ilitek.filter(\.cannotHappenHere), [], "off, or waiting on swipes: guidance")
        let noFollowing = GestureTesterRow.rows(behaviour: ilitekBehaviour, multiTouch: true, swipesFollowFingers: true,
                                                canFollowSwipes: false)
        XCTAssertEqual(noFollowing.filter(\.cannotHappenHere).map(\.kind), [.followedSwipes], "not on this Mac")
    }

    /// Every combination of the six gesture switches, the one-finger mode and whether it is a choice
    /// or the default, one finger only or not, followed swipes on or off and possible or not, and
    /// palm rejection: each row's state, by the rules the plan gives.
    func testEveryCombination() throws {
        let switches: [WritableKeyPath<GestureOptions, Bool>] = [
            \.twoFingerScroll, \.pinch, \.twoFingerTap, \.swipes, \.longPress, \.rotate,
        ]
        var checked = 0
        for bits in 0..<(1 << switches.count) {
            var gestures = GestureOptions()
            for (index, keyPath) in switches.enumerated() {
                gestures[keyPath: keyPath] = bits & (1 << index) != 0
            }
            for mode in OneFingerMode.allCases {
                for isChoice in [false, true] {
                    for multiTouch in [false, true] {
                        for follow in [false, true] {
                            for canFollow in [false, true] {
                                for (palm, edge) in [(false, 0.0), (true, 4.0)] {
                                    var behaviour = try behaviour()
                                    behaviour.gestures = gestures
                                    behaviour.oneFinger = mode
                                    behaviour.oneFingerChoice = isChoice ? mode : nil
                                    behaviour.multiFingerAvailable = multiTouch
                                    behaviour.rejection.palm = palm
                                    behaviour.rejection.edgeMarginMM = edge
                                    let rows = GestureTesterRow.rows(
                                        behaviour: behaviour, multiTouch: multiTouch, swipesFollowFingers: follow,
                                        canFollowSwipes: canFollow)
                                    XCTAssertEqual(rows.map(\.kind), GestureTesterRow.Kind.allCases)
                                    for row in rows {
                                        XCTAssertEqual(
                                            row.state,
                                            expected(row.kind, gestures: gestures, mode: mode, isChoice: isChoice,
                                                     multiTouch: multiTouch, follow: follow, canFollow: canFollow,
                                                     palm: palm, edge: edge),
                                            "\(row.kind), gestures \(bits), \(mode), multi-touch \(multiTouch)")
                                        XCTAssertEqual(row.dragNeedsHold, row.kind == .drag && mode == .alwaysScroll)
                                        XCTAssertEqual(
                                            row.howLines,
                                            row.state == .needsMoreThanOneFinger
                                                ? 0 : row.kind == .rejection && multiTouch ? 2 : 1)
                                        XCTAssertTrue(row.isEnabled)
                                    }
                                    checked += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 64 * 3 * 2 * 2 * 2 * 2 * 2)
    }

    private func expected(
        _ kind: GestureTesterRow.Kind, gestures: GestureOptions, mode: OneFingerMode, isChoice: Bool, multiTouch: Bool,
        follow: Bool, canFollow: Bool, palm: Bool, edge: Double
    ) -> GestureTesterRow.State {
        func onOff(_ on: Bool) -> GestureTesterRow.State { on ? .on : .off }
        let several: Set<GestureTesterRow.Kind> = [
            .twoFingerScroll, .pinch, .rotate, .twoFingerTap, .threeFingerSwipes, .fourFingerSwipes, .followedSwipes,
        ]
        if several.contains(kind), !multiTouch { return .needsMoreThanOneFinger }
        switch kind {
        case .tap, .doubleTap, .tripleTap, .drag: return .always
        case .oneFinger: return .oneFinger(mode, isDefault: !isChoice)
        case .longPress: return onOff(gestures.longPress)
        case .twoFingerScroll: return onOff(gestures.twoFingerScroll)
        case .pinch: return onOff(gestures.pinch)
        case .rotate: return onOff(gestures.rotate)
        case .twoFingerTap: return onOff(gestures.twoFingerTap)
        case .threeFingerSwipes, .fourFingerSwipes: return onOff(gestures.swipes)
        case .followedSwipes:
            if !canFollow { return .notOnThisMac }
            if !gestures.swipes { return .needsSwipes }
            return onOff(follow)
        case .rejection: return multiTouch ? onOff(palm) : .edgeOnly(edge)
        }
    }

    /// Palm detection needs a contact the panel marks not confident, one over 25 mm, or a whole hand
    /// at once. The row says what this touchscreen can recognise, in the pane's words; on one that
    /// gives one finger (its mouse interface reports none of those) it is about the edge alone.
    func testThePalmRowSaysWhatThisTouchscreenCanRecognise() throws {
        var behaviour = try behaviour()
        behaviour.rejection = RejectionRules(palm: true, edgeMarginMM: 4)
        func rejection(multiTouch: Bool) throws -> GestureTesterRow {
            try XCTUnwrap(GestureTesterRow.rows(behaviour: behaviour, multiTouch: multiTouch, swipesFollowFingers: false,
                                                canFollowSwipes: true).first { $0.kind == .rejection })
        }

        behaviour.reportsPalms = true
        var row = try rejection(multiTouch: true)
        XCTAssertEqual(row.state, .on)
        XCTAssertEqual(Wording.gestureTesterRowTitle(row), "Palm and edge")
        XCTAssertEqual(Wording.gestureTesterRowHow(row, behaviour: behaviour),
                       "\(Wording.palmExplanation(reportsPalms: true)) Edge: 4 mm.")

        behaviour.reportsPalms = false
        row = try rejection(multiTouch: true)
        XCTAssertEqual(Wording.gestureTesterRowHow(row, behaviour: behaviour),
                       "This touchscreen doesn’t report the size of a touch, so only a whole hand can be recognised. Edge: 4 mm.")
        XCTAssertEqual(row.howLines, 2)

        row = try rejection(multiTouch: false)
        XCTAssertEqual(row.state, .edgeOnly(4))
        XCTAssertEqual(Wording.gestureTesterRowTitle(row), "Touches at the edge")
        XCTAssertEqual(Wording.gestureTesterRowHow(row, behaviour: behaviour),
                       "Touches that start within 4 mm of an edge are ignored.")
        XCTAssertEqual(Wording.gestureTesterState(row.state), "4 mm")
        XCTAssertEqual(row.match, GestureTesterRow.Match([.ignored]))

        behaviour.rejection.edgeMarginMM = 0
        row = try rejection(multiTouch: false)
        XCTAssertEqual(Wording.gestureTesterRowHow(row, behaviour: behaviour),
                       "Off. Its margin is under Accidental touches in Settings.")
        XCTAssertEqual(Wording.gestureTesterState(row.state), "Off")
    }

    // MARK: - Type, and room, for each display

    func testMillimetresAPoint() throws {
        let strip = try XCTUnwrap(GestureTesterType.millimetresPerPoint(points: CGSize(width: 1600, height: 600),
                                                                       diagonalInches: 12.3))
        XCTAssertEqual(strip, 0.1828, accuracy: 0.0001)
        let hdmi = try XCTUnwrap(GestureTesterType.millimetresPerPoint(points: CGSize(width: 2560, height: 1440),
                                                                      diagonalInches: 23.8))
        XCTAssertEqual(hdmi, 0.2058, accuracy: 0.0001)
        XCTAssertNil(GestureTesterType.millimetresPerPoint(points: CGSize(width: 1600, height: 600), diagonalInches: nil))
        XCTAssertNil(GestureTesterType.millimetresPerPoint(points: .zero, diagonalInches: 12.3))
        XCTAssertNil(GestureTesterType.millimetresPerPoint(points: CGSize(width: 1600, height: 600), diagonalInches: 0))
    }

    /// At least 12-point text and 13-point titles in the wide arrangement (14 and 17 in the regular),
    /// and larger where a line would be under 2.5 mm on the glass.
    func testTheTypeIsSizedFromTheDisplaysMillimetres() {
        let strip = GestureTesterType(.wide, millimetresPerPoint: 0.1828)
        XCTAssertEqual(strip, GestureTesterType(body: 12, title: 13))
        XCTAssertEqual(GestureTesterType.lineMillimetres(strip.body, millimetresPerPoint: 0.1828), 2.63, accuracy: 0.01)
        XCTAssertEqual(GestureTesterType.lineMillimetres(strip.title, millimetresPerPoint: 0.1828), 2.85, accuracy: 0.01)

        let hdmi = GestureTesterType(.regular, millimetresPerPoint: 0.2058)
        XCTAssertEqual(hdmi, GestureTesterType(body: 14, title: 17))
        XCTAssertEqual(GestureTesterType.lineMillimetres(hdmi.body, millimetresPerPoint: 0.2058), 3.46, accuracy: 0.01)

        // A 13.3″ display at 2560 × 1600 points: 0.112 mm a point. 12-point lines would be 1.6 mm.
        let dense = GestureTesterType(.wide, millimetresPerPoint: 0.1119)
        XCTAssertEqual(dense, GestureTesterType(body: 19, title: 20))
        XCTAssertGreaterThanOrEqual(GestureTesterType.lineMillimetres(dense.body, millimetresPerPoint: 0.1119), 2.5)
        XCTAssertEqual(GestureTesterType(.regular, millimetresPerPoint: 0.1119), GestureTesterType(body: 19, title: 22))

        XCTAssertEqual(GestureTesterType(.wide, millimetresPerPoint: nil), GestureTesterType(body: 12, title: 13),
                       "size unknown: the floors")
        XCTAssertEqual(GestureTesterType(.wide, millimetresPerPoint: 0.001).body, GestureTesterType.largestBody)
    }

    private func content(visible: CGSize) -> CGFloat {
        let frame = GestureTesterWindowFrame.frame(in: CGRect(origin: .zero, size: visible))
        return NSWindow.contentRect(forFrameRect: frame, styleMask: GestureTesterNSWindow.style).height
    }

    private func stripMetrics(multiTouch: Bool) throws -> (GestureTesterMetrics, [GestureTesterRow]) {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(strip))
        let snapshot = model.snapshot
        let tester = try XCTUnwrap(snapshot.gestureTester)
        let touchscreen = try XCTUnwrap(UIFixtures.touchscreen(strip, in: snapshot))
        let metrics = GestureTesterMetrics.forTester(tester, touchscreen: touchscreen, in: snapshot, layout: .wide)
        let rows = GestureTesterRow.rows(behaviour: touchscreen.behaviour, multiTouch: multiTouch,
                                         swipesFollowFingers: false, canFollowSwipes: true)
        return (metrics, rows)
    }

    /// The strip, its 600 points less the menu bar and a 70-point Dock (505), and less the menu bar
    /// alone (575): on its own one-finger touchscreen every row shows without scrolling.
    func testOnTheStripWithTheDockEveryRowOfAOneFingerTouchscreenFits() throws {
        let (metrics, rows) = try stripMetrics(multiTouch: false)
        XCTAssertEqual(metrics.type, GestureTesterType(body: 12, title: 13))
        let withDock = content(visible: CGSize(width: 1600, height: 505))
        XCTAssertLessThanOrEqual(metrics.minimumHeight(rows), withDock,
                                 "needs \(metrics.minimumHeight(rows)) of \(withDock)")
        XCTAssertLessThanOrEqual(metrics.minimumHeight(rows), content(visible: CGSize(width: 1600, height: 575)))
    }

    /// A multi-touch touchscreen on a display of the strip's shape has more rows of two lines: there,
    /// its rows scroll when they don't fit, and only then.
    func testWhereTheRowsDoNotFitTheyScroll() throws {
        let (metrics, rows) = try stripMetrics(multiTouch: true)
        let (_, oneFinger) = try stripMetrics(multiTouch: false)
        XCTAssertGreaterThan(metrics.canDoHeight(rows), metrics.canDoHeight(oneFinger))
        XCTAssertGreaterThan(metrics.minimumHeight(rows), content(visible: CGSize(width: 1600, height: 505)),
                             "with the Dock, the multi-touch rows scroll")
    }

    /// No how-to is ever cut short: each fits its lines at its type, in both arrangements, for both
    /// kinds of touchscreen, every one-finger mode, with and without palm sizes and an edge margin.
    func testNoHowToIsCutShort() throws {
        let types: [(GestureTesterLayout, GestureTesterType)] = [
            (.wide, GestureTesterType(.wide, millimetresPerPoint: 0.1828)),
            (.regular, GestureTesterType(.regular, millimetresPerPoint: 0.2058)),
        ]
        for (layout, type) in types {
            let metrics = GestureTesterMetrics(layout, type: type)
            let font = NSFont.systemFont(ofSize: metrics.bodySize)
            for multiTouch in [false, true] {
                for mode in OneFingerMode.allCases {
                    for (reportsPalms, edge) in [(false, 0.0), (true, 4.0), (false, 10.0)] {
                        var behaviour = try behaviour()
                        behaviour.oneFinger = mode
                        behaviour.reportsPalms = reportsPalms
                        behaviour.rejection.edgeMarginMM = edge
                        let rows = GestureTesterRow.rows(behaviour: behaviour, multiTouch: multiTouch,
                                                         swipesFollowFingers: true, canFollowSwipes: true)
                        for row in rows where row.howLines > 0 {
                            let how = Wording.gestureTesterRowHow(row, behaviour: behaviour)
                            let height = NSAttributedString(string: how, attributes: [.font: font]).boundingRect(
                                with: CGSize(width: metrics.howWidth, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin]).height
                            XCTAssertLessThanOrEqual(
                                height.rounded(.up), CGFloat(row.howLines) * metrics.bodyLine,
                                "\(layout) \(row.kind): “\(how)” needs more than \(row.howLines) line(s)")
                        }
                    }
                }
            }
        }
    }

    func testATouchscreenWithoutARecordCanChangeNothingHere() throws {
        let rows = GestureTesterRow.rows(behaviour: try behaviour(), multiTouch: true, swipesFollowFingers: false,
                                         canFollowSwipes: true, canChangeSettings: false)
        XCTAssertTrue(rows.allSatisfy { !$0.isEnabled })
    }

    func testSwitchingARowSendsThePanesCommand() throws {
        let behaviour = try behaviour()
        for kind in GestureTesterRow.Kind.allCases {
            for on in [false, true] {
                let command = GestureTesterRow.command(kind, on: on, for: ilitek, behaviour: behaviour)
                switch kind {
                case .longPress, .twoFingerScroll, .pinch, .rotate, .twoFingerTap, .threeFingerSwipes, .fourFingerSwipes:
                    let gestureSwitch = try XCTUnwrap(kind.gestureSwitch)
                    XCTAssertEqual(command, GestureRow.command(gestureSwitch, on: on, for: ilitek, behaviour: behaviour))
                case .followedSwipes:
                    XCTAssertEqual(command, .setSwipesFollowFingers(on))
                case .rejection:
                    XCTAssertEqual(command, PalmRejection.command(on, rules: behaviour.rejection, for: ilitek))
                case .tap, .doubleTap, .tripleTap, .drag, .oneFinger:
                    XCTAssertNil(command, "\(kind) has no switch")
                }
            }
        }
        var swipesOff = GestureOptions.all
        swipesOff.swipes = false
        XCTAssertEqual(GestureTesterRow.command(.threeFingerSwipes, on: false, for: ilitek, behaviour: behaviour),
                       .setGestures(ilitek, swipesOff))
        XCTAssertEqual(GestureTesterRow.command(.fourFingerSwipes, on: false, for: ilitek, behaviour: behaviour),
                       .setGestures(ilitek, swipesOff), "three and four fingers share the pane's one switch")
    }

    /// The one-finger row's picker is the pane's (`OneFingerPicker`): the same options, the default
    /// first, with the same titles, and the same commands. So the tester can give the default back,
    /// as the pane can: its Default sends nil.
    func testTheOneFingerPickerIsThePanes() throws {
        for id in [ilitek, strip] {
            for choice in [nil, OneFingerMode.automatic, .alwaysScroll, .alwaysDrag] {
                let name = "\(id.rawValue), choice \(String(describing: choice))"
                let model = PreviewModel(.desk)
                model.perform(.setOneFinger(id, choice))
                let touchscreen = try touchscreen(id, model.snapshot)
                XCTAssertEqual(touchscreen.behaviour.oneFingerChoice, choice, name)
                let pane = OneFingerPicker(touchscreen)
                let rows = GestureTesterRow.rows(
                    for: touchscreen, multiTouch: touchscreen.behaviour.multiFingerAvailable, swipesFollowFingers: false,
                    canFollowSwipes: true)
                let tester = try XCTUnwrap(rows.first { $0.kind == .oneFinger }?.oneFingerPicker, name)
                XCTAssertEqual(tester, pane, name)
                XCTAssertEqual(OneFingerPicker.options.map(tester.title), OneFingerPicker.options.map(pane.title), name)
                for option in OneFingerPicker.options {
                    XCTAssertEqual(tester.command(option, for: id), pane.command(option, for: id), name)
                }
                XCTAssertEqual(tester.command(nil, for: id), choice == nil ? nil : .setOneFinger(id, nil),
                               "\(name): Default sends nil")
                XCTAssertTrue(rows.filter { $0.kind != .oneFinger }.allSatisfy { $0.oneFingerPicker == nil }, name)
            }
        }
        XCTAssertEqual(OneFingerPicker.options.first, .some(nil), "the default first")
        let strip = try touchscreen(self.strip, UIFixtures.desk)
        XCTAssertEqual(OneFingerPicker.options.map(OneFingerPicker(strip).title),
                       ["Default (Always scroll)", "Automatic", "Always drag", "Always scroll"])
    }

    // MARK: - Counting what Tactile saw

    private func tester(
        _ recent: [RecognisedGesture], seen: [GestureSeenCount]? = nil, for touchscreen: TouchscreenID = UIFixtures.ilitek
    ) -> GestureTesterSnapshot {
        let counted = seen ?? RecognisedGesture.Kind.allCases.compactMap { kind in
            let count = recent.filter { $0.kind == kind }.count
            return count == 0 ? nil : GestureSeenCount(id: kind, count: count)
        }
        return GestureTesterSnapshot(
            touchscreen: touchscreen, touchscreenName: "ILITEK-TP", displayID: 2, multiTouch: true,
            performsSwipes: false, fingersDown: 0, recent: recent, seen: counted)
    }

    private func gesture(_ id: Int, _ kind: RecognisedGesture.Kind, _ fingers: Int, _ summary: String = "") -> RecognisedGesture {
        RecognisedGesture(id: id, kind: kind, fingers: fingers, summary: summary, at: Double(id))
    }

    func testRowsCountTheModelsSeenByKindAndTheFeedByFingers() throws {
        let recent = [
            gesture(9, .swipe, 4), gesture(8, .swipe, 3), gesture(7, .swipe, 3), gesture(6, .rightClick, 2),
            gesture(5, .rightClick, 1), gesture(4, .flick, 2), gesture(3, .scroll, 2), gesture(2, .scroll, 1),
            gesture(1, .tap, 1),
        ]
        // The model saw more taps than the feed still holds.
        var seen = tester(recent).seen
        if let index = seen.firstIndex(where: { $0.id == .tap }) { seen[index].count = 12 }
        let snapshot = tester(recent, seen: seen)
        var tally = GestureTally()
        tally.follow(snapshot)
        let rows = GestureTesterRow.rows(behaviour: try behaviour(), multiTouch: true, swipesFollowFingers: false,
                                         canFollowSwipes: true)
        let counts = Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0.count(seen: seen, tally: tally)) })
        XCTAssertEqual(counts[.tap], 12, "a whole kind: the model's count")
        XCTAssertEqual(counts[.oneFinger], 1, "one finger: its scroll")
        XCTAssertEqual(counts[.twoFingerScroll], 2, "two fingers: the scroll and its flick")
        XCTAssertEqual(counts[.longPress], 1)
        XCTAssertEqual(counts[.twoFingerTap], 1)
        XCTAssertEqual(counts[.threeFingerSwipes], 2)
        XCTAssertEqual(counts[.fourFingerSwipes], 1)
        XCTAssertEqual(counts[.pinch], 0)
        XCTAssertEqual(counts[.drag], 0)
    }

    func testWithOneFingerDraggingTheOneFingerRowCountsDrags() throws {
        var dragging = try behaviour()
        dragging.oneFinger = .alwaysDrag
        let row = try XCTUnwrap(GestureTesterRow.rows(behaviour: dragging, multiTouch: true, swipesFollowFingers: false,
                                                      canFollowSwipes: true).first { $0.kind == .oneFinger })
        XCTAssertEqual(row.match, GestureTesterRow.Match([.drag], fingers: 1))
        var scrolling = dragging
        scrolling.oneFinger = .alwaysScroll
        let scrollRow = try XCTUnwrap(GestureTesterRow.rows(behaviour: scrolling, multiTouch: false,
                                                            swipesFollowFingers: false, canFollowSwipes: true)
            .first { $0.kind == .oneFinger })
        XCTAssertEqual(scrollRow.match, GestureTesterRow.Match([.scroll, .flick], fingers: 1))
    }

    /// One entry per scroll, updated in place while it goes on: counted once.
    func testAScrollUpdatedInPlaceIsCountedOnce() {
        var tally = GestureTally()
        tally.follow(tester([gesture(1, .scroll, 1, "40 pt down")]))
        tally.follow(tester([gesture(1, .scroll, 1, "340 pt down")]))
        XCTAssertEqual(tally.count([.scroll], fingers: 1), 1)
    }

    func testTheTallyKeepsWhatHasLeftTheFeed() {
        var tally = GestureTally()
        var recent: [RecognisedGesture] = []
        for id in 1...45 {
            recent.insert(gesture(id, .swipe, 3), at: 0)
            recent = Array(recent.prefix(40))
            tally.follow(tester(recent))
        }
        XCTAssertEqual(tally.count([.swipe], fingers: 3), 45, "the feed holds 40; the row counts all of them")
    }

    func testTheTallyStartsAgain() {
        var tally = GestureTally()
        tally.follow(tester([gesture(2, .swipe, 3), gesture(1, .swipe, 3)]))
        XCTAssertEqual(tally.count([.swipe], fingers: 3), 2)

        tally.follow(tester([]))
        XCTAssertEqual(tally.count([.swipe], fingers: 3), 0, "Clear: nothing in the feed or in seen")

        tally.follow(tester([gesture(3, .swipe, 3)]))
        tally.follow(tester([gesture(1, .swipe, 3)], for: strip))
        XCTAssertEqual(tally.touchscreen, strip)
        XCTAssertEqual(tally.count([.swipe], fingers: 3), 1, "another touchscreen: from its own feed")

        tally.follow(tester([gesture(5, .swipe, 3), gesture(4, .swipe, 3)], for: strip))
        tally.follow(tester([gesture(1, .rightClick, 2)], for: strip))
        XCTAssertEqual(tally.count([.swipe], fingers: 3), 0, "the numbers started again: a new tester")
        XCTAssertEqual(tally.count([.rightClick], fingers: 2), 1)

        tally.follow(nil)
        XCTAssertNil(tally.touchscreen)
        XCTAssertTrue(tally.entries.isEmpty)
    }

    // MARK: - The window, following the snapshot

    private func shown(_ touchscreen: TouchscreenID, _ display: UInt32) -> GestureTesterPresenter.Shown {
        GestureTesterPresenter.Shown(touchscreen: touchscreen, displayID: display)
    }

    private func tester(_ touchscreen: TouchscreenID, on display: UInt32, fingers: Int = 0) -> GestureTesterSnapshot {
        GestureTesterSnapshot(touchscreen: touchscreen, touchscreenName: "", displayID: display, multiTouch: true,
                              performsSwipes: false, fingersDown: fingers, recent: [], seen: [])
    }

    func testTheWindowFollowsTheTester() {
        var presenter = GestureTesterPresenter()
        XCTAssertEqual(presenter.told(nil), .nothing)
        XCTAssertEqual(presenter.told(tester(ilitek, on: 2)), .open(shown(ilitek, 2)))
        XCTAssertEqual(presenter.told(tester(ilitek, on: 2, fingers: 3)), .nothing, "the feed changing moves nothing")
        XCTAssertEqual(presenter.told(tester(strip, on: 5)), .replace(shown(strip, 5)), "moved to the other touchscreen")
        XCTAssertEqual(presenter.told(tester(strip, on: 4)), .replace(shown(strip, 4)), "and to another display")
        XCTAssertEqual(presenter.told(nil), .close("the tester closed"))
        XCTAssertEqual(presenter.told(nil), .nothing)
    }

    /// The close button or Esc: the window goes at once and the model is told, once. Until the model
    /// has closed it, the tester it still names stays closed.
    func testThePersonsCloseIsSentOnce() {
        var presenter = GestureTesterPresenter()
        _ = presenter.told(tester(ilitek, on: 2))
        XCTAssertEqual(presenter.closedByPerson(), .send(.closeGestureTester))
        XCTAssertEqual(presenter.closedByPerson(), .nothing)
        XCTAssertEqual(presenter.told(tester(ilitek, on: 2, fingers: 1)), .nothing, "the model hasn't caught up")
        XCTAssertEqual(presenter.told(nil), .nothing, "it has: already down")
        XCTAssertEqual(presenter.told(tester(ilitek, on: 2)), .open(shown(ilitek, 2)), "opened again later")
    }

    func testAfterThePersonsCloseAnotherTesterOpens() {
        var presenter = GestureTesterPresenter()
        _ = presenter.told(tester(ilitek, on: 2))
        _ = presenter.closedByPerson()
        XCTAssertEqual(presenter.told(tester(strip, on: 5)), .open(shown(strip, 5)))
    }

    func testGestureTesterPressedForTheOneUpBringsItForward() {
        var presenter = GestureTesterPresenter()
        XCTAssertEqual(presenter.asked(toOpen: ilitek), .nothing, "nothing up: the snapshot will open it")
        _ = presenter.told(tester(ilitek, on: 2))
        XCTAssertEqual(presenter.asked(toOpen: ilitek), .bringForward)
        XCTAssertEqual(presenter.asked(toOpen: strip), .nothing, "another: the snapshot will move it")
    }

    func testGestureTesterPressedAfterThePersonClosedItOpensItAgain() {
        var presenter = GestureTesterPresenter()
        _ = presenter.told(tester(ilitek, on: 2))
        _ = presenter.closedByPerson()
        XCTAssertEqual(presenter.asked(toOpen: ilitek), .open(shown(ilitek, 2)), "the model still names it")
        XCTAssertEqual(presenter.told(tester(ilitek, on: 2)), .nothing, "up already")
    }

    /// Moving the tester to the other touchscreen replaces the window and keeps Tactile a regular app
    /// if it was made one: the Dock icon doesn't blink. A close, by the model or the person, lets go.
    func testMovingTheTesterKeepsTheDockHold() {
        var presenter = GestureTesterPresenter()
        let open = presenter.told(tester(ilitek, on: 2))
        XCTAssertFalse(open.releasesHold)
        let moved = presenter.told(tester(strip, on: 5))
        XCTAssertEqual(moved, .replace(shown(strip, 5)))
        XCTAssertFalse(moved.releasesHold)
        XCTAssertTrue(presenter.closedByPerson().releasesHold)
        XCTAssertTrue(GestureTesterPresenter.Action.close("the tester closed").releasesHold)
        XCTAssertFalse(GestureTesterPresenter.Action.bringForward.releasesHold)

        // As the window does it: the old window closes keeping the hold; the new one opens.
        var holds = RegularAppHolds()
        holds.opened(.gestureTester)
        XCTAssertEqual(holds.hold(.gestureTester, current: .accessory), .regular)
        holds.opened(.gestureTester)
        XCTAssertEqual(holds.hold(.gestureTester, current: .regular), nil, "regular all along")
        XCTAssertEqual(holds.release(.gestureTester), .accessory, "the tester's close lets go")
    }

    func testAtQuitTheWindowGoesQuietly() {
        var presenter = GestureTesterPresenter()
        _ = presenter.told(tester(ilitek, on: 2))
        presenter.closedQuietly()
        XCTAssertNil(presenter.shown)
        XCTAssertEqual(presenter.closedByPerson(), .nothing, "nothing sent")
    }

    // MARK: - Tactile as a regular app, for Settings and the tester

    func testOneWindowMakesTactileRegularAndBack() {
        var holds = RegularAppHolds()
        holds.opened(.settings)
        XCTAssertEqual(holds.hold(.settings, current: .accessory), .regular)
        XCTAssertEqual(holds.release(.settings), .accessory)
        XCTAssertEqual(holds.release(.settings), nil)
    }

    func testThePolicyComesBackWhenTheLastWindowClosesInEitherOrder() {
        var holds = RegularAppHolds()
        holds.opened(.settings)
        XCTAssertEqual(holds.hold(.settings, current: .accessory), .regular)
        holds.opened(.gestureTester)
        XCTAssertEqual(holds.hold(.gestureTester, current: .regular), nil, "regular already")
        XCTAssertEqual(holds.release(.settings), nil, "the tester is still open")
        XCTAssertEqual(holds.release(.gestureTester), .accessory)

        var reverse = RegularAppHolds()
        reverse.opened(.gestureTester)
        XCTAssertEqual(reverse.hold(.gestureTester, current: .accessory), .regular)
        reverse.opened(.settings)
        XCTAssertEqual(reverse.release(.gestureTester), nil, "Settings is still open, though it needed nothing")
        XCTAssertEqual(reverse.release(.settings), .accessory)
    }

    func testNothingChangesWhenNoWindowNeededIt() {
        var holds = RegularAppHolds()
        holds.opened(.gestureTester)
        XCTAssertEqual(holds.release(.gestureTester), nil)
        XCTAssertEqual(holds.hold(.settings, current: .regular), nil)
        XCTAssertEqual(holds.release(.settings), nil, "it was regular before")
    }
}
