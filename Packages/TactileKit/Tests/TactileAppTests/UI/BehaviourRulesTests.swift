import Foundation
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The interface's decisions for the set-up and behaviour controls: when set-up by touch, calibration
/// and test can be used and why not, a touchscreen that can't be told apart, the gesture switches,
/// the edge margin, what Copy Settings From… lists, Set Up Touchscreens… in the menu, and the
/// first-run window.
@MainActor
final class BehaviourRulesTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel

    private func touchscreen(_ id: TouchscreenID, _ snapshot: AppSnapshot) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: snapshot))
    }

    // MARK: - Set up by touch

    func testOnTheDeskEveryConnectedTouchscreenCanBeSetUp() throws {
        let desk = UIFixtures.desk
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(ilitek, desk), in: desk), .available)
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(strip, desk), in: desk), .available)
        XCTAssertEqual(SetUpAvailability.onItsDisplay(try touchscreen(ilitek, desk), in: desk), .available)
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(oldPanel, desk), in: desk), .unavailable(.notConnected))
    }

    func testWhySetUpIsUnavailable() throws {
        var snapshot = UIFixtures.desk
        var ilitek = try touchscreen(self.ilitek, snapshot)

        snapshot.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .full,
                                       step: .check(display: 5))
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.anotherBeingSetUp))
        snapshot.setUp?.touchscreen = self.ilitek
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.beingSetUp))
        snapshot.setUp = nil

        snapshot.isOn = false
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.tactileOff))
        snapshot.isOn = true
        snapshot.warnings = [.accessibilityMissing]
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.accessibilityMissing))
        snapshot.warnings = []

        ilitek.notes = [.cannotBeToldApart]
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.cannotBeToldApart))
        ilitek.notes = [.touchesCannotBeRead]
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.touchesCannotBeRead))
        ilitek.notes = []
        let status = ilitek.status
        ilitek.status = .stoppedAnswering
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.stoppedAnswering))
        XCTAssertEqual(SetUpAvailability.onItsDisplay(ilitek, in: snapshot), .unavailable(.stoppedAnswering))
        XCTAssertEqual(Wording.setUpUnavailable(.stoppedAnswering), "It stopped answering. Unplug it and plug it back in.")
        ilitek.status = status
        ilitek.canBeSetUp = false
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.notNow),
                       "everything else allows it: the model's word, just now")
    }

    /// While set-up mode is on, between flows, the pane's buttons say so; during a flow in it, which
    /// touchscreen is being set up.
    func testWhileSetUpModeIsOn() throws {
        var snapshot = UIFixtures.desk
        snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        let ilitek = try touchscreen(self.ilitek, snapshot)
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.setUpModeOn))
        XCTAssertEqual(SetUpAvailability.onItsDisplay(ilitek, in: snapshot), .unavailable(.setUpModeOn))
        snapshot.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .full,
                                       step: .check(display: 5))
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.anotherBeingSetUp))
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(strip, snapshot), in: snapshot), .unavailable(.beingSetUp))
    }

    /// Set-up mode takes a display from another touchscreen if asked, so no display has to be free:
    /// only that one exists. Taken from the model's `canBeSetUp`, once everything else allows it.
    func testNoExternalDisplay() throws {
        var snapshot = UIFixtures.desk
        var ilitek = try touchscreen(self.ilitek, snapshot)
        snapshot.displays.removeAll { !$0.isBuiltIn }
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.noExternalDisplay))
        ilitek.canBeSetUp = false
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.noExternalDisplay))
        snapshot.displays = []
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(.noExternalDisplay))

        // Every external display paired with the other touchscreen: still available.
        let taken = UIFixtures.desk
        var strip = try touchscreen(self.strip, taken)
        strip.pairedDisplayID = nil
        strip.pairedDisplayName = nil
        XCTAssertEqual(SetUpAvailability.full(strip, in: taken), .available)
    }

    func testCalibrationAndTestNeedItsOwnDisplayConnected() throws {
        let desk = UIFixtures.desk
        var ilitek = try touchscreen(self.ilitek, desk)
        ilitek.pairedDisplayID = nil
        XCTAssertEqual(SetUpAvailability.onItsDisplay(ilitek, in: desk), .unavailable(.displayNotConnected))
        ilitek.pairedDisplayName = nil
        XCTAssertEqual(SetUpAvailability.onItsDisplay(ilitek, in: desk), .unavailable(.unpaired))

        let unplugged = UIFixtures.snapshot(.displayUnplugged)
        XCTAssertEqual(SetUpAvailability.onItsDisplay(try touchscreen(self.ilitek, unplugged), in: unplugged),
                       .unavailable(.displayNotConnected))
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(self.ilitek, unplugged), in: unplugged), .available,
                       "a full set-up can pair it with another display")

        // `canBeSetUp` is about a full set-up; calibration and test need only its own display.
        ilitek = try touchscreen(self.ilitek, desk)
        ilitek.canBeSetUp = false
        XCTAssertEqual(SetUpAvailability.onItsDisplay(ilitek, in: desk), .available)
        XCTAssertEqual(SetUpAvailability.full(ilitek, in: desk), .unavailable(.notNow))
    }

    /// A touchscreen in mouse mode that macOS still sees (Tactile couldn't take it for itself): the
    /// model refuses every set-up of it. So Set Up by Touch…, Calibrate Corners… and Test all say
    /// why, rather than look usable or blame the displays.
    func testATouchscreenMacOSIsAlsoHandlingCannotBeSetUpCalibratedOrTested() throws {
        let desk = UIFixtures.desk
        var strip = try touchscreen(self.strip, desk)
        // As the model shows it: still paired with its connected display, held, no set-up possible.
        strip.notes = [.oneFingerOnly, .macOSMayAlsoRespond]
        strip.mode = .held
        strip.canBeSetUp = false
        XCTAssertNotNil(strip.pairedDisplayID)
        XCTAssertEqual(SetUpAvailability.full(strip, in: desk), .unavailable(.macOSAlsoHandlesIt),
                       "Set Up by Touch…: not \"every external display is paired\"")
        XCTAssertEqual(SetUpAvailability.onItsDisplay(strip, in: desk), .unavailable(.macOSAlsoHandlesIt),
                       "Calibrate Corners… and Test")
        XCTAssertEqual(SetUpAvailability.offered(strip, in: desk), .unavailable(.macOSAlsoHandlesIt),
                       "the first-run window")
        XCTAssertEqual(SetUpAvailability.full(try touchscreen(ilitek, desk), in: desk), .available, "the other one")

        // Either note alone: the model sets it up.
        strip.canBeSetUp = true
        for notes in [[TouchscreenNote.oneFingerOnly], [.macOSMayAlsoRespond]] {
            strip.notes = notes
            XCTAssertEqual(SetUpAvailability.full(strip, in: desk), .available, "\(notes)")
            XCTAssertEqual(SetUpAvailability.onItsDisplay(strip, in: desk), .available, "\(notes)")
        }
    }

    func testEveryReasonHasWords() {
        let reasons: [SetUpAvailability.Reason] = [
            .notConnected, .beingSetUp, .anotherBeingSetUp, .setUpModeOn, .tactileOff, .accessibilityMissing,
            .cannotBeToldApart, .touchesCannotBeRead, .macOSAlsoHandlesIt, .noExternalDisplay, .notNow, .unpaired,
            .displayNotConnected,
        ]
        for reason in reasons {
            XCTAssertFalse(Wording.setUpUnavailable(reason).isEmpty)
            XCTAssertEqual(SetUpAvailability.unavailable(reason).reason, reason)
        }
        XCTAssertNil(SetUpAvailability.available.reason)
    }

    // MARK: - The controls that change a fit

    /// While a set-up runs the model changes no fit of any touchscreen: Display, Orientation, Flip,
    /// Diagonal, Use Whole Glass and Forget are disabled for every one, the one being set up and the
    /// others, with one line saying why; and enabled again when it ends.
    func testTheFitControlsWaitForASetUp() throws {
        let model = PreviewModel(.desk)
        let everyOne = [(ilitek, "the touchscreen being set up"), (strip, "the other one"),
                        (oldPanel, "a remembered one: Forget")]
        for (id, which) in everyOne {
            let fit = FitControls(try touchscreen(id, model.snapshot), in: model.snapshot)
            XCTAssertNil(fit.reason, "\(which), before")
            XCTAssertTrue(fit.isEnabled, "\(which), before")
            XCTAssertTrue(fit.orientationIsEnabled, "\(which), before: paired")
        }
        model.perform(.beginSetUp(ilitek, .calibrate))
        for (id, which) in everyOne {
            let fit = FitControls(try touchscreen(id, model.snapshot), in: model.snapshot)
            XCTAssertEqual(fit.reason, .setUpRunning, which)
            XCTAssertFalse(fit.isEnabled, which)
            XCTAssertFalse(fit.orientationIsEnabled, which)
        }
        model.perform(.cancelSetUp)
        for (id, which) in everyOne {
            let fit = FitControls(try touchscreen(id, model.snapshot), in: model.snapshot)
            XCTAssertNil(fit.reason, "\(which), after")
            XCTAssertTrue(fit.isEnabled, "\(which), after")
        }
    }

    /// A touchscreen that can't be told apart never changes a fit, and its note says why, set-up or
    /// not. Orientation and Flip also need a pairing.
    func testTheFitControlsOfATwinAndOfAnUnpairedTouchscreen() throws {
        var twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertEqual(FitControls(twin, in: twins).reason, .cannotBeToldApart)
        twins.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .test,
                                    step: .check(display: 5))
        XCTAssertEqual(FitControls(twin, in: twins).reason, .cannotBeToldApart, "no set-up line: it could never change them")
        XCTAssertFalse(FitControls(twin, in: twins).orientationIsEnabled)

        let first = UIFixtures.snapshot(.nothingPaired)
        let unpaired = FitControls(try touchscreen(ilitek, first), in: first)
        XCTAssertTrue(unpaired.isEnabled)
        XCTAssertFalse(unpaired.orientationIsEnabled, "the orientation belongs to the glass on its display")
    }

    // MARK: - A touchscreen that can't be told apart

    func testATouchscreenThatCannotBeToldApartCannotBeChanged() throws {
        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertFalse(twin.canChangeSettings)
        XCTAssertTrue(try touchscreen(ilitek, twins).canChangeSettings)
        XCTAssertEqual(SetUpAvailability.full(twin, in: twins), .unavailable(.cannotBeToldApart))
    }

    func testMacOSIgnoresItIsShownBesideWhenOffNotUnderTheName() throws {
        var ilitek = try touchscreen(self.ilitek, UIFixtures.desk)
        ilitek.notes = [.oneFingerOnly, .macOSIgnoresIt, .cannotBeToldApart]
        XCTAssertEqual(ilitek.headerNotes, [.oneFingerOnly, .cannotBeToldApart])
        XCTAssertTrue(ilitek.macOSIgnoresIt)
    }

    // MARK: - Dots and the menu while a touchscreen is set up

    func testTheDotWhileBeingSetUp() throws {
        var ilitek = try touchscreen(self.ilitek, UIFixtures.desk)
        ilitek.mode = .settingUp
        XCTAssertEqual(StatusIndicator(ilitek), .settingUp)
        ilitek.status = .notSetUp
        XCTAssertEqual(StatusIndicator(ilitek), .settingUp)
    }

    // MARK: - Set Up Touchscreens… in the menu

    /// One item for every touchscreen, enabled whenever set-up mode could begin, set up or not.
    func testSetUpTouchscreensIsEnabledWhenTheModeCouldBegin() {
        for variant in [PreviewModel.Variant.desk, .nothingPaired, .displayUnplugged, .identicalTwins] {
            XCTAssertEqual(SetUpModeAvailability(UIFixtures.snapshot(variant)), .available, "\(variant)")
            XCTAssertEqual(MenuBarContent(UIFixtures.snapshot(variant)).setUp, .available, "\(variant)")
        }
        XCTAssertEqual(SetUpModeAvailability.command, .beginSetUpMode)
    }

    /// Each reason, in the order the menu says it.
    func testWhySetUpTouchscreensCannotBeUsed() throws {
        var snapshot = UIFixtures.desk
        snapshot.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertEqual(SetUpModeAvailability(snapshot), .unavailable(.running), "set-up mode on")
        snapshot.setUpMode = nil
        snapshot.setUp = SetUpSnapshot(touchscreen: ilitek, touchscreenName: "ILITEK-TP", purpose: .test,
                                       step: .check(display: 2))
        XCTAssertEqual(SetUpModeAvailability(snapshot), .unavailable(.running), "a test from a pane")
        snapshot.setUp = nil

        XCTAssertEqual(SetUpModeAvailability(UIFixtures.snapshot(.tactileOff)), .unavailable(.tactileOff))
        XCTAssertEqual(SetUpModeAvailability(UIFixtures.snapshot(.accessibilityMissing)), .unavailable(.accessibilityMissing))
        XCTAssertEqual(SetUpModeAvailability(UIFixtures.snapshot(.allWarnings)), .unavailable(.accessibilityMissing))

        var none = UIFixtures.desk
        none.touchscreens.removeAll(where: \.isConnected)
        XCTAssertEqual(SetUpModeAvailability(none), .unavailable(.noTouchscreen), "only a remembered one")

        // Neither connected touchscreen can be set up: the strip shared with macOS, the ILITEK
        // unreadable.
        var unable = UIFixtures.desk
        for index in unable.touchscreens.indices where unable.touchscreens[index].isConnected {
            unable.touchscreens[index].notes = unable.touchscreens[index].id == strip
                ? [.oneFingerOnly, .macOSMayAlsoRespond] : [.touchesCannotBeRead]
            unable.touchscreens[index].canBeSetUp = false
        }
        XCTAssertEqual(SetUpModeAvailability(unable), .unavailable(.noneCanBeSetUp))
        if let index = unable.touchscreens.firstIndex(where: { $0.id == strip }) {
            unable.touchscreens[index].notes = [.oneFingerOnly]
            unable.touchscreens[index].canBeSetUp = true
        }
        XCTAssertEqual(SetUpModeAvailability(unable), .available, "one that can is enough")

        var noDisplay = UIFixtures.desk
        noDisplay.displays.removeAll { !$0.isBuiltIn }
        XCTAssertEqual(SetUpModeAvailability(noDisplay), .unavailable(.noExternalDisplay))

        // While the displays settle every touchscreen is held, and the model says not just now.
        var settling = UIFixtures.desk
        for index in settling.touchscreens.indices {
            settling.touchscreens[index].canBeSetUp = false
            if settling.touchscreens[index].isConnected { settling.touchscreens[index].mode = .held }
        }
        XCTAssertEqual(SetUpModeAvailability(settling), .unavailable(.notNow), "the model's word: not just now")
        XCTAssertEqual(MenuBarContent(settling).setUp, .unavailable(.notNow))

        // The model says there is no display to choose (every external display in a mirror set):
        // its reason, whether a touchscreen drives or none does.
        var mirrored = UIFixtures.desk
        for index in mirrored.touchscreens.indices { mirrored.touchscreens[index].canBeSetUp = false }
        mirrored.setUpModeRefusal = .noDisplayToChoose
        XCTAssertEqual(SetUpModeAvailability(mirrored), .unavailable(.noDisplayToChoose))
        var mirroredAndHeld = mirrored
        for index in mirroredAndHeld.touchscreens.indices where mirroredAndHeld.touchscreens[index].isConnected {
            mirroredAndHeld.touchscreens[index].mode = .held
        }
        XCTAssertEqual(SetUpModeAvailability(mirroredAndHeld), .unavailable(.noDisplayToChoose), "none drives")
        var drivingNotNow = mirrored
        drivingNotNow.setUpModeRefusal = .notNow
        XCTAssertEqual(SetUpModeAvailability(drivingNotNow), .unavailable(.notNow),
                       "a touchscreen drives: no guess at mirroring, the model's word")
        XCTAssertEqual(MenuBarContent(mirrored).setUp, .unavailable(.noDisplayToChoose))
        let ilitekThere = try XCTUnwrap(mirrored.touchscreens.first { $0.id == ilitek })
        XCTAssertEqual(SetUpAvailability.full(ilitekThere, in: mirrored), .unavailable(.noDisplayToChoose))
        XCTAssertEqual(Wording.setUpModeUnavailable(.noDisplayToChoose),
                       "No display can be chosen: displays that mirror each other can’t be told apart. Stop mirroring first.")
    }

    /// Every reason the model gives for not beginning set-up mode, in a snapshot where everything
    /// else the interface can see allows it: the menu's item and a pane's Set Up by Touch… each
    /// say one, in words.
    func testEveryRefusalOfTheModelIsWordedInTheMenuAndThePane() throws {
        let cases: [(SetUpModeRefusal, menu: SetUpModeAvailability.Reason, pane: SetUpAvailability.Reason)] = [
            (.notNow, .notNow, .notNow),
            (.tactileOff, .tactileOff, .tactileOff),
            (.accessibilityMissing, .accessibilityMissing, .accessibilityMissing),
            (.noDisplay, .noExternalDisplay, .noExternalDisplay),
            (.running, .running, .setUpModeOn),
            (.noTouchscreenCanBeSetUp, .noneCanBeSetUp, .notNow),
            (.noDisplayToChoose, .noDisplayToChoose, .noDisplayToChoose),
        ]
        // Every case, once: a new one fails to compile here until it is worded above.
        for (refusal, _, _) in cases {
            switch refusal {
            case .notNow, .tactileOff, .accessibilityMissing, .noDisplay, .running, .noTouchscreenCanBeSetUp,
                 .noDisplayToChoose: break
            }
        }
        XCTAssertEqual(cases.count, 7)
        for (refusal, menuReason, paneReason) in cases {
            var snapshot = UIFixtures.desk
            for index in snapshot.touchscreens.indices { snapshot.touchscreens[index].canBeSetUp = false }
            snapshot.setUpModeRefusal = refusal
            XCTAssertEqual(SetUpModeAvailability(snapshot), .unavailable(menuReason), "\(refusal)")
            XCTAssertEqual(MenuBarContent(snapshot).setUp, .unavailable(menuReason), "\(refusal)")
            XCTAssertFalse(Wording.setUpModeUnavailable(menuReason).isEmpty, "\(refusal)")
            let ilitek = try touchscreen(self.ilitek, snapshot)
            XCTAssertEqual(SetUpAvailability.full(ilitek, in: snapshot), .unavailable(paneReason), "\(refusal)")
            XCTAssertFalse(Wording.setUpUnavailable(paneReason).isEmpty, "\(refusal)")
        }
    }

    /// The twin can't be set up: its pane's button says so; the menu's item is for every
    /// touchscreen, and the ILITEK and the strip can be.
    func testATwinCannotBeSetUpButTheOthersCan() throws {
        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.id.rawValue.hasPrefix("#") })
        XCTAssertFalse(twin.canBeSetUpByTouch)
        XCTAssertEqual(SetUpAvailability.full(twin, in: twins), .unavailable(.cannotBeToldApart))
        XCTAssertEqual(MenuBarContent(twins).setUp, .available)
    }

    // MARK: - One finger

    /// The default first, named with the mode it gives on this touchscreen, then the three modes.
    /// On the strip, which gives one finger, the default is Always scroll; on the ILITEK, Automatic.
    func testTheOneFingerPopUp() throws {
        let desk = UIFixtures.desk
        let onStrip = OneFingerPicker(try touchscreen(strip, desk))
        XCTAssertEqual(OneFingerPicker.options, [nil, .automatic, .alwaysDrag, .alwaysScroll])
        XCTAssertEqual(OneFingerPicker.options.map(onStrip.title),
                       ["Default (Always scroll)", "Automatic", "Always drag", "Always scroll"])
        XCTAssertNil(onStrip.choice)
        XCTAssertEqual(onStrip.inForce, .alwaysScroll)
        XCTAssertEqual(onStrip.explanation,
                       "Scrolls, as on a phone. To drag, rest a finger until the ring appears, then move it.",
                       "Always scroll on a one-finger touchscreen: how to drag")

        let onILITEK = OneFingerPicker(try touchscreen(ilitek, desk))
        XCTAssertEqual(onILITEK.title(nil), "Default (Automatic)")
        XCTAssertEqual(onILITEK.explanation, "Drags or scrolls depending on what’s under it")
    }

    /// With a mode chosen, the default is still named for the touchscreen's kind, and the line
    /// beneath explains the mode in force.
    func testAChoiceMadeAndTheDefaultStillNamed() throws {
        var strip = try touchscreen(self.strip, UIFixtures.desk)
        strip.behaviour.oneFingerChoice = .alwaysDrag
        strip.behaviour.oneFinger = .alwaysDrag
        let picker = OneFingerPicker(strip)
        XCTAssertEqual(picker.choice, .alwaysDrag)
        XCTAssertEqual(picker.title(nil), "Default (Always scroll)", "the strip's kind")
        XCTAssertEqual(picker.explanation, "Drags, as a mouse would")

        var ilitek = try touchscreen(self.ilitek, UIFixtures.desk)
        ilitek.behaviour.oneFingerChoice = .alwaysScroll
        ilitek.behaviour.oneFinger = .alwaysScroll
        XCTAssertEqual(OneFingerPicker(ilitek).title(nil), "Default (Automatic)")
        XCTAssertEqual(OneFingerPicker(ilitek).explanation,
                       "Scrolls, as on a phone. To drag, rest a finger until the ring appears, then move it.")
    }

    /// The ring shows only with long-press on and the touch circles shown; without it, the line
    /// says to rest a moment.
    func testHowToDragWithoutTheRing() throws {
        for change in [{ (b: inout BehaviourSnapshot) in b.gestures.longPress = false },
                       { (b: inout BehaviourSnapshot) in b.showsCircles = false }] {
            var strip = try touchscreen(self.strip, UIFixtures.desk)
            change(&strip.behaviour)
            let picker = OneFingerPicker(strip)
            XCTAssertFalse(picker.ringShows)
            XCTAssertEqual(picker.explanation, "Scrolls, as on a phone. To drag, rest a finger for a moment, then move it.")
        }
    }

    /// The default sends nil; a mode sends itself, even the one the default gives; the one chosen
    /// sends nothing.
    func testWhatTheOneFingerPopUpSends() throws {
        let strip = try touchscreen(self.strip, UIFixtures.desk)
        let picker = OneFingerPicker(strip)
        XCTAssertNil(picker.command(nil, for: self.strip), "already the default")
        XCTAssertEqual(picker.command(.alwaysScroll, for: self.strip), .setOneFinger(self.strip, .alwaysScroll),
                       "a choice, though the default gives the same")
        XCTAssertEqual(picker.command(.automatic, for: self.strip), .setOneFinger(self.strip, .automatic))
        var chosen = strip
        chosen.behaviour.oneFingerChoice = .automatic
        chosen.behaviour.oneFinger = .automatic
        XCTAssertEqual(OneFingerPicker(chosen).command(nil, for: self.strip), .setOneFinger(self.strip, nil),
                       "back to the default")
        XCTAssertNil(OneFingerPicker(chosen).command(.automatic, for: self.strip))
    }

    // MARK: - Gestures

    func testTheGestureSwitchesShowWhatIsStored() throws {
        var behaviour = try touchscreen(ilitek, UIFixtures.desk).behaviour
        behaviour.gestures.pinch = false
        let rows = GestureRow.rows(for: behaviour)
        XCTAssertEqual(rows.map(\.kind), GestureRow.Kind.allCases)
        XCTAssertEqual(rows.map(\.isOn), [true, false, true, true, true, true])
        XCTAssertTrue(rows.allSatisfy(\.isEnabled))
    }

    func testOnAOneFingerTouchscreenTheMultiFingerSwitchesAreOffAndDisabledAndLongPressStaysLive() throws {
        let behaviour = try touchscreen(strip, UIFixtures.desk).behaviour
        XCTAssertFalse(behaviour.multiFingerAvailable)
        XCTAssertTrue(behaviour.gestures.pinch, "stored on")
        let rows = GestureRow.rows(for: behaviour)
        for row in rows where row.kind != .longPress {
            XCTAssertFalse(row.isOn, "\(row.kind) shown off")
            XCTAssertFalse(row.isEnabled, "\(row.kind) disabled")
        }
        let longPress = try XCTUnwrap(rows.first { $0.kind == .longPress })
        XCTAssertTrue(longPress.isOn)
        XCTAssertTrue(longPress.isEnabled)
    }

    func testASwitchChangesItsGestureAndKeepsTheRestAsStored() throws {
        let behaviour = try touchscreen(strip, UIFixtures.desk).behaviour
        var expected = behaviour.gestures
        expected.longPress = false
        XCTAssertEqual(GestureRow.command(.longPress, on: false, for: strip, behaviour: behaviour),
                       .setGestures(strip, expected),
                       "the multi-finger gestures stored on stay stored on")
        var rotateOff = GestureOptions.all
        rotateOff.rotate = false
        XCTAssertEqual(GestureRow.command(.rotate, on: false, for: ilitek, behaviour: try touchscreen(ilitek, UIFixtures.desk).behaviour),
                       .setGestures(ilitek, rotateOff))
    }

    func testEachKindIsItsOwnGesture() {
        for kind in GestureRow.Kind.allCases {
            var options = GestureOptions.all
            options[keyPath: kind.keyPath] = false
            XCTAssertEqual(
                [options.twoFingerScroll, options.pinch, options.twoFingerTap, options.swipes, options.rotate, options.longPress]
                    .filter { !$0 }.count, 1, "\(kind)")
        }
        XCTAssertEqual(GestureRow.Kind.allCases.filter(\.needsSeveralFingers), [.twoFingerScroll, .pinch, .twoFingerTap, .swipes, .rotate])
    }

    // MARK: - Accidental touches

    func testTheEdgeMargin() {
        let rules = RejectionRules(palm: true, edgeMarginMM: 0)
        XCTAssertEqual(EdgeMargin.command(4, rules: rules, for: ilitek), .setRejection(ilitek, RejectionRules(palm: true, edgeMarginMM: 4)))
        XCTAssertNil(EdgeMargin.command(0, rules: rules, for: ilitek), "unchanged")
        XCTAssertEqual(EdgeMargin.command(4.4, rules: rules, for: ilitek),
                       .setRejection(ilitek, RejectionRules(palm: true, edgeMarginMM: 4)), "whole millimetres")
        XCTAssertEqual(EdgeMargin.command(12, rules: rules, for: ilitek),
                       .setRejection(ilitek, RejectionRules(palm: true, edgeMarginMM: 10)))
        XCTAssertEqual(EdgeMargin.range, 0...10)
    }

    func testPalmRejection() {
        let rules = RejectionRules(palm: true, edgeMarginMM: 3)
        XCTAssertEqual(PalmRejection.command(false, rules: rules, for: strip),
                       .setRejection(strip, RejectionRules(palm: false, edgeMarginMM: 3)))
    }

    // MARK: - Copy Settings From…

    func testCopyListsTheOtherTouchscreens() throws {
        let desk = UIFixtures.desk
        let sources = CopySource.sources(for: try touchscreen(ilitek, desk), in: desk)
        XCTAssertEqual(sources.map(\.id), [strip, oldPanel])
        XCTAssertEqual(sources.map(\.title), ["TouchScreen", "Old panel (not connected)"])
        XCTAssertEqual(sources.first?.command(to: ilitek), .copyBehaviour(from: strip, to: ilitek))
    }

    func testATouchscreenThatCannotBeToldApartIsNeverASource() throws {
        let twins = UIFixtures.snapshot(.identicalTwins)
        let sources = CopySource.sources(for: try touchscreen(strip, twins), in: twins)
        XCTAssertFalse(sources.contains { $0.id.rawValue.hasPrefix("#") })
        XCTAssertEqual(sources.map(\.id), [ilitek, oldPanel])
    }

    // MARK: - The warnings' own buttons

    func testTouchUpIsRecognised() {
        XCTAssertTrue(WarningActions.isTouchUp(bundleIdentifier: "de.schafe.Touch-Up-notarized", bundleURL: nil))
        XCTAssertTrue(WarningActions.isTouchUp(bundleIdentifier: "de.schafe.Touch-Up", bundleURL: nil))
        XCTAssertTrue(WarningActions.isTouchUp(
            bundleIdentifier: "com.example.other", bundleURL: URL(fileURLWithPath: "/Applications/Touch Up.app")))
        XCTAssertFalse(WarningActions.isTouchUp(
            bundleIdentifier: "com.crissmoldovan.tactile", bundleURL: URL(fileURLWithPath: "/Applications/Tactile.app")))
        XCTAssertFalse(WarningActions.isTouchUp(bundleIdentifier: nil, bundleURL: nil))
        XCTAssertTrue(WarningActions.keyboardSettingsAddresses.allSatisfy { URL(string: $0) != nil })
    }

    // MARK: - The first-run window

    /// The window names every touchscreen the model offers set-up to, in its order, and none while a
    /// set-up runs or set-up mode is on.
    func testTheFirstRunWindowFollowsTheOffer() throws {
        let first = UIFixtures.snapshot(.nothingPaired)
        XCTAssertEqual(first.offerSetUpTo, [ilitek, strip])
        XCTAssertEqual(FirstRunOffer(first),
                       FirstRunOffer(touchscreens: [ilitek, strip], names: ["ILITEK-TP", "TouchScreen"]))
        XCTAssertNil(FirstRunOffer(UIFixtures.desk))

        var running = first
        running.setUp = SetUpSnapshot(touchscreen: strip, touchscreenName: "TouchScreen", purpose: .test,
                                      step: .check(display: 5))
        XCTAssertNil(FirstRunOffer(running), "never over the set-up screens")
        var mode = first
        mode.setUpMode = SetUpModeSnapshot(stage: .choosing, displays: [], touchscreens: [], justSetUp: nil, notice: nil)
        XCTAssertNil(FirstRunOffer(mode), "nor over set-up mode")

        var gone = first
        gone.touchscreens.removeAll { $0.id == ilitek }
        XCTAssertEqual(FirstRunOffer(gone), FirstRunOffer(touchscreens: [strip], names: ["TouchScreen"]),
                       "a touchscreen that isn't there is left out")
        gone.touchscreens.removeAll { $0.id == strip }
        XCTAssertNil(FirstRunOffer(gone), "none left")
    }

    /// Set Up… must never offer a set-up that can't run: with Accessibility missing, Settings asks
    /// first; with Tactile off, nothing is offered; a touchscreen that can't be set up is left out;
    /// once all is fine, the offer is shown.
    func testTheFirstRunWindowNeverOffersASetUpThatCannotRun() throws {
        var snapshot = UIFixtures.snapshot(.nothingPaired)
        XCTAssertNotNil(FirstRunOffer(snapshot))
        snapshot.warnings = [.accessibilityMissing]
        XCTAssertNil(FirstRunOffer(snapshot))
        XCTAssertTrue(shouldOpenSettingsAtLaunch(snapshot), "Settings asks instead")
        snapshot.warnings = []
        snapshot.isOn = false
        XCTAssertNil(FirstRunOffer(snapshot))
        snapshot.isOn = true
        XCTAssertEqual(FirstRunOffer(snapshot)?.touchscreens, [ilitek, strip])
        // Whether the mode can begin now is the model's to say: it keeps its offer through a display
        // reconfiguration while `canBeSetUp` is false for that moment.
        for index in snapshot.touchscreens.indices { snapshot.touchscreens[index].canBeSetUp = false }
        XCTAssertEqual(FirstRunOffer(snapshot)?.touchscreens, [ilitek, strip], "kept through a reconfiguration")
        if let index = snapshot.touchscreens.firstIndex(where: { $0.id == strip }) {
            snapshot.touchscreens[index].notes = [.oneFingerOnly, .macOSMayAlsoRespond]
        }
        XCTAssertEqual(FirstRunOffer(snapshot), FirstRunOffer(touchscreens: [ilitek], names: ["ILITEK-TP"]),
                       "one macOS also handles is left out")
        snapshot.offerSetUpTo = []
        XCTAssertNil(FirstRunOffer(snapshot), "no offer from the model, no window")
    }

    /// Set Up… begins set-up mode, for every touchscreen; Not Now declines each one named.
    func testFirstRunButtons() {
        let one = FirstRunOffer(touchscreens: [ilitek], names: ["ILITEK-TP"])
        XCTAssertEqual(one.setUpCommand, .beginSetUpMode)
        XCTAssertEqual(one.notNowCommands, [.declineSetUp(ilitek)])
        let both = FirstRunOffer(touchscreens: [ilitek, strip], names: ["ILITEK-TP", "TouchScreen"])
        XCTAssertEqual(both.setUpCommand, .beginSetUpMode)
        XCTAssertEqual(both.notNowCommands, [.declineSetUp(ilitek), .declineSetUp(strip)])
    }
}
