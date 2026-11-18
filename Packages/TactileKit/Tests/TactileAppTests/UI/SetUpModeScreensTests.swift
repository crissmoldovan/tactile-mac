import CoreGraphics
import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// Set-up mode's overview, worked out from the snapshot alone: which card each display gets in each
/// stage, what its buttons send, where the session card goes and what it says, and Back for Cancel in
/// the mode's flows.
@MainActor
final class SetUpModeScreensTests: XCTestCase {
    private struct NotTheOverview: Error {
        var role: SetUpScreenRole
    }

    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip

    private func id(_ name: String, _ snapshot: AppSnapshot) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: snapshot))
    }

    private func overview(_ name: String, _ snapshot: AppSnapshot) throws -> SetUpModeScreen {
        let display = try id(name, snapshot)
        let screen = try XCTUnwrap(SetUpScreens.plan(snapshot).first { $0.displayID == display })
        guard case .overview(let overview) = screen.role else { throw NotTheOverview(role: screen.role) }
        return overview
    }

    private func card(_ name: String, _ snapshot: AppSnapshot) throws -> SetUpModeCard {
        try XCTUnwrap(try overview(name, snapshot).card, name)
    }

    private func modeModel(_ variant: PreviewModel.Variant = .desk) -> PreviewModel {
        let model = PreviewModel(variant)
        model.perform(.beginSetUpMode)
        return model
    }

    // MARK: - Every display, while every display offers itself

    /// A screen on every display, in the snapshot's order: a card on each candidate (every display
    /// but the built-in one), the session card on the built-in display, which takes the keyboard.
    /// Every one has buttons, takes the mouse, and is not a flow's.
    func testTheOverviewHasAScreenOnEveryDisplay() throws {
        let snapshot = modeModel().snapshot
        let plan = SetUpScreens.plan(snapshot)
        XCTAssertEqual(plan.map(\.displayID), snapshot.displays.map(\.id))
        let builtIn = try id("Built-in Retina Display", snapshot)
        for screen in plan {
            guard case .overview(let overview) = screen.role else { return XCTFail("\(screen.displayID)") }
            XCTAssertEqual(overview.card == nil, screen.displayID == builtIn, "a card on each candidate")
            XCTAssertEqual(overview.session != nil, screen.displayID == builtIn, "the session card on the built-in one")
            XCTAssertEqual(screen.takesKeyboard, screen.displayID == builtIn)
            XCTAssertTrue(screen.hasControls)
            XCTAssertTrue(screen.backdropTakesMouse, "nothing in the overview is click-through")
            XCTAssertEqual(screen.placement, .centre)
            XCTAssertNil(screen.progress)
            XCTAssertNil(screen.keyboardMoment)
            XCTAssertEqual(screen.dimming, 0.62, accuracy: 0.001)
        }
    }

    func testAFreeDisplaysCard() throws {
        let snapshot = modeModel().snapshot
        let lg = try id("LG HDR 4K", snapshot)
        let card = try card("LG HDR 4K", snapshot)
        XCTAssertEqual(card.name, "LG HDR 4K")
        XCTAssertFalse(card.detail.isEmpty, "its detail, to tell it apart")
        XCTAssertEqual(card.state, .free)
        XCTAssertEqual(card.moment, .offering)
        XCTAssertEqual(card.stateLine, "Set up a touchscreen on this screen")
        XCTAssertEqual(card.buttons, [.thisOne(display: lg)])
        XCTAssertEqual(card.prominentButton, .thisOne(display: lg))
        XCTAssertEqual(card.buttons.map(\.command), [.setUpChoose(displayID: lg)])
    }

    func testADisplayWithATouchscreen() throws {
        let snapshot = modeModel().snapshot
        let hdmi = try id("HDMI", snapshot)
        let card = try card("HDMI", snapshot)
        XCTAssertEqual(card.state, .setUp(touchscreen: ilitek, name: "ILITEK-TP", isJustSetUp: false, canBeTested: true))
        XCTAssertEqual(card.stateLine, "✓ ILITEK-TP is set up here")
        XCTAssertEqual(card.buttons, [.test(ilitek), .setUpAgainHere(display: hdmi)])
        XCTAssertEqual(card.buttons.map(\.command), [.beginSetUp(ilitek, .test), .setUpChoose(displayID: hdmi)])
        XCTAssertNil(card.prominentButton)
        XCTAssertFalse(card.isJustSetUp)
    }

    /// The last touchscreen Done in this session: its card says where, and is marked.
    func testTheDisplayJustSetUp() throws {
        let model = modeModel()
        let fhd = try id("12.3FHD", model.snapshot)
        model.perform(.setUpChoose(displayID: fhd))
        model.simulate(.touch(strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: nil))
        model.perform(.setUpDone)
        let card = try card("12.3FHD", model.snapshot)
        XCTAssertTrue(card.isJustSetUp)
        XCTAssertEqual(card.stateLine, "✓ TouchScreen is set up on 12.3FHD")
        XCTAssertFalse(try self.card("HDMI", model.snapshot).isJustSetUp, "the others are only set up")
        XCTAssertEqual(try self.card("HDMI", model.snapshot).stateLine, "✓ ILITEK-TP is set up here")
    }

    /// Test only where it can run: a card whose touchscreen can't be set up, or isn't connected,
    /// offers Set Up Again Here alone.
    func testTestIsOfferedOnlyWhereItCanRun() throws {
        var snapshot = modeModel().snapshot
        let hdmi = try id("HDMI", snapshot)
        let index = try XCTUnwrap(snapshot.setUpMode?.touchscreens.firstIndex { $0.id == ilitek })
        snapshot.setUpMode?.touchscreens[index].state = .cannotBeSetUp
        XCTAssertEqual(try card("HDMI", snapshot).buttons, [.setUpAgainHere(display: hdmi)])
        snapshot.setUpMode?.touchscreens.remove(at: index)
        XCTAssertEqual(try card("HDMI", snapshot).buttons, [.setUpAgainHere(display: hdmi)], "not connected")
    }

    // MARK: - Waiting for a touch

    /// The chosen display is bright, says "Now touch this screen" and offers Back, below its
    /// message; every other card is dimmed deeply, says which display waits, and keeps its button
    /// (not Test), so another display can be chosen.
    func testWaitingForATouch() throws {
        let model = modeModel()
        let lg = try id("LG HDR 4K", model.snapshot), hdmi = try id("HDMI", model.snapshot)
        model.perform(.setUpChoose(displayID: lg))
        let snapshot = model.snapshot
        let plan = SetUpScreens.plan(snapshot)

        let chosen = try card("LG HDR 4K", snapshot)
        XCTAssertEqual(chosen.moment, .touchHere)
        XCTAssertEqual(chosen.buttons, [.back])
        XCTAssertEqual(chosen.buttons.map(\.command), [.setUpBack])
        XCTAssertNil(chosen.prominentButton)
        let chosenScreen = try XCTUnwrap(plan.first { $0.displayID == lg })
        XCTAssertEqual(chosenScreen.dimming, 0)
        XCTAssertEqual(chosenScreen.placement, .belowCentre)
        XCTAssertTrue(chosenScreen.role.isTouched, "its buttons say they answer the mouse")
        XCTAssertEqual(chosenScreen.role.backdropScheme, .light)

        let other = try card("HDMI", snapshot)
        XCTAssertEqual(other.moment, .waitingElsewhere(displayName: "LG HDR 4K"))
        XCTAssertEqual(other.buttons, [.setUpAgainHere(display: hdmi)], "no Test while a display waits")
        XCTAssertNil(other.prominentButton)
        let free = try card("Display", snapshot)
        XCTAssertEqual(free.buttons, [.thisOne(display: try id("Display", snapshot))])
        XCTAssertNil(free.prominentButton, "dimmed: nothing drawn as the thing to do")
        for screen in plan where screen.displayID != lg {
            XCTAssertEqual(screen.dimming, 0.82, accuracy: 0.001, "\(screen.displayID)")
            XCTAssertEqual(screen.placement, .centre)
        }
        XCTAssertTrue(try XCTUnwrap(plan.first { $0.takesKeyboard }).role.session != nil, "the session card keeps it")
    }

    // MARK: - Touched first

    /// Every card says which touchscreen was touched, above its button; Test goes; the session card
    /// offers Back.
    func testTouchedFirst() throws {
        let model = modeModel()
        model.simulate(.touch(strip))
        let snapshot = model.snapshot
        let hdmi = try id("HDMI", snapshot), lg = try id("LG HDR 4K", snapshot)
        for name in ["HDMI", "LG HDR 4K", "Display", "12.3FHD"] {
            XCTAssertEqual(try card(name, snapshot).touchedFirst, "TouchScreen", name)
            XCTAssertEqual(try card(name, snapshot).moment, .offering, name)
        }
        XCTAssertEqual(try card("HDMI", snapshot).buttons, [.setUpAgainHere(display: hdmi)])
        XCTAssertEqual(try card("HDMI", snapshot).prominentButton, .setUpAgainHere(display: hdmi))
        XCTAssertEqual(try card("LG HDR 4K", snapshot).buttons, [.thisOne(display: lg)])
        XCTAssertEqual(try card("LG HDR 4K", snapshot).prominentButton, .thisOne(display: lg))
        let session = try XCTUnwrap(try overview("Built-in Retina Display", snapshot).session)
        XCTAssertEqual(session.touchedFirst, "TouchScreen")
    }

    // MARK: - The session card

    /// One line per connected touchscreen, as the model words them, and the latest notice.
    func testTheSessionCard() throws {
        let model = modeModel()
        var session = try XCTUnwrap(try overview("Built-in Retina Display", model.snapshot).session)
        XCTAssertEqual(session.lines.map(\.name), ["ILITEK-TP", "TouchScreen"])
        XCTAssertEqual(session.lines.map(\.state), [.setUp(displayName: "HDMI"), .setUp(displayName: "12.3FHD")])
        XCTAssertNil(session.notice)
        XCTAssertNil(session.touchedFirst)

        let lg = try id("LG HDR 4K", model.snapshot)
        model.perform(.setUpChoose(displayID: lg))
        model.simulate(.displayConnected(lg, false))
        session = try XCTUnwrap(try overview("Built-in Retina Display", model.snapshot).session)
        XCTAssertEqual(session.notice, .displayGone(name: "LG HDR 4K"))
        XCTAssertNil(try overview("Built-in Retina Display", model.snapshot).card)
        XCTAssertFalse(SetUpScreens.plan(model.snapshot).contains { $0.displayID == lg }, "its screen is gone")
    }

    /// A touchscreen that can't be set up: its line says why, and its touch is a notice.
    func testATouchscreenThatCannotBeSetUp() throws {
        let model = modeModel(.identicalTwins)
        let twin = try XCTUnwrap(model.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        model.simulate(.touch(twin.id))
        let session = try XCTUnwrap(try overview("Built-in Retina Display", model.snapshot).session)
        let line = try XCTUnwrap(session.lines.first { $0.id == twin.id })
        XCTAssertEqual(line.state, .cannotBeSetUp)
        XCTAssertEqual(line.reason, Wording.note(.cannotBeToldApart))
        XCTAssertEqual(session.notice, .cannotBeSetUp(touchscreen: twin.id, name: "ILITEK-TP"))
        XCTAssertEqual(model.snapshot.setUpMode?.stage, .choosing, "not an answer")
    }

    /// On the built-in display, never a candidate; with none (the lid closed), beside the first
    /// candidate's card, in the snapshot's order; the keyboard goes with it.
    func testWhereTheSessionCardGoes() throws {
        let model = modeModel()
        XCTAssertEqual(SetUpScreens.sessionDisplay(try XCTUnwrap(model.snapshot.setUpMode), in: model.snapshot),
                       try id("Built-in Retina Display", model.snapshot))
        model.simulate(.displayConnected(1, false))
        let snapshot = model.snapshot
        let first = try XCTUnwrap(snapshot.setUpMode?.displays.first)
        XCTAssertEqual(first.name, "Display")
        XCTAssertEqual(SetUpScreens.sessionDisplay(try XCTUnwrap(snapshot.setUpMode), in: snapshot), first.id)
        let screen = try XCTUnwrap(SetUpScreens.plan(snapshot).first { $0.displayID == first.id })
        guard case .overview(let overview) = screen.role else { return XCTFail("overview") }
        XCTAssertNotNil(overview.card, "its own card")
        XCTAssertNotNil(overview.session, "and the session card beside it")
        XCTAssertTrue(screen.takesKeyboard)
        XCTAssertEqual(SetUpScreens.plan(snapshot).filter(\.takesKeyboard).count, 1)

        var empty = snapshot
        empty.displays = []
        XCTAssertNil(SetUpScreens.sessionDisplay(try XCTUnwrap(empty.setUpMode), in: empty))
    }

    /// A screen shared by the built-in display and a candidate (mirrored): the candidate's card is
    /// shown, with the session card beside it, and the keyboard.
    func testTheSessionCardSurvivesAMirror() throws {
        let snapshot = modeModel().snapshot
        let builtIn = try id("Built-in Retina Display", snapshot), hdmi = try id("HDMI", snapshot)
        let placed = SetUpScreens.placed(SetUpScreens.plan(snapshot), screen: { $0 == builtIn ? hdmi : $0 })
        let onHDMI = try XCTUnwrap(placed.screens.first { $0.screenID == hdmi }).screen
        guard case .overview(let overview) = onHDMI.role else { return XCTFail("overview") }
        XCTAssertEqual(onHDMI.displayID, hdmi)
        XCTAssertNotNil(overview.card)
        XCTAssertNotNil(overview.session)
        XCTAssertTrue(onHDMI.hasControls)
        XCTAssertTrue(onHDMI.takesKeyboard)
        XCTAssertFalse(placed.screens.contains { $0.screenID == builtIn })
    }

    /// The chosen display mirrored on another candidate's screen: it is shown, bright.
    func testTheChosenDisplayWinsAMirror() throws {
        let model = modeModel()
        let hdmi = try id("HDMI", model.snapshot), display = try id("Display", model.snapshot)
        model.perform(.setUpChoose(displayID: display))
        let placed = SetUpScreens.placed(SetUpScreens.plan(model.snapshot), screen: { $0 == display ? hdmi : $0 })
        let onHDMI = try XCTUnwrap(placed.screens.first { $0.screenID == hdmi }).screen
        XCTAssertEqual(onHDMI.displayID, display)
        guard case .overview(let overview) = onHDMI.role else { return XCTFail("overview") }
        XCTAssertEqual(overview.card?.moment, .touchHere)
    }

    /// A display that is neither a candidate nor the session card's (one the model doesn't list):
    /// dimmed, no buttons, still swallowing the mouse.
    func testADisplayWithNoCard() throws {
        var snapshot = modeModel().snapshot
        let lg = try id("LG HDR 4K", snapshot)
        snapshot.setUpMode?.displays.removeAll { $0.id == lg }
        let screen = try XCTUnwrap(SetUpScreens.plan(snapshot).first { $0.displayID == lg })
        XCTAssertFalse(screen.hasControls)
        XCTAssertTrue(screen.backdropTakesMouse)
        XCTAssertEqual(screen.dimming, 0.82, accuracy: 0.001)
        XCTAssertTrue(screen.messageAtEdge)
    }

    /// A stage the cards can't show is drawn as choosing: a display chosen that has no card, or a
    /// flow said to run with no flow in the snapshot.
    func testAStageTheCardsCannotShowIsDrawnAsChoosing() throws {
        let choosing = SetUpScreens.plan(modeModel().snapshot)
        var snapshot = modeModel().snapshot
        snapshot.setUpMode?.stage = .running
        XCTAssertEqual(SetUpScreens.plan(snapshot), choosing)
        snapshot.setUpMode?.stage = .waitingForTouch(display: 99)
        XCTAssertEqual(SetUpScreens.plan(snapshot), choosing)
    }

    // MARK: - A flow in the mode

    /// In the mode, a flow's Cancel reads Back and returns to the overview, and Esc leaves the whole
    /// mode; outside it (Calibrate or Test from a pane), Cancel, as before.
    func testBackInTheModeCancelOutside() throws {
        let model = modeModel()
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model.snapshot)))
        model.simulate(.touch(ilitek))
        let inMode = SetUpScreens.plan(model.snapshot)
        XCTAssertFalse(inMode.isEmpty)
        for screen in inMode {
            XCTAssertTrue(screen.inSetUpMode, "\(screen.displayID)")
            XCTAssertEqual(screen.escLine, "Press Esc to leave set-up.")
            XCTAssertEqual(screen.keyboardMoment, .corners)
        }
        XCTAssertEqual(SetUpModeButton.back.command, .setUpBack)
        XCTAssertEqual(SetUpModeButton.finish.command, .cancelSetUp, "Finish and Esc leave the mode")

        let pane = PreviewModel(.desk)
        pane.perform(.beginSetUp(ilitek, .calibrate))
        for screen in SetUpScreens.plan(pane.snapshot) {
            XCTAssertFalse(screen.inSetUpMode, "\(screen.displayID)")
            XCTAssertEqual(screen.escLine, "Press Esc to cancel.")
        }
        // The overview says the same as the mode's flows.
        XCTAssertTrue(SetUpScreens.plan(modeModel().snapshot).allSatisfy { $0.escLine == "Press Esc to leave set-up." })
    }

    /// Review Focus 4 in the mode: HDMI, paired with the ILITEK, chosen again (Set Up Again Here)
    /// and touched with the strip. Every touchscreen is held while the mode is on, so no other
    /// touchscreen's taps can land on HDMI's buttons: at the corners, the size and the check, HDMI
    /// has its buttons and takes the keyboard, and its backdrop swallows the mouse where it hides
    /// what is beneath (corners and size). Every display has its buttons while the mode is on.
    func testADisplayTakenFromAnotherTouchscreenKeepsItsButtons() throws {
        let model = modeModel()
        let hdmi = try id("HDMI", model.snapshot)
        model.perform(.setUpChoose(displayID: hdmi))
        model.simulate(.touch(strip))
        XCTAssertEqual(model.snapshot.setUp?.touchscreen, strip)
        func onHDMI() throws -> SetUpScreen {
            let plan = SetUpScreens.plan(model.snapshot)
            XCTAssertTrue(plan.allSatisfy(\.hasControls), "every display, while the mode is on")
            let placed = SetUpScreens.placed(plan, screen: { $0 })
            XCTAssertEqual(placed.screens.filter(\.screen.takesKeyboard).map(\.screenID), [hdmi], "as the overlay places it")
            return try XCTUnwrap(plan.first { $0.displayID == hdmi })
        }

        var screen = try onHDMI()
        guard case .corners = screen.role else { return XCTFail("corners: \(screen.role)") }
        XCTAssertTrue(screen.hasControls, "corners")
        XCTAssertTrue(screen.takesKeyboard, "corners")
        XCTAssertTrue(screen.backdropTakesMouse, "corners: opaque, never click-through")

        for _ in 0..<4 { model.touchSetUp() }
        screen = try onHDMI()
        guard case .size = screen.role else { return XCTFail("size: \(screen.role)") }
        XCTAssertTrue(screen.hasControls, "size: Continue must be there")
        XCTAssertTrue(screen.takesKeyboard, "size: Return reaches Continue")
        XCTAssertTrue(screen.backdropTakesMouse, "size")

        model.perform(.setUpConfirmSize(inches: nil))
        screen = try onHDMI()
        guard case .check = screen.role else { return XCTFail("check: \(screen.role)") }
        XCTAssertTrue(screen.hasControls, "check: Done must be there")
        XCTAssertTrue(screen.takesKeyboard, "check")
        XCTAssertFalse(screen.backdropTakesMouse, "the check is clear, as always")

        model.perform(.setUpDone)
        XCTAssertEqual(model.snapshot.setUpMode?.displays.first { $0.id == hdmi }?.touchscreen, strip)
    }

    /// Outside the mode nothing changes: a calibration of the ILITEK leaves the strip's display
    /// without buttons, click-through.
    func testOutsideTheModeTheOtherTouchscreensDisplayStillHasNoButtons() throws {
        let model = PreviewModel(.desk)
        model.perform(.beginSetUp(ilitek, .calibrate))
        let fhd = try XCTUnwrap(SetUpScreens.plan(model.snapshot).first { $0.displayID == (try? id("12.3FHD", model.snapshot)) })
        XCTAssertFalse(fhd.hasControls)
        XCTAssertFalse(fhd.backdropTakesMouse)
    }

    /// The hint beside a card's buttons says what answers them. Outside the mode Esc is Cancel's,
    /// and Return the default button's: "the mouse or the keyboard". In the mode, Back answers no
    /// key (Esc leaves the whole mode): a card with Back alone says "the mouse"; the size and check
    /// cards, with Continue and Done, still say the keyboard too.
    func testWhatTheMouseHintSays() throws {
        let mode = modeModel()
        let lg = try id("LG HDR 4K", mode.snapshot)
        mode.perform(.setUpChoose(displayID: lg))
        let chosen = try XCTUnwrap(SetUpScreens.plan(mode.snapshot).first { $0.displayID == lg })
        XCTAssertEqual(chosen.mouseHint, "Use the mouse for this button.", "Back alone, on the chosen display")
        mode.simulate(.touch(ilitek))
        func hint() throws -> String { try XCTUnwrap(SetUpScreens.plan(mode.snapshot).first { $0.displayID == lg }).mouseHint }
        XCTAssertEqual(try hint(), "Use the mouse for this button.", "corners in the mode: Back alone")
        for _ in 0..<4 { mode.touchSetUp() }
        XCTAssertEqual(try hint(), "Use the mouse or the keyboard for these buttons.", "size: Return is Continue")
        mode.perform(.setUpConfirmSize(inches: nil))
        XCTAssertEqual(try hint(), "Use the mouse or the keyboard for these buttons.", "check: Return is Done")

        let pane = PreviewModel(.desk)
        pane.perform(.beginSetUp(ilitek, .calibrate))
        let hdmi = try id("HDMI", pane.snapshot)
        XCTAssertEqual(try XCTUnwrap(SetUpScreens.plan(pane.snapshot).first { $0.displayID == hdmi }).mouseHint,
                       "Use the mouse or the keyboard for these buttons.", "outside the mode: Esc is Cancel's")
    }

    /// While another display waits for a touch, a card is dimmed with its display, the just-set-up
    /// card's green border too; the chosen one and every card otherwise are drawn in full.
    func testACardIsDimmedWhileAnotherDisplayWaits() throws {
        let model = modeModel()
        let fhd = try id("12.3FHD", model.snapshot)
        model.perform(.setUpChoose(displayID: fhd))
        model.simulate(.touch(strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: nil))
        model.perform(.setUpDone)
        XCTAssertEqual(try card("12.3FHD", model.snapshot).opacity, 1)
        XCTAssertEqual(try card("LG HDR 4K", model.snapshot).opacity, 1)
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model.snapshot)))
        let justSetUp = try card("12.3FHD", model.snapshot)
        XCTAssertTrue(justSetUp.isJustSetUp)
        XCTAssertLessThan(justSetUp.opacity, 0.7, "the green border quietened too")
        XCTAssertEqual(try card("HDMI", model.snapshot).opacity, justSetUp.opacity)
        XCTAssertEqual(try card("LG HDR 4K", model.snapshot).opacity, 1, "the chosen display's own")
        model.simulate(.touch(ilitek))
        model.perform(.setUpBack)
        XCTAssertEqual(try card("12.3FHD", model.snapshot).opacity, 1, "back to choosing")
    }

    /// No built-in display, and the first candidate chosen: it carries the session card too. Its
    /// "Now touch this screen" moves into a card of its own beside the session card, both in the
    /// middle, so a long session card can't cover the message on a short display (the strip's 600
    /// pt). Chosen anywhere else, the message stays on the backdrop with Back below the middle.
    func testTheChosenDisplayWithTheSessionCardSaysItInACard() throws {
        let model = modeModel()
        model.simulate(.displayConnected(1, false))
        let display = try id("Display", model.snapshot), hdmi = try id("HDMI", model.snapshot)
        model.perform(.setUpChoose(displayID: display))
        var screen = try XCTUnwrap(SetUpScreens.plan(model.snapshot).first { $0.displayID == display })
        guard case .overview(var overview) = screen.role else { return XCTFail("overview") }
        XCTAssertEqual(overview.card?.moment, .touchHere)
        XCTAssertNotNil(overview.session)
        XCTAssertTrue(overview.saysTouchHereInACard)
        XCTAssertEqual(screen.placement, .centre)
        XCTAssertTrue(screen.takesKeyboard)

        model.perform(.setUpChoose(displayID: hdmi))
        screen = try XCTUnwrap(SetUpScreens.plan(model.snapshot).first { $0.displayID == hdmi })
        guard case .overview(let chosen) = screen.role else { return XCTFail("overview") }
        XCTAssertFalse(chosen.saysTouchHereInACard, "the session card is on Display")
        XCTAssertEqual(screen.placement, .belowCentre)
        screen = try XCTUnwrap(SetUpScreens.plan(model.snapshot).first { $0.displayID == display })
        guard case .overview(let other) = screen.role else { return XCTFail("overview") }
        XCTAssertFalse(other.saysTouchHereInACard)
        XCTAssertEqual(screen.placement, .centre)

        // The session card brought to the chosen display by a mirror: the same.
        let mirrored = modeModel()
        let builtIn = try id("Built-in Retina Display", mirrored.snapshot), lg = try id("LG HDR 4K", mirrored.snapshot)
        mirrored.perform(.setUpChoose(displayID: lg))
        let placed = SetUpScreens.placed(SetUpScreens.plan(mirrored.snapshot), screen: { $0 == builtIn ? lg : $0 })
        let onLG = try XCTUnwrap(placed.screens.first { $0.screenID == lg }).screen
        guard case .overview(let merged) = onLG.role else { return XCTFail("overview") }
        XCTAssertTrue(merged.saysTouchHereInACard)
        XCTAssertEqual(onLG.placement, .centre)
        XCTAssertTrue(onLG.takesKeyboard)
        overview.session = nil
        XCTAssertFalse(overview.saysTouchHereInACard)
        XCTAssertEqual(overview.placement, .belowCentre)
    }

    /// A flow's step moves the keyboard; the overview's stages don't.
    func testTheKeyboardMoment() throws {
        let model = modeModel()
        func moment() -> SetUpStepName?? {
            SetUpScreens.plan(model.snapshot).first(where: \.takesKeyboard).map(\.keyboardMoment)
        }
        XCTAssertEqual(moment(), .some(nil), "the overview")
        model.perform(.setUpChoose(displayID: try id("LG HDR 4K", model.snapshot)))
        XCTAssertEqual(moment(), .some(nil), "still the overview")
        model.simulate(.touch(ilitek))
        XCTAssertEqual(moment(), .some(.corners))
    }
}
