// Delivery 4b, Parts S2 and L, through the model: followed swipes (the setting, whether this Mac can
// follow them, every way a touch stops during one) and launch at login. The Dock-swipe sender's
// events are captured by the recording outputs, and launch at login is the fake conditions': nothing
// posts a Dock swipe, and nothing is registered.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileDevices
import TactileGestures
import TactileOutput
import TactileReading
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

@MainActor
final class LivingOnTheMacModelTests: XCTestCase {

    /// The desk with followed swipes switched on.
    private func following() throws -> ModelHarness {
        try deskHarness(self, settings: with(Desk.settings) { $0.swipesFollowFingers = true })
    }

    /// Three fingers on the ILITEK, 30 mm apart, moving left `millimetres` from `start`, in frames
    /// 10 ms apart; the lift too when `lifting`. Returns where the first finger is.
    @discardableResult
    private func swipe(_ harness: ModelHarness, from start: TimeInterval, left millimetres: Double, steps: Int = 20,
                       startX: CGFloat = 0.45, lifting: Bool) -> CGFloat {
        let width = SurfaceSize.millimetres(display: Desk.hdmi, diagonalInches: 23.8).width
        let spacing = 30 / width
        let step = CGFloat(millimetres) / CGFloat(steps) / width
        var frames: [ContactFrame] = []
        var x = startX
        for index in 0...steps {
            if index > 0 { x -= step }
            frames.append(ContactFrame(time: start + Double(index) * 0.01, contacts: (0..<3).map {
                Contact(id: $0, position: CGPoint(x: x + CGFloat($0) * spacing, y: 0.5))
            }))
        }
        if lifting { frames.append(ContactFrame(time: start + Double(steps + 1) * 0.01, contacts: [])) }
        harness.send(frames, from: Desk.ilitekHandle)
        return x
    }

    private func ends(_ harness: ModelHarness) -> [DockEvent.Phase?] {
        harness.outputs.dockSwipeEvents.filter(\.isEnd).map(\.phase)
    }

    // MARK: - The setting, and whether this Mac can follow

    func testTheSettingIsStoredAtOnceAndFollowedFromTheNextSession() throws {
        let harness = try deskHarness(self)
        XCTAssertFalse(harness.model.snapshot.swipesFollowFingers)
        _ = swipe(harness, from: harness.clock + 1, left: 50, lifting: true)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.record.dockEvents, [], "off: today's swipe")
        XCTAssertEqual(harness.outputs.shortcuts, 1)

        harness.model.perform(.setSwipesFollowFingers(true))
        XCTAssertTrue(harness.model.snapshot.swipesFollowFingers)
        XCTAssertEqual(harness.savedSettings()?.swipesFollowFingers, true, "stored at once")
        _ = swipe(harness, from: harness.clock + 1, left: 50, lifting: true)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.dockPhases.first, .began)
        XCTAssertEqual(ends(harness), [.ended])
        XCTAssertEqual(harness.outputs.shortcuts, 1, "no second shortcut")
    }

    func testCanFollowSwipesIsTheSendersAnswerForThisMac() throws {
        let harness = try deskHarness(self)
        XCTAssertTrue(harness.model.snapshot.canFollowSwipes, "macOS 15, the gesture on")
        harness.outputs.dockSurroundings.isSpaceSwipeEnabled = false
        harness.conditions.setTouchUpRunning(false)  // any change: a round
        XCTAssertFalse(harness.model.snapshot.canFollowSwipes, "the gesture off in System Settings")
        harness.outputs.dockSurroundings.isSpaceSwipeEnabled = true
        harness.outputs.dockSurroundings.macOSMajorVersion = 27
        harness.conditions.setTouchUpRunning(false)
        XCTAssertFalse(harness.model.snapshot.canFollowSwipes, "a macOS it doesn't know")
        harness.outputs.dockSurroundings.macOSMajorVersion = 26
        harness.outputs.dockSurroundings.defaultSpaces = nil
        harness.conditions.setTouchUpRunning(false)
        XCTAssertTrue(harness.model.snapshot.canFollowSwipes, "the Spaces are asked for at a swipe's beginning only")
    }

    /// The final review's fix 1 (its probe A1): the gesture switched off in System Settings while
    /// Tactile follows swipes. The conditions notice it and say they changed, with nothing they carry
    /// different; at that round the row shows off and disabled, with why, the snapshot and Copy
    /// Diagnostics say this Mac can't follow them, and the next swipe is the shortcut. What is
    /// stored stays on.
    func testTheGestureSwitchedOffInSystemSettingsShowsAtTheNextRound() throws {
        let harness = try following()
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot), FollowedSwipesRow(isOn: true, isEnabled: true, reason: nil))
        let requests = harness.source.requests(for: Desk.ilitekHandle)

        harness.switchSpaceSwipe(false)
        XCTAssertFalse(harness.model.snapshot.canFollowSwipes)
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot),
                       FollowedSwipesRow(isOn: false, isEnabled: false, reason: Wording.swipesFollowFingersUnavailable))
        XCTAssertTrue(harness.model.snapshot.swipesFollowFingers, "the stored setting stays on")
        XCTAssertEqual(harness.source.requests(for: Desk.ilitekHandle), requests, "nothing asked of the touchscreens")
        harness.model.perform(.copyDiagnostics)
        XCTAssertTrue(try XCTUnwrap(harness.pasteboard.last).contains("(this Mac can't follow them)"))

        swipe(harness, from: harness.clock + 1, left: 50, lifting: true)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.record.dockEvents, [], "the interface and the pipeline agree")
        XCTAssertEqual(harness.outputs.shortcuts, 1)
    }

    /// The final review's fix 1 (its probe A2), the one a person meets: the row says the gesture
    /// must be switched on; they switch it on in System Settings. At the round the conditions'
    /// change makes, the row is enabled and on again, as the stored setting is, and the next swipe
    /// is followed. Then off and on once more: the row follows each time.
    func testTheGestureSwitchedOnInSystemSettingsShowsAtTheNextRound() throws {
        let harness = try following()
        harness.switchSpaceSwipe(false)
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot).reason, Wording.swipesFollowFingersUnavailable)

        harness.switchSpaceSwipe(true)
        XCTAssertTrue(harness.model.snapshot.canFollowSwipes)
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot), FollowedSwipesRow(isOn: true, isEnabled: true, reason: nil))
        harness.model.perform(.copyDiagnostics)
        XCTAssertTrue(try XCTUnwrap(harness.pasteboard.last).contains("(this Mac can follow them)"))
        swipe(harness, from: harness.clock + 1, left: 50, lifting: true)
        harness.tick(after: 1)
        XCTAssertEqual(harness.outputs.dockPhases.first, .began, "the interface and the pipeline agree")
        XCTAssertEqual(ends(harness), [.ended])
        XCTAssertEqual(harness.outputs.shortcuts, 0)

        for isOn in [false, true, false, true] {
            harness.switchSpaceSwipe(isOn)
            XCTAssertEqual(harness.model.snapshot.canFollowSwipes, isOn)
            XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot).isEnabled, isOn)
            XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot).isOn, isOn)
        }
    }

    /// With the stored setting off, the row still follows the gesture: enabled, and off.
    func testTheGestureSettingShowsWithTheStoredSettingOffToo() throws {
        let harness = try deskHarness(self)
        harness.switchSpaceSwipe(false)
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot),
                       FollowedSwipesRow(isOn: false, isEnabled: false, reason: Wording.swipesFollowFingersUnavailable))
        harness.switchSpaceSwipe(true)
        XCTAssertEqual(FollowedSwipesRow(harness.model.snapshot), FollowedSwipesRow(isOn: false, isEnabled: true, reason: nil))
    }

    // MARK: - Every way the model stops a touch during a followed swipe (Review Focus 1)

    /// What a stop does to a followed swipe whose fingers then go on and lift going forward.
    private enum Expected {
        /// The touch is cut short: one cancelled end, no shortcut.
        case cutShort
        /// The Dock slides back but the touch goes on: one cancelled end, and the fingers'
        /// completion is the shortcut (they lose the following, never the swipe).
        case closedKeepingTheSwipe
        /// Nothing to do with this swipe: it ends followed.
        case goesOn
    }

    /// Every way the model stops a touchscreen, or changes something under it, during a followed swipe.
    private var everyStop: [(name: String, stop: (ModelHarness) -> Void, undo: ((ModelHarness) -> Void)?, expected: Expected)] {
        [
            ("unplugged", { $0.source.unplug(Desk.ilitekHandle) }, { $0.source.plugIn(Desk.ilitek()) }, .cutShort),
            ("Tactile off", { $0.model.perform(.setOn(false)) }, { $0.model.perform(.setOn(true)) }, .cutShort),
            ("Accessibility gone", { $0.conditions.setAccessibility(false) }, { $0.conditions.setAccessibility(true) }, .cutShort),
            ("locked", { $0.conditions.setSessionActive(false) }, { $0.conditions.setSessionActive(true) }, .cutShort),
            ("asleep", { $0.conditions.sleep() }, { $0.conditions.wake() }, .cutShort),
            ("displays reconfiguring", { $0.displays.set([]) }, { $0.displays.set(Desk.displays) }, .cutShort),
            ("another display gone", { $0.displays.set(Desk.displays.filter { $0.displayID != Desk.lg.displayID }) },
             { $0.displays.set(Desk.displays) }, .closedKeepingTheSwipe),
            ("its display gone", { $0.displays.set(Desk.displays.filter { $0.displayID != Desk.hdmi.displayID }) },
             { $0.displays.set(Desk.displays) }, .cutShort),
            ("the touchscreen turned off", { $0.model.perform(.setTouchscreenOn(Desk.ilitekID, false)) },
             { $0.model.perform(.setTouchscreenOn(Desk.ilitekID, true)) }, .cutShort),
            ("set-up on it", { $0.model.perform(.beginSetUp(Desk.ilitekID, .calibrate)) }, { $0.model.perform(.cancelSetUp) },
             .cutShort),
            ("set-up on the strip", { $0.model.perform(.beginSetUp(Desk.stripID, .calibrate)) }, { $0.model.perform(.cancelSetUp) },
             .goesOn),
            ("unpaired", { $0.model.perform(.unpair(Desk.ilitekID)) },
             { $0.model.perform(.pair(Desk.ilitekID, displayID: Desk.hdmi.displayID)) }, .cutShort),
            // The model's own cancel (`cancelTouch`): the fingers now come from elsewhere.
            ("its touches now from its mouse interface",
             { $0.source.change(Desk.ilitekHandle) { $0.status.touchOrigin = .mouseInterface } },
             { $0.source.change(Desk.ilitekHandle) { $0.status.touchOrigin = .touchInterface } }, .cutShort),
            // Forgetting is refused for a connected touchscreen; the only forgetting during a swipe
            // is of another, unplugged, touchscreen.
            ("forgotten, refused as it is connected", { $0.model.perform(.forget(Desk.ilitekID)) }, { _ in }, .goesOn),
            ("the strip unplugged and forgotten", { harness in
                harness.source.unplug(Desk.stripHandle)
                harness.model.perform(.forget(Desk.stripID))
            }, { $0.source.plugIn(Desk.stripScreen()) }, .goesOn),
            ("the setting off", { $0.model.perform(.setSwipesFollowFingers(false)) },
             { $0.model.perform(.setSwipesFollowFingers(true)) }, .goesOn),
            ("the gesture off in System Settings", { harness in
                harness.outputs.dockSurroundings.isSpaceSwipeEnabled = false
                harness.conditions.setTouchUpRunning(false)
            }, { harness in
                harness.outputs.dockSurroundings.isSpaceSwipeEnabled = true
                harness.conditions.setTouchUpRunning(false)
            }, .goesOn),
            ("quitting", { $0.model.shutDown() }, nil, .cutShort),
        ]
    }

    /// The first end of each swipe (the repeats, but at quit, wait in the recording's scheduler).
    func testEveryStopDuringAFollowedSwipe() throws {
        for (name, stop, _, expected) in everyStop {
            let harness = try following()
            let x = swipe(harness, from: harness.clock + 1, left: 30, lifting: false)
            XCTAssertTrue(harness.outputs.dockSwipes.isOpen, "\(name): open")
            stop(harness)
            let closed = expected == .goesOn ? [] : (name == "quitting" ? [DockEvent.Phase.cancelled, .cancelled] : [.cancelled])
            XCTAssertEqual(ends(harness), closed, "\(name): the end at the stop")
            XCTAssertEqual(harness.outputs.dockSwipes.isOpen, expected == .goesOn, name)

            // The fingers go on and lift going forward.
            _ = swipe(harness, from: harness.clock + 0.01, left: 30, startX: x, lifting: true)
            harness.tick(after: 2)
            switch expected {
            case .cutShort:
                XCTAssertEqual(ends(harness), closed, "\(name): nothing more")
                XCTAssertEqual(harness.outputs.shortcuts, 0, "\(name): no shortcut")
            case .closedKeepingTheSwipe:
                XCTAssertEqual(ends(harness), [.cancelled], "\(name): nothing more from the Dock")
                XCTAssertEqual(harness.outputs.shortcuts, 1, "\(name): the swipe, by the shortcut")
            case .goesOn:
                XCTAssertEqual(ends(harness), [.ended], "\(name): followed to its end")
                XCTAssertEqual(harness.outputs.shortcuts, 0, name)
            }
            XCTAssertFalse(harness.outputs.dockSwipes.isOpen, name)
        }
    }

    /// The reviewer's P5: every stop at three moments (just after the `began`, mid-swipe, straight
    /// after the lift), each checking the ends, the shortcuts, no button, a free pointer; and then,
    /// once undone, that the next swipe is followed normally.
    func testEveryStopAtThreeMomentsThenTheNextSwipe() throws {
        let moments: [(name: String, millimetres: Double, steps: Int, lifted: Bool)] = [
            ("just after the began", 10, 2, false), ("mid-swipe", 30, 20, false), ("straight after the lift", 50, 20, true),
        ]
        for (name, stop, undo, expected) in everyStop {
            for moment in moments {
                let harness = try following()
                let label = "\(name), \(moment.name)"
                let x = swipe(harness, from: harness.clock + 1, left: moment.millimetres, steps: moment.steps,
                              lifting: moment.lifted)
                XCTAssertEqual(harness.outputs.dockPhases.first, .began, label)
                stop(harness)
                if !moment.lifted {
                    _ = swipe(harness, from: harness.clock + 0.01, left: 30, steps: 10, startX: x, lifting: true)
                }
                harness.tick(after: 2)
                let first = ends(harness).first
                let shortcuts = harness.outputs.shortcuts
                if moment.lifted {
                    XCTAssertEqual(first, .ended, "\(label): it had ended")
                    XCTAssertEqual(shortcuts, 0, label)
                } else {
                    switch expected {
                    case .cutShort:
                        XCTAssertEqual(first, .cancelled, label)
                        XCTAssertEqual(shortcuts, 0, label)
                    case .closedKeepingTheSwipe:
                        XCTAssertEqual(first, .cancelled, label)
                        XCTAssertEqual(shortcuts, 1, label)
                    case .goesOn:
                        XCTAssertEqual(first, .ended, label)
                        XCTAssertEqual(shortcuts, 0, label)
                    }
                }
                XCTAssertEqual(harness.outputs.dockSwipeEvents.filter(\.isEnd).filter { $0.phase != first }.count, 0,
                               "\(label): one kind of end")
                XCTAssertEqual(harness.outputs.count(.down), 0, label)
                XCTAssertFalse(harness.outputs.dockSwipes.isOpen, label)
                XCTAssertNil(harness.outputs.arbiter.owner, label)

                guard let undo else { continue }
                undo(harness)
                harness.tick(after: 2)
                let before = harness.outputs.dockPhases.count
                swipe(harness, from: harness.clock + 1, left: 50, steps: 20, lifting: true)
                harness.tick(after: 2)
                let next = harness.outputs.dockPhases.dropFirst(before).filter { $0 != .changed }
                XCTAssertEqual(Array(next), [.began, .ended], "\(label): the next swipe")
                XCTAssertEqual(harness.outputs.shortcuts, shortcuts, "\(label): no shortcut for it")
            }
        }
    }

    /// Fix 4: the repeated end can't wait for 0.2 s at quit; it goes before `shutDown` returns.
    func testAtQuitTheEndGoesTwiceBeforeShutDownReturns() throws {
        let harness = try following()
        swipe(harness, from: harness.clock + 1, left: 30, lifting: false)
        harness.model.shutDown()
        XCTAssertEqual(ends(harness), [.cancelled, .cancelled])
        XCTAssertTrue(harness.outputs.record.dockScheduled.isEmpty, "nothing left waiting")
    }

    func testTheSwipeIsClosedBeforeAnythingElseTheModelDoes() throws {
        for (name, stop, next) in [
            ("asleep", { (h: ModelHarness) in h.conditions.sleep() }, "source.setState \(Desk.ilitekHandle) released"),
            ("quitting", { (h: ModelHarness) in h.model.shutDown() }, "source.setState \(Desk.ilitekHandle) released"),
            ("unplugged", { (h: ModelHarness) in h.source.unplug(Desk.ilitekHandle) }, "arrow shown"),
        ] {
            let harness = try following()
            _ = swipe(harness, from: harness.clock + 1, left: 30, lifting: false)
            stop(harness)
            let end = try XCTUnwrap(harness.log.first("dock cancelled"), name)
            let after = try XCTUnwrap(harness.log.first(next), name)
            XCTAssertLessThan(end, after, name)
        }
    }

    func testTheSendersPerEventLinesFollowDebugLoggingOnlyInTheApp() {
        let app = DockSwipeLogging(swipes: true, events: false)
        XCTAssertEqual(TactileModel.dockSwipeLogging(app, debugLogging: true), DockSwipeLogging(swipes: true, events: true))
        XCTAssertEqual(TactileModel.dockSwipeLogging(DockSwipeLogging(swipes: true, events: true), debugLogging: false), app)
        XCTAssertEqual(TactileModel.dockSwipeLogging(.quiet, debugLogging: true), .quiet, "a test's sender stays quiet")
    }

    func testATestsSenderStaysQuietWithDebugLoggingOn() throws {
        let harness = try deskHarness(self)
        harness.model.perform(.setDebugLogging(true))
        XCTAssertEqual(harness.outputs.dockSwipes.logging, .quiet)
    }

    // MARK: - Launch at login (Part L)

    func testLaunchAtLoginIsWhatTheSystemSays() throws {
        let harness = try deskHarness(self)
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .off)
        let before = try Data(contentsOf: harness.settingsURL)

        harness.model.perform(.setLaunchAtLogin(true))
        XCTAssertEqual(harness.conditions.launchAtLoginRequests, [true])
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .on, "read again after the command")

        // macOS wants the person's approval: the switch says so, and Login Items opens on request.
        harness.conditions.answerToLaunchAtLogin = { _ in .needsApproval }
        harness.model.perform(.setLaunchAtLogin(true))
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .needsApproval)
        harness.model.perform(.openLoginItemsSettings)
        XCTAssertEqual(harness.conditions.loginItemsOpened, 1)
        // The person allows it there and comes back.
        harness.conditions.launchAtLoginChanged(to: .on)
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .on)

        harness.conditions.answerToLaunchAtLogin = { _ in .off }
        harness.model.perform(.setLaunchAtLogin(false))
        XCTAssertEqual(harness.conditions.launchAtLoginRequests, [true, true, false])
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .off)
        XCTAssertEqual(try Data(contentsOf: harness.settingsURL), before, "the system keeps it, not the settings")
    }

    /// The final review's fix 2 (its probe D): Copy Diagnostics copies what is known when it is
    /// pressed, not the last round's snapshot. Launch at login switched on in System Settings, with
    /// no word from the conditions yet: the copy says on, and the snapshot agrees.
    func testCopyDiagnosticsAfterALaunchAtLoginChangeTheModelWasNotToldOf() throws {
        let harness = try following()
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .off)
        harness.conditions.launchAtLogin = .on
        harness.model.perform(.copyDiagnostics)
        let text = try XCTUnwrap(harness.pasteboard.last)
        XCTAssertTrue(text.contains("· launch at login on\n"), text)
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .on)
    }

    /// The same for the trackpad gesture, switched off with no round since: the copy says this Mac
    /// can't follow swipes, as the pipelines already know.
    func testCopyDiagnosticsAfterAGestureChangeTheModelWasNotToldOf() throws {
        let harness = try following()
        harness.outputs.dockSurroundings.isSpaceSwipeEnabled = false
        harness.model.perform(.copyDiagnostics)
        let text = try XCTUnwrap(harness.pasteboard.last)
        XCTAssertTrue(text.contains("Swipes follow the fingers on (this Mac can't follow them)"), text)
        XCTAssertFalse(harness.model.snapshot.canFollowSwipes)
    }

    /// Which of `AppCommand`'s cases `command` is. Exhaustive, so a new case doesn't compile until it
    /// is named here, and the test below then fails until it drives it.
    private static func caseIndex(_ command: AppCommand) -> Int {
        switch command {
        case .setOn: return 0
        case .setTouchscreenOn: return 1
        case .setWhenOff: return 2
        case .rename: return 3
        case .pair: return 4
        case .unpair: return 5
        case .setOrientation: return 6
        case .setDiagonal: return 7
        case .forget: return 8
        case .renameDisplay: return 9
        case .setDebugLogging: return 10
        case .askForAccessibility: return 11
        case .setOneFinger: return 12
        case .setPointerReturn: return 13
        case .setShowsCircles: return 14
        case .setGestures: return 15
        case .setRejection: return 16
        case .copyBehaviour: return 17
        case .resetBehaviour: return 18
        case .clearCalibration: return 19
        case .beginSetUp: return 20
        case .setUpConfirmSize: return 21
        case .setUpRedo: return 22
        case .setUpDone: return 23
        case .cancelSetUp: return 24
        case .declineSetUp: return 25
        case .setRecordsFrames: return 26
        case .copyDiagnostics: return 27
        case .setSwipesFollowFingers: return 28
        case .setLaunchAtLogin: return 29
        case .openLoginItemsSettings: return 30
        case .beginSetUpMode: return 31
        case .setUpChoose: return 32
        case .setUpBack: return 33
        case .openGestureTester: return 34
        case .closeGestureTester: return 35
        case .setGestureTesterPerformsSwipes: return 36
        case .clearGestureTester: return 37
        case .beginSupportCheck: return 38
        case .endSupportCheck: return 39
        }
    }

    private static let appCommandCases = 40

    /// The final review's item 4: nothing asks macOS to launch Tactile at login but the switch.
    /// Whatever the system says of it, the conditions see no request after `start`, nor after one of
    /// every other command; the switch's command is the one that asks.
    func testNothingButTheSwitchAsksToLaunchAtLogin() throws {
        let ilitek = Desk.ilitekID, strip = Desk.stripID
        let commands: [AppCommand] = [
            .setOn(true), .setTouchscreenOn(ilitek, true), .setWhenOff(ilitek, .ignoreTouches), .rename(ilitek, to: "Desk"),
            .unpair(strip), .pair(strip, displayID: Desk.strip.displayID), .setOrientation(ilitek, .asFitted),
            .setDiagonal(ilitek, inches: 23.8), .forget(TouchscreenID(rawValue: "1111:2222:gone")),
            .renameDisplay(uuid: Desk.hdmi.uuid, to: "Top"), .setDebugLogging(false), .askForAccessibility,
            .setOneFinger(ilitek, .automatic), .setPointerReturn(ilitek, .backWhereItWas), .setShowsCircles(ilitek, true),
            .setGestures(ilitek, .all), .setRejection(ilitek, RejectionRules()), .copyBehaviour(from: ilitek, to: strip),
            .resetBehaviour(strip), .clearCalibration(ilitek), .beginSetUp(ilitek, .calibrate),
            .setUpConfirmSize(inches: nil), .setUpRedo, .setUpDone, .cancelSetUp, .declineSetUp(ilitek),
            .setRecordsFrames(false), .copyDiagnostics, .setSwipesFollowFingers(true), .openLoginItemsSettings,
            .beginSetUpMode, .setUpChoose(displayID: Desk.hdmi.displayID), .setUpBack,
            .openGestureTester(ilitek), .setGestureTesterPerformsSwipes(true), .clearGestureTester, .closeGestureTester,
            .beginSupportCheck(ilitek), .endSupportCheck,
        ]
        XCTAssertEqual(Set(commands.map(Self.caseIndex)),
                       Set(0..<Self.appCommandCases).subtracting([Self.caseIndex(.setLaunchAtLogin(true))]),
                       "one of every command but the switch's")

        for state: LaunchAtLogin in [.off, .on, .needsApproval, .notInstalled, .unavailable] {
            let harness = try deskHarness(self)
            harness.conditions.launchAtLoginChanged(to: state)
            XCTAssertEqual(harness.conditions.launchAtLoginRequests, [], "\(state): after start")
            for command in commands {
                harness.model.perform(command)
                XCTAssertEqual(harness.conditions.launchAtLoginRequests, [], "\(state): after \(command)")
            }
            harness.model.perform(.setLaunchAtLogin(state != .on))
            XCTAssertEqual(harness.conditions.launchAtLoginRequests, [state != .on], "\(state): the switch asks")
        }
    }

    func testLaunchAtLoginIsReadAfterEveryCommand() throws {
        let harness = try deskHarness(self)
        harness.conditions.launchAtLogin = .notInstalled  // changed without a word
        harness.model.perform(.setDebugLogging(true))
        XCTAssertEqual(harness.model.snapshot.launchAtLogin, .notInstalled)
    }

    /// Fix 7: the installed copy is the one in `/Applications` or `~/Applications`, its symbolic
    /// links resolved first.
    func testTheInstalledCopyIsTheOneInApplicationsWithItsLinksResolved() {
        let home = "/Volumes/Home/someone"
        let build = "/Volumes/Home/someone/work/tactile/build/Release/Tactile.app"
        // A link in /Applications to a build folder, as `ln -s` would leave it.
        let links = ["/Applications/Linked.app": build]
        func installed(_ path: String) -> Bool {
            LaunchAtLoginRules.isTheInstalledCopy(bundlePath: path, home: home, resolvingSymlinks: { links[$0] ?? $0 })
        }
        XCTAssertTrue(installed("/Applications/Tactile.app"))
        XCTAssertTrue(installed("/Volumes/Home/someone/Applications/Tactile.app"), "~/Applications")
        XCTAssertTrue(installed("/Applications/Utilities/Tactile.app"), "deeper in")
        XCTAssertTrue(installed("/applications/Tactile.app"), "without regard to case")
        XCTAssertFalse(installed(build), "a build folder")
        XCTAssertFalse(installed("/Applications/Linked.app"), "a link in /Applications into a build folder")
        XCTAssertFalse(installed("/Volumes/Home/someone/work/Applications/Tactile.app"), "a path that merely contains Applications")
        XCTAssertFalse(installed("/Volumes/Applications/Tactile.app"))
        XCTAssertFalse(installed("/ApplicationsOld/Tactile.app"))
        XCTAssertFalse(installed("/Volumes/Home/other/Applications/Tactile.app"), "another person's")
        XCTAssertFalse(installed("/private/var/folders/xy/T/AppTranslocation/1234/d/Tactile.app"), "translocated")
        XCTAssertFalse(installed("/Applications"))
        XCTAssertFalse(installed("/Applications/../Volumes/Home/someone/Tactile.app"))
    }

    /// Fix 7: installed and `notFound` (never registered, or unregistered) is off; unavailable only
    /// after a request in this run was refused. Carried item D: on and waiting for approval are read
    /// before where Tactile runs, so a registered item can always be switched off; not installed and
    /// not registered is `notInstalled`.
    func testWhatTheSwitchShows() {
        func state(installed: Bool = true, _ status: LoginItemStatus?, refused: Bool = false) -> LaunchAtLogin {
            LaunchAtLoginRules.state(isInstalled: installed, status: status, refused: refused)
        }
        XCTAssertEqual(state(.notRegistered), .off)
        XCTAssertEqual(state(.notFound), .off, "installed, never registered, nobody has asked")
        XCTAssertEqual(state(nil), .off, "a status this Tactile doesn't know")
        XCTAssertEqual(state(.enabled), .on)
        XCTAssertEqual(state(.requiresApproval), .needsApproval)
        XCTAssertEqual(state(.notFound, refused: true), .unavailable, "a request in this run was refused")
        XCTAssertEqual(state(.notRegistered, refused: true), .unavailable)
        XCTAssertEqual(state(.enabled, refused: true), .on, "registered after all")
        XCTAssertEqual(state(.requiresApproval, refused: true), .needsApproval)
        for refused in [false, true] {
            XCTAssertEqual(state(installed: false, .enabled, refused: refused), .on,
                           "a build folder whose login item is registered: it can be switched off")
            XCTAssertEqual(state(installed: false, .requiresApproval, refused: refused), .needsApproval,
                           "a build folder whose login item waits for approval")
            for status: LoginItemStatus? in [.notRegistered, .notFound, nil] {
                XCTAssertEqual(state(installed: false, status, refused: refused), .notInstalled,
                               "\(String(describing: status)), \(refused)")
            }
        }
    }

    /// Carried item D: switching on from outside the Applications folder is refused before macOS is
    /// asked; switching off from there reaches it. From the installed copy, both reach it.
    func testARequestFromABuildFolder() {
        let off = FakeLoginItem(status: .enabled)
        XCTAssertEqual(LaunchAtLoginRules.request(true, isInstalled: false, registrar: off), .notTheInstalledCopy)
        XCTAssertEqual(off.calls, [], "nothing is registered from a build folder")
        XCTAssertEqual(off.status, .enabled)

        let registered = FakeLoginItem(status: .enabled)
        XCTAssertEqual(LaunchAtLoginRules.request(false, isInstalled: false, registrar: registered),
                       .asked(error: nil, statusAfter: .notFound, refused: false))
        XCTAssertEqual(registered.calls, [.unregister], "switched off from where it runs")
        XCTAssertEqual(LaunchAtLoginRules.state(isInstalled: false, status: registered.status, refused: false), .notInstalled,
                       "and then it can't be switched on again from there")

        let installed = FakeLoginItem(status: .notFound)
        XCTAssertEqual(LaunchAtLoginRules.request(true, isInstalled: true, registrar: installed),
                       .asked(error: nil, statusAfter: .enabled, refused: false))
        XCTAssertEqual(installed.calls, [.register])
        XCTAssertEqual(LaunchAtLoginRules.request(false, isInstalled: true, registrar: installed),
                       .asked(error: nil, statusAfter: .notFound, refused: false))
        XCTAssertEqual(installed.calls, [.register, .unregister])
    }

    /// A request macOS refuses: the call threw, or switching on left it neither on nor waiting.
    func testARefusedRequest() {
        let throwing = FakeLoginItem(status: .notFound)
        throwing.error = FakeLoginItem.Refusal()
        guard case .asked(let error?, .notFound, true) = LaunchAtLoginRules.request(true, isInstalled: true, registrar: throwing)
        else { return XCTFail("a call that threw is refused") }
        XCTAssertTrue(error.contains("Refusal"), error)

        let ignored = FakeLoginItem(status: .notFound)
        ignored.statusAfterRegister = .notRegistered
        XCTAssertEqual(LaunchAtLoginRules.request(true, isInstalled: true, registrar: ignored),
                       .asked(error: nil, statusAfter: .notRegistered, refused: true))
    }

    /// Fix 7: whether a request was refused, from what the call did and what the system says after.
    func testARequestIsRefusedWhenItThrewOrDidNothing() {
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: true, threw: true, statusAfter: .notRegistered))
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: true, threw: false, statusAfter: .notRegistered), "still not on")
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: true, threw: false, statusAfter: .notFound))
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: true, threw: false, statusAfter: nil))
        XCTAssertFalse(LaunchAtLoginRules.wasRefused(on: true, threw: false, statusAfter: .enabled))
        XCTAssertFalse(LaunchAtLoginRules.wasRefused(on: true, threw: false, statusAfter: .requiresApproval), "waiting for approval")
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: true, threw: true, statusAfter: .requiresApproval), "a call that threw")
        XCTAssertEqual(LaunchAtLoginRules.state(isInstalled: true, status: .requiresApproval, refused: true), .needsApproval,
                       "though waiting for approval still shows as that")
        XCTAssertTrue(LaunchAtLoginRules.wasRefused(on: false, threw: true, statusAfter: .enabled))
        XCTAssertFalse(LaunchAtLoginRules.wasRefused(on: false, threw: false, statusAfter: .notRegistered))
        XCTAssertFalse(LaunchAtLoginRules.wasRefused(on: false, threw: false, statusAfter: .notFound))
    }
}

/// A login item for `LaunchAtLoginRules.request`, in place of `SMAppService.mainApp`: it records each
/// call, and changes its status as macOS would.
@MainActor
final class FakeLoginItem: LoginItemRegistrar {
    struct Refusal: Error {}
    enum Call: Equatable { case register, unregister }

    var calls: [Call] = []
    var status: LoginItemStatus?
    var statusAfterRegister: LoginItemStatus? = .enabled
    var statusAfterUnregister: LoginItemStatus? = .notFound
    var error: Error?

    init(status: LoginItemStatus?) {
        self.status = status
    }

    func register() throws {
        calls.append(.register)
        if let error { throw error }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append(.unregister)
        if let error { throw error }
        status = statusAfterUnregister
    }
}
