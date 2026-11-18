import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import TactileScreens
import XCTest

@testable import TactileApp

/// What each display shows while a flow runs (corners, size, check), in set-up mode or outside it,
/// worked out from the snapshot alone: where the target is, the size card's choices, which screens
/// have buttons, which takes the keyboard, and where the buttons go. Set-up mode's overview is
/// `SetUpModeScreensTests`'.
@MainActor
final class SetUpScreensTests: XCTestCase {
    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private var now: TimeInterval = 500

    private func model(_ variant: PreviewModel.Variant = .desk) -> PreviewModel {
        PreviewModel(variant, clock: { [unowned self] in self.now })
    }

    private func id(_ name: String, _ snapshot: AppSnapshot) throws -> UInt32 {
        try XCTUnwrap(UIFixtures.displayID(named: name, in: snapshot))
    }

    private func screen(_ name: String, in plan: [SetUpScreen], _ snapshot: AppSnapshot) throws -> SetUpScreen {
        let display = try id(name, snapshot)
        return try XCTUnwrap(plan.first { $0.displayID == display })
    }

    /// Corners and size are dark with a light card, as mockup 8 draws them, whatever the Mac's
    /// appearance; dimmed displays have dark cards; the check is the person's own screen, with a card
    /// in the Mac's appearance. In set-up mode's overview, the chosen display is bright with a light
    /// card, and every other display dark with dark cards.
    func testEachScreensAppearance() {
        let corners = SetUpScreenRole.corners(target: .zero, index: 0, problem: nil)
        let size = SetUpScreenRole.size(SetUpSizeChoices(displayReports: 27, touchscreenReports: nil, current: nil))
        for role in [corners, size] {
            XCTAssertEqual(role.backdropScheme, .dark, "\(role)")
            XCTAssertEqual(role.cardScheme, .light, "\(role): a card that stands out")
        }
        XCTAssertEqual(SetUpScreenRole.elsewhere(displayName: "HDMI").backdropScheme, .dark)
        XCTAssertEqual(SetUpScreenRole.elsewhere(displayName: "HDMI").cardScheme, .dark)
        XCTAssertNil(SetUpScreenRole.check(canRedo: true).backdropScheme)
        XCTAssertNil(SetUpScreenRole.check(canRedo: true).cardScheme)

        func card(_ moment: SetUpModeCard.Moment) -> SetUpScreenRole {
            .overview(SetUpModeScreen(
                card: SetUpModeCard(displayID: 2, name: "HDMI", detail: "", state: .free, moment: moment, touchedFirst: nil),
                session: nil, aDisplayWaits: moment != .offering))
        }
        XCTAssertEqual(card(.touchHere).backdropScheme, .light, "the chosen display: bright")
        XCTAssertEqual(card(.touchHere).cardScheme, .light)
        for role in [card(.offering), card(.waitingElsewhere(displayName: "LG HDR 4K")),
                     .overview(SetUpModeScreen(card: nil, session: nil, aDisplayWaits: false))] {
            XCTAssertEqual(role.backdropScheme, .dark, "\(role)")
            XCTAssertEqual(role.cardScheme, .dark, "\(role)")
        }
    }

    /// The other touchscreen's display stays usable: lightly dimmed, its line at an edge, while the
    /// displays that have buttons are dimmed more.
    func testTheOtherTouchscreensDisplayIsOnlyLightlyDimmed() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let snapshot = model.snapshot
        let plan = SetUpScreens.plan(snapshot)
        let fhd = try screen("12.3FHD", in: plan, snapshot)
        let builtIn = try screen("Built-in Retina Display", in: plan, snapshot)
        let lg = try screen("LG HDR 4K", in: plan, snapshot)
        XCTAssertEqual(fhd.role, builtIn.role, "both elsewhere")
        XCTAssertGreaterThan(fhd.dimming, 0)
        XCTAssertLessThanOrEqual(fhd.dimming, 0.3)
        XCTAssertGreaterThan(builtIn.dimming, 0.5)
        XCTAssertGreaterThan(lg.dimming, 0.5)
        XCTAssertTrue(fhd.messageAtEdge)
        XCTAssertFalse(builtIn.messageAtEdge)
        XCTAssertEqual(try screen("HDMI", in: plan, snapshot).dimming, 0, "the corners' own background")
    }

    // MARK: - What the overlay does with a snapshot

    func testEscIsTheCancelKey() {
        XCTAssertTrue(SetUpOverlay.isCancelKey(53, modifiers: []))
        XCTAssertTrue(SetUpOverlay.isCancelKey(53, modifiers: [.shift]), "Shift doesn't matter")
        XCTAssertTrue(SetUpOverlay.isCancelKey(53, modifiers: [.capsLock]), "nor Caps Lock")
        XCTAssertTrue(SetUpOverlay.isCancelKey(53, modifiers: [.shift, .capsLock, .numericPad, .function]),
                      "nor flags no one holds down for Esc")
        XCTAssertFalse(SetUpOverlay.isCancelKey(53, modifiers: [.command]), "⌘-Esc is another app's")
        XCTAssertFalse(SetUpOverlay.isCancelKey(53, modifiers: [.option]))
        XCTAssertFalse(SetUpOverlay.isCancelKey(53, modifiers: [.control]))
        XCTAssertFalse(SetUpOverlay.isCancelKey(53, modifiers: [.option, .command]), "⌥⌘-Esc is Force Quit")
        XCTAssertFalse(SetUpOverlay.isCancelKey(36, modifiers: []), "Return")
        XCTAssertFalse(SetUpOverlay.isCancelKey(48, modifiers: []), "Tab")
    }

    /// The screens come down only when no set-up runs. A set-up with no displays for a moment (the
    /// displays reconfiguring) keeps the screens as they are, and the text typed in them.
    func testTheScreensStayWhileASetUpRunsWithNoDisplays() {
        let model = model()
        XCTAssertEqual(SetUpPresentation(model.snapshot).change, .takeDown)
        model.perform(.beginSetUp(ilitek, .calibrate))
        var snapshot = model.snapshot
        XCTAssertEqual(SetUpPresentation(snapshot).change, .show)
        snapshot.displays = []
        let reconfiguring = SetUpPresentation(snapshot)
        XCTAssertTrue(reconfiguring.isRunning)
        XCTAssertEqual(reconfiguring.plan, [])
        XCTAssertEqual(reconfiguring.change, .keep)

        // Set-up mode, between flows, likewise.
        let mode = self.model()
        mode.perform(.beginSetUpMode)
        var overview = mode.snapshot
        XCTAssertEqual(SetUpPresentation(overview).change, .show)
        overview.displays = []
        XCTAssertEqual(SetUpPresentation(overview).change, .keep)
        mode.perform(.cancelSetUp)
        XCTAssertEqual(SetUpPresentation(mode.snapshot).change, .takeDown)
    }

    func testTheTypeFitsTheDisplay() {
        let strip = SetUpMetrics(displaySize: CGSize(width: 1600, height: 600))
        let hdmi = SetUpMetrics(displaySize: CGSize(width: 2560, height: 1440))
        let tiny = SetUpMetrics(displaySize: CGSize(width: 320, height: 240))
        XCTAssertEqual(strip.title, 56, accuracy: 0.01)
        XCTAssertEqual(hdmi.title, 89.6, accuracy: 0.01)
        XCTAssertEqual(tiny.title, 32, "never smaller")
        XCTAssertEqual(SetUpMetrics(displaySize: CGSize(width: 6016, height: 3384)).title, 96, "never larger")
        XCTAssertEqual(strip.cardScale, 1)
        XCTAssertEqual(hdmi.cardScale, 1.4, accuracy: 0.01)
        XCTAssertEqual(SetUpMetrics(displaySize: CGSize(width: 6016, height: 3384)).cardScale, 1.5)
    }

    func testNothingWithoutASetUp() {
        XCTAssertEqual(SetUpScreens.plan(UIFixtures.desk), [])
    }

    // MARK: - Another touchscreen's display

    func testTheOtherTouchscreensDisplayHasNoButtons() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let plan = SetUpScreens.plan(model.snapshot)
        let fhd = try screen("12.3FHD", in: plan, model.snapshot)
        XCTAssertFalse(fhd.hasControls, "the strip's taps there must never land on a button")
        XCTAssertEqual(plan.filter { !$0.hasControls }.map(\.displayID), [fhd.displayID])
    }

    // MARK: - Corners, size, check

    func testCornersShowOneTargetOnItsDisplay() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        model.touchSetUp(.tooManyFingers)
        let snapshot = model.snapshot
        let plan = SetUpScreens.plan(snapshot)
        let hdmi = try screen("HDMI", in: plan, snapshot)
        XCTAssertEqual(hdmi.role, .corners(target: Calibration.targets[0], index: 0, problem: .tooManyFingers))
        XCTAssertEqual(hdmi.progress, SetUpProgress(steps: [.corners, .check], current: .corners))
        XCTAssertTrue(hdmi.takesKeyboard)
        XCTAssertEqual(hdmi.placement, .belowCentre)
        for other in plan where other.displayID != hdmi.displayID {
            XCTAssertEqual(other.role, .elsewhere(displayName: "HDMI"))
            XCTAssertFalse(other.takesKeyboard)
            XCTAssertEqual(other.placement, .belowCentre)
        }
        XCTAssertFalse(try screen("12.3FHD", in: plan, snapshot).hasControls)
    }

    func testTheSizeCard() throws {
        let model = model(.nothingPaired)
        model.perform(.beginSetUpMode)
        model.perform(.setUpChoose(displayID: try id("HDMI", model.snapshot)))
        model.simulate(.touch(ilitek))
        for _ in 0..<4 { model.touchSetUp() }
        let snapshot = model.snapshot
        let hdmi = try screen("HDMI", in: SetUpScreens.plan(snapshot), snapshot)
        guard case .size(let choices) = hdmi.role else { return XCTFail("size") }
        XCTAssertEqual(choices.choices, [.displayReport, .touchscreenReport, .another])
        XCTAssertEqual(try XCTUnwrap(choices.displayReports), 27, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(choices.touchscreenReports), 21.5, accuracy: 0.05)
        XCTAssertEqual(hdmi.placement, .centre)
        XCTAssertEqual(hdmi.progress, SetUpProgress(steps: [.corners, .size, .check], current: .size),
                       "a set-up from nothing: corners, size and check, with no pair step")
    }

    func testTheCheck() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .test))
        let snapshot = model.snapshot
        let hdmi = try screen("HDMI", in: SetUpScreens.plan(snapshot), snapshot)
        XCTAssertEqual(hdmi.role, .check(canRedo: false))
        XCTAssertEqual(hdmi.progress, SetUpProgress(steps: [], current: .check), "a test is the check alone")
        XCTAssertEqual(hdmi.placement, .bottom)

        let calibrating = self.model()
        calibrating.perform(.beginSetUp(ilitek, .calibrate))
        for _ in 0..<4 { calibrating.touchSetUp() }
        let check = try screen("HDMI", in: SetUpScreens.plan(calibrating.snapshot), calibrating.snapshot)
        XCTAssertEqual(check.role, .check(canRedo: true))
    }

    /// The display being set up is unplugged, and the snapshot shows it gone before the flow ends:
    /// every screen left says where the set-up was, by no name, and one still takes the keyboard.
    func testTheStepsDisplayGone() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        var snapshot = model.snapshot
        let hdmi = try id("HDMI", snapshot)
        snapshot.displays.removeAll { $0.id == hdmi }
        let plan = SetUpScreens.plan(snapshot)
        XCTAssertEqual(plan.count, 4)
        XCTAssertTrue(plan.allSatisfy { $0.role == .elsewhere(displayName: nil) })
        XCTAssertEqual(plan.filter(\.takesKeyboard).count, 1)
        XCTAssertTrue(try XCTUnwrap(plan.first(where: \.takesKeyboard)).hasControls)
    }

    // MARK: - Screens, and displays that mirror another

    func testEachDisplayOnItsOwnScreen() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let plan = SetUpScreens.plan(model.snapshot)
        let placed = SetUpScreens.placed(plan, screen: { $0 })
        XCTAssertEqual(placed.screens.map(\.screenID), plan.map(\.displayID))
        XCTAssertEqual(placed.screens.map(\.screen), plan)
        XCTAssertEqual(placed.unplaced, [])
    }

    /// "Display" mirrors "HDMI", and the corners are on it: HDMI's screen shows them, and no other.
    func testADisplayThatMirrorsAnotherIsShownOnTheScreenWithItsPicture() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let snapshot = model.snapshot
        let hdmi = try id("HDMI", snapshot), display = try id("Display", snapshot)
        var plan = SetUpScreens.plan(snapshot)
        let hdmiIndex = try XCTUnwrap(plan.firstIndex { $0.displayID == hdmi })
        let displayIndex = try XCTUnwrap(plan.firstIndex { $0.displayID == display })
        let corners = plan[hdmiIndex].role
        plan[hdmiIndex].role = .elsewhere(displayName: "Display")
        plan[hdmiIndex].takesKeyboard = false
        plan[displayIndex].role = corners
        plan[displayIndex].takesKeyboard = true
        let placed = SetUpScreens.placed(plan, screen: { $0 == display ? hdmi : $0 })
        XCTAssertEqual(placed.screens.count, plan.count - 1)
        let onHDMI = try XCTUnwrap(placed.screens.first { $0.screenID == hdmi }).screen
        XCTAssertEqual(onHDMI.displayID, display)
        XCTAssertEqual(onHDMI.role, corners)
        XCTAssertTrue(onHDMI.takesKeyboard)
        XCTAssertFalse(placed.screens.contains { $0.screenID == display })
    }

    func testAScreenSharedWithAnotherTouchscreensDisplayHasNoButtons() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let snapshot = model.snapshot
        let hdmi = try id("HDMI", snapshot), fhd = try id("12.3FHD", snapshot)
        let plan = SetUpScreens.plan(snapshot)
        let placed = SetUpScreens.placed(plan, screen: { $0 == fhd ? hdmi : $0 })
        let onHDMI = try XCTUnwrap(placed.screens.first { $0.screenID == hdmi }).screen
        XCTAssertEqual(onHDMI.displayID, hdmi, "the one being touched")
        XCTAssertFalse(onHDMI.hasControls, "the strip's taps would land on it")
        XCTAssertFalse(onHDMI.takesKeyboard)
        XCTAssertFalse(onHDMI.backdropTakesMouse, "its clicks go through")
        XCTAssertEqual(placed.screens.filter(\.screen.takesKeyboard).count, 1, "another screen takes the keyboard")
    }

    // MARK: - The mouse on the backdrops

    /// A backdrop that hides what is beneath it (the corners, the size card) takes the mouse and
    /// swallows it, where its screen has buttons: a click there never reaches a window the person
    /// can't see. The check is clear, and the dimmed displays let clicks through. Set-up mode's
    /// overview takes the mouse on every display, cards or none: the click is the choice.
    func testWhichBackdropsTakeTheMouse() {
        let overview = SetUpScreenRole.overview(SetUpModeScreen(
            card: SetUpModeCard(displayID: 2, name: "HDMI", detail: "", state: .free, moment: .offering, touchedFirst: nil),
            session: nil, aDisplayWaits: false))
        let roles: [(SetUpScreenRole, Bool, Bool)] = [
            (.corners(target: CGPoint(x: 0.1, y: 0.1), index: 0, problem: nil), true, false),
            (.size(SetUpSizeChoices(displayReports: 27, touchscreenReports: nil, current: nil)), true, false),
            (.check(canRedo: true), false, false),
            (.elsewhere(displayName: "HDMI"), false, false),
            (overview, true, true),
            (.overview(SetUpModeScreen(card: nil, session: nil, aDisplayWaits: false)), true, true),
        ]
        for (role, takesMouse, withoutButtons) in roles {
            var screen = SetUpScreen(
                displayID: 2, touchscreenName: "ILITEK-TP", progress: SetUpProgress(steps: [], current: .check),
                role: role, hasControls: true, takesKeyboard: false, placement: .belowCentre)
            XCTAssertEqual(screen.backdropTakesMouse, takesMouse, "\(role)")
            screen.hasControls = false
            XCTAssertEqual(screen.backdropTakesMouse, withoutButtons, "\(role) with no buttons")
        }
    }

    /// Through a set-up in set-up mode on the desk: every display swallows the mouse in the
    /// overview; then the screen being touched does until the check, and the others, the strip's
    /// display among them, don't; back in the overview, every display again.
    func testTheScreenBeingTouchedSwallowsTheMouseUntilTheCheck() throws {
        let model = model()
        model.perform(.beginSetUpMode)
        func takesMouse(_ name: String) throws -> Bool {
            try screen(name, in: SetUpScreens.plan(model.snapshot), model.snapshot).backdropTakesMouse
        }
        let others = ["LG HDR 4K", "Display", "Built-in Retina Display", "12.3FHD"]
        for name in ["HDMI"] + others {
            XCTAssertTrue(try takesMouse(name), "\(name), in the overview")
        }
        model.perform(.setUpChoose(displayID: try id("HDMI", model.snapshot)))
        for name in ["HDMI"] + others {
            XCTAssertTrue(try takesMouse(name), "\(name), waiting for a touch")
        }
        model.simulate(.touch(ilitek))
        XCTAssertTrue(try takesMouse("HDMI"), "corners")
        for name in others {
            XCTAssertFalse(try takesMouse(name), "\(name), elsewhere")
        }
        for _ in 0..<4 { model.touchSetUp() }
        guard case .size? = model.snapshot.setUp?.step else { return XCTFail("size") }
        XCTAssertTrue(try takesMouse("HDMI"), "size")
        for name in others {
            XCTAssertFalse(try takesMouse(name), "\(name), elsewhere")
        }
        model.perform(.setUpConfirmSize(inches: nil))
        guard case .check? = model.snapshot.setUp?.step else { return XCTFail("check") }
        XCTAssertFalse(try takesMouse("HDMI"), "the check is clear, over the person's own windows")
        model.perform(.setUpDone)
        for name in ["HDMI"] + others {
            XCTAssertTrue(try takesMouse(name), "\(name), back in the overview")
        }
    }

    func testADisplayNoScreenShowsIsLeftOut() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let snapshot = model.snapshot
        let lg = try id("LG HDR 4K", snapshot)
        let placed = SetUpScreens.placed(SetUpScreens.plan(snapshot), screen: { $0 == lg ? nil : $0 })
        XCTAssertEqual(placed.unplaced, [lg])
        XCTAssertEqual(placed.screens.count, snapshot.displays.count - 1)
    }

    // MARK: - Starting the corners again

    /// The display was turned in macOS mid-round: the corners start again from the first target
    /// with no problem set. The screen says so, neutrally, until the next tap is taken.
    func testCornersStartingAgainWithoutAProblemSaySo() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let hdmi = try id("HDMI", model.snapshot)
        model.touchSetUp()
        model.touchSetUp()
        let atThird = SetUpScreens.plan(model.snapshot)
        model.restartSetUpCorners()
        let restarted = SetUpScreens.plan(model.snapshot, after: atThird)
        XCTAssertTrue(try XCTUnwrap(restarted.first { $0.displayID == hdmi }).restartedCorners)
        XCTAssertFalse(try XCTUnwrap(restarted.first { $0.displayID != hdmi }).restartedCorners, "on its display only")

        let stillThere = SetUpScreens.plan(model.snapshot, after: restarted)
        XCTAssertTrue(try XCTUnwrap(stillThere.first { $0.displayID == hdmi }).restartedCorners, "until the next tap")
        model.touchSetUp()
        let moved = SetUpScreens.plan(model.snapshot, after: stillThere)
        XCTAssertFalse(try XCTUnwrap(moved.first { $0.displayID == hdmi }).restartedCorners)
    }

    func testTheFirstTargetIsNotAStartAgain() throws {
        let model = model()
        model.perform(.beginSetUp(ilitek, .calibrate))
        let plan = SetUpScreens.plan(model.snapshot, after: [])
        XCTAssertTrue(plan.allSatisfy { !$0.restartedCorners })
        model.touchSetUp()
        model.touchSetUp(.tapsDidNotFit)
        let refused = SetUpScreens.plan(model.snapshot, after: SetUpScreens.plan(model.snapshot))
        XCTAssertTrue(refused.allSatisfy { !$0.restartedCorners }, "a refused round says why instead")
    }

    // MARK: - The size card's choices

    func testWhatTheSizeCardOffers() {
        let both = SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: nil)
        XCTAssertEqual(both.choices, [.displayReport, .touchscreenReport, .another])
        XCTAssertEqual(both.initialChoice, .displayReport)
        XCTAssertEqual(both.initialText, "")

        let glassOnly = SetUpSizeChoices(displayReports: nil, touchscreenReports: 21.5, current: nil)
        XCTAssertEqual(glassOnly.choices, [.touchscreenReport, .another])
        XCTAssertEqual(glassOnly.initialChoice, .touchscreenReport)

        let none = SetUpSizeChoices(displayReports: nil, touchscreenReports: nil, current: nil)
        XCTAssertEqual(none.choices, [.another])
        XCTAssertEqual(none.initialChoice, .another)
    }

    func testTheSizeInForceIsChosenFirst() {
        XCTAssertEqual(SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: 23.8).initialChoice, .another)
        XCTAssertEqual(SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: 23.8).initialText, "23.8")
        XCTAssertEqual(SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: 21.5).initialChoice,
                       .touchscreenReport)
        XCTAssertEqual(SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: 27).initialChoice, .displayReport)
    }

    func testWhatContinueSends() {
        let choices = SetUpSizeChoices(displayReports: 27, touchscreenReports: 21.5, current: nil)
        XCTAssertEqual(choices.command(.displayReport, text: "99"), .setUpConfirmSize(inches: nil),
                       "as reported: the display's own size")
        XCTAssertEqual(choices.command(.touchscreenReport, text: ""), .setUpConfirmSize(inches: 21.5))
        XCTAssertEqual(choices.command(.another, text: "23.8"), .setUpConfirmSize(inches: 23.8))
        XCTAssertEqual(choices.command(.another, text: " 23,8″ "), .setUpConfirmSize(inches: 23.8))
        XCTAssertNil(choices.command(.another, text: ""), "Continue waits for a size")
        XCTAssertNil(choices.command(.another, text: "1000"))
        XCTAssertNil(choices.command(.another, text: "big"))
        XCTAssertNil(SetUpSizeChoices(displayReports: nil, touchscreenReports: nil, current: nil)
            .command(.displayReport, text: ""), "a choice that isn't offered")
    }

    // MARK: - Where the buttons go

    func testWhereTheButtonsGo() {
        // HDMI, in AppKit's coordinates: origin bottom-left.
        let screen = CGRect(x: -252, y: 1329, width: 2560, height: 1440)
        let size = CGSize(width: 400, height: 90)
        XCTAssertEqual(SetUpScreens.controlsFrame(.centre, size: size, on: screen),
                       CGRect(x: 828, y: 2004, width: 400, height: 90))
        XCTAssertEqual(SetUpScreens.controlsFrame(.belowCentre, size: size, on: screen),
                       CGRect(x: 828, y: 2049 - SetUpScreens.controlsGap - 90, width: 400, height: 90))
        XCTAssertEqual(SetUpScreens.controlsFrame(.bottom, size: size, on: screen),
                       CGRect(x: 828, y: 1329 + SetUpScreens.bottomMargin, width: 400, height: 90))
    }

    func testTheButtonsNeverLeaveTheirDisplay() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 120)
        let frame = SetUpScreens.controlsFrame(.bottom, size: CGSize(width: 500, height: 200), on: narrow)
        XCTAssertTrue(narrow.contains(frame), "\(frame)")
    }

    // MARK: - Return held down

    /// Return held on the size card must not reach Done by key repeat once the check's 0.4 s have
    /// passed: a repeat of Return (36) or Enter (76) is dropped, and nothing else is.
    func testARepeatOfReturnOrEnterIsDropped() {
        XCTAssertTrue(SetUpScreens.dropsKeyDown(keyCode: 36, isARepeat: true), "Return repeating")
        XCTAssertTrue(SetUpScreens.dropsKeyDown(keyCode: 76, isARepeat: true), "Enter repeating")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 36, isARepeat: false), "Return's first press")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 76, isARepeat: false), "Enter's first press")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 53, isARepeat: true), "Esc repeating")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 0, isARepeat: true), "A repeating, in the size field")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 19, isARepeat: true), "2 repeating, in the size field")
        XCTAssertFalse(SetUpScreens.dropsKeyDown(keyCode: 51, isARepeat: true), "Delete repeating")
    }
}
