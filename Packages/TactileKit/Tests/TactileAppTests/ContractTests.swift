import CoreGraphics
import Foundation
import TactileApp
import TactileGestures
import TactileScreens
import XCTest

final class ContractTests: XCTestCase {
    /// Behaviour away from the defaults, every field.
    private func changedBehaviour() -> BehaviourSnapshot {
        var gestures = GestureOptions.all
        gestures.longPress = false
        gestures.rotate = false
        return BehaviourSnapshot(
            oneFinger: .alwaysScroll, oneFingerChoice: .alwaysScroll, pointerReturn: .staysWhereTouched,
            showsCircles: false, gestures: gestures,
            rejection: RejectionRules(palm: false, edgeMarginMM: 5), reportsPalms: true, multiFingerAvailable: false)
    }

    /// A connected touchscreen, paired with a connected display.
    private func leftPanel() -> TouchscreenSnapshot {
        TouchscreenSnapshot(
            id: TouchscreenID(rawValue: "222a:0001:ABC123"),
            name: "Left panel",
            deviceName: "ILITEK Multi-Touch",
            isConnected: true,
            isOn: true,
            whenOff: .leaveToMacOS,
            mode: .driving,
            status: .pairedWith(name: "DELL P2418HT", detail: "left of the main display"),
            notes: [.oneFingerOnly, .rememberedByPort],
            pairedDisplayID: 3,
            pairedDisplayName: "DELL P2418HT",
            displayChoices: [DisplayChoice(id: 3, name: "DELL P2418HT", detail: "left", inUseBy: nil)],
            orientation: Orientation(quarterTurns: 1, isFlipped: true),
            diagonalInches: nil,
            reportedDiagonalInches: 23.8,
            usbID: "222a:0001",
            serial: "ABC123",
            location: "01141000",
            device: "multi-touch, touch interface, exclusive",
            behaviour: changedBehaviour(),
            isCalibrated: true,
            canBeSetUp: true
        )
    }

    func testASnapshotSurvivesAJSONRoundTrip() throws {
        let touchscreen = leftPanel()
        let remembered = TouchscreenSnapshot(
            id: TouchscreenID(rawValue: "27c0:0859:TEST-SERIAL-0001"),
            name: "Right panel",
            deviceName: "Right panel",
            isConnected: false,
            isOn: false,
            whenOff: .ignoreTouches,
            mode: nil,
            status: .displayNotConnected(name: "LG HDR 4K"),
            notes: [],
            pairedDisplayID: nil,
            pairedDisplayName: "LG HDR 4K",
            displayChoices: [],
            orientation: nil,
            diagonalInches: 15.6,
            reportedDiagonalInches: nil,
            usbID: "27c0:0859",
            serial: "TEST-SERIAL-0001",
            location: nil,
            device: nil,
            behaviour: BehaviourSnapshot(
                oneFinger: .automatic, oneFingerChoice: nil, pointerReturn: .backWhereItWas, showsCircles: true,
                gestures: .all,
                rejection: RejectionRules(), reportsPalms: false, multiFingerAvailable: true),
            isCalibrated: false,
            canBeSetUp: false
        )
        let display = DisplaySnapshot(
            id: 3,
            uuid: "FACADE00-0000-4000-8000-000000000001",
            name: "DELL P2418HT",
            detail: "left of the main display",
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            isBuiltIn: false,
            isMain: false,
            pairedTouchscreen: "Left panel"
        )
        let snapshot = AppSnapshot(
            appVersion: "0.2.0",
            isOn: true,
            warnings: AppWarning.allCases,
            touchscreens: [touchscreen, remembered],
            displays: [display],
            debugLogging: false,
            setUp: SetUpSnapshot(
                touchscreen: touchscreen.id, touchscreenName: "Left panel", purpose: .calibrate,
                step: .corners(display: 3, target: CGPoint(x: 0.1, y: 0.9), index: 2, problem: .moved)),
            setUpMode: nil,
            offerSetUpTo: [remembered.id],
            setUpModeRefusal: .running,
            gestureTester: GestureTesterSnapshot(
                touchscreen: touchscreen.id, touchscreenName: "Left panel", displayID: 3, multiTouch: true,
                performsSwipes: false, fingersDown: 2,
                recent: RecognisedGesture.Kind.allCases.enumerated().reversed().map { index, kind in
                    RecognisedGesture(id: index + 1, kind: kind, fingers: index % 4 + 1, summary: "\(kind.rawValue) ×1.4",
                                      at: 1000.5 + Double(index))
                },
                seen: RecognisedGesture.Kind.allCases.enumerated().map { GestureSeenCount(id: $1, count: $0 + 1) }),
            recordsFrames: true,
            swipesFollowFingers: true,
            canFollowSwipes: true,
            launchAtLogin: .needsApproval
        )

        XCTAssertEqual(snapshot.gestureTester?.recent.count, RecognisedGesture.Kind.allCases.count)
        XCTAssertNotNil(touchscreen.behaviour.oneFingerChoice)
        XCTAssertNil(remembered.behaviour.oneFingerChoice)

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: data), snapshot)
    }

    /// The state file is the snapshot as JSON: set-up mode survives it in every stage, with every
    /// notice and every kind of touchscreen line.
    func testSetUpModeSurvivesAJSONRoundTripInEveryStageAndNotice() throws {
        let ilitek = TouchscreenID(rawValue: "222a:0001:ABC123")
        let strip = TouchscreenID(rawValue: "27c0:0859:TEST-SERIAL-0001")
        let other = TouchscreenID(rawValue: "0eef:0001:")
        let displays = [
            SetUpDisplayCard(id: 3, name: "DELL P2418HT", detail: "left of the main display", touchscreen: ilitek,
                             touchscreenName: "Left panel"),
            SetUpDisplayCard(id: 5, name: "HDMI", detail: "above the main display", touchscreen: nil, touchscreenName: nil),
        ]
        let lines = [
            SetUpTouchscreenLine(id: ilitek, name: "Left panel", state: .setUp(displayName: "DELL P2418HT"), reason: nil),
            SetUpTouchscreenLine(id: strip, name: "TouchScreen", state: .notSetUp, reason: nil),
            SetUpTouchscreenLine(id: other, name: "ACDC", state: .cannotBeSetUp, reason: "Its touches can't be read."),
        ]
        let stages: [SetUpModeSnapshot.Stage] = [
            .choosing, .waitingForTouch(display: 5), .touchedFirst(touchscreen: strip, name: "TouchScreen"), .running,
        ]
        let notices: [SetUpModeNotice?] = [
            nil, .cannotBeSetUp(touchscreen: other, name: "ACDC"), .displayGone(name: "HDMI"),
            .touchscreenGone(name: "TouchScreen"),
        ]
        for stage in stages {
            for notice in notices {
                for justSetUp in [nil, ilitek] {
                    let mode = SetUpModeSnapshot(
                        stage: stage, displays: displays, touchscreens: lines, justSetUp: justSetUp, notice: notice)
                    let snapshot = AppSnapshot(
                        appVersion: "0.5.0", isOn: true, warnings: [], touchscreens: [], displays: [],
                        debugLogging: false, setUp: nil, setUpMode: mode,
                        offerSetUpTo: [strip, other], setUpModeRefusal: .running, gestureTester: nil, recordsFrames: false,
                        swipesFollowFingers: true,
                        canFollowSwipes: true, launchAtLogin: .off)
                    let data = try JSONEncoder().encode(snapshot)
                    XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: data), snapshot,
                                   "\(stage) \(String(describing: notice)) \(String(describing: justSetUp))")
                }
            }
        }
    }

    /// Why set-up mode can't begin: every reason, and none, survive the state file; each is written
    /// as its name; a state file written before the field reads as none.
    func testEverySetUpModeRefusalSurvivesAJSONRoundTrip() throws {
        let refusals: [SetUpModeRefusal?] = [
            nil, .notNow, .tactileOff, .accessibilityMissing, .noDisplay, .running, .noTouchscreenCanBeSetUp,
            .noDisplayToChoose,
        ]
        for refusal in refusals {
            let snapshot = AppSnapshot(
                appVersion: "0.5.0", isOn: true, warnings: [], touchscreens: [leftPanel()], displays: [],
                debugLogging: false, setUp: nil, setUpMode: nil, offerSetUpTo: [], setUpModeRefusal: refusal,
                gestureTester: nil, recordsFrames: false, swipesFollowFingers: false, canFollowSwipes: true,
                launchAtLogin: .off)
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(AppSnapshot.self, from: data), snapshot, "\(String(describing: refusal))")
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object["setUpModeRefusal"] as? String, refusal.map { "\($0)" })

            var withoutKey = object
            withoutKey["setUpModeRefusal"] = nil
            let older = try JSONDecoder().decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: withoutKey))
            XCTAssertNil(older.setUpModeRefusal)
        }
        XCTAssertEqual(SetUpModeRefusal.noDisplayToChoose.rawValue, "noDisplayToChoose")
    }

    func testEveryLaunchAtLoginSurvivesAJSONRoundTrip() throws {
        for state in [LaunchAtLogin.off, .on, .needsApproval, .notInstalled, .unavailable] {
            let data = try JSONEncoder().encode([state])
            XCTAssertEqual(try JSONDecoder().decode([LaunchAtLogin].self, from: data), [state])
        }
    }

    func testEverySetUpStepSurvivesAJSONRoundTrip() throws {
        let steps: [SetUpStep] = [
            .corners(display: 3, target: CGPoint(x: 0.9, y: 0.1), index: 0, problem: nil),
            .corners(display: 3, target: CGPoint(x: 0.1, y: 0.1), index: 1, problem: .tapsDidNotFit),
            .size(display: 3, displayReports: 23.8, touchscreenReports: nil, current: 24),
            .size(display: 3, displayReports: nil, touchscreenReports: nil, current: nil),
            .check(display: 3),
        ]
        for purpose in [SetUpPurpose.full, .calibrate, .test] {
            for step in steps {
                let setUp = SetUpSnapshot(
                    touchscreen: TouchscreenID(rawValue: "222a:0001:ABC123"), touchscreenName: "Left panel",
                    purpose: purpose, step: step)
                let data = try JSONEncoder().encode(setUp)
                XCTAssertEqual(try JSONDecoder().decode(SetUpSnapshot.self, from: data), setUp, "\(purpose) \(step)")
            }
        }
    }

    func testThePairedDisplaysNameSurvivesTheJSONAndMayBeAbsent() throws {
        let touchscreen = leftPanel()
        let data = try JSONEncoder().encode(touchscreen)
        let decoded = try JSONDecoder().decode(TouchscreenSnapshot.self, from: data)
        XCTAssertEqual(decoded.pairedDisplayName, "DELL P2418HT")
        XCTAssertEqual(decoded, touchscreen)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "pairedDisplayName"))
        let withoutKey = try JSONSerialization.data(withJSONObject: object)
        let decodedWithoutKey = try JSONDecoder().decode(TouchscreenSnapshot.self, from: withoutKey)
        XCTAssertNil(decodedWithoutKey.pairedDisplayName)
        var expected = touchscreen
        expected.pairedDisplayName = nil
        XCTAssertEqual(decodedWithoutKey, expected)
    }

    func testAMissingDisplayIsNamedInTheJSON() throws {
        let data = try JSONEncoder().encode(TouchscreenStatus.displayNotConnected(name: "HDMI"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"name\""), json)
        XCTAssertFalse(json.contains("_0"), json)
    }
}
