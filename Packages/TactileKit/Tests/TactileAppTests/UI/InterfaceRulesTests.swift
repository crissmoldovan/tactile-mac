import Foundation
import TactileScreens
import XCTest

@testable import TactileApp

/// The interface's small decisions: when Settings opens itself, what is selected, the dots, the
/// menu, the menu-bar icon and the diagonal field.
final class InterfaceRulesTests: XCTestCase {

    // MARK: - The first-run moment

    /// Settings opens itself only for missing Accessibility access. Touchscreens that aren't set up
    /// get the small first-run window instead (`FirstRunOffer`), once.
    func testSettingsOpensItselfOnlyWhenAccessibilityIsMissing() {
        XCTAssertFalse(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.desk)))
        XCTAssertFalse(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.nothingPaired)),
                       "the first-run window asks instead")
        XCTAssertTrue(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.accessibilityMissing)))
        XCTAssertTrue(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.allWarnings)))
        XCTAssertFalse(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.tactileOff)))
        XCTAssertFalse(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.displayUnplugged)))
        XCTAssertFalse(shouldOpenSettingsAtLaunch(UIFixtures.snapshot(.identicalTwins)))
    }

    func testOtherWarningsAloneDoNotOpenSettings() {
        var snapshot = UIFixtures.desk
        snapshot.warnings = [.touchUpRunning, .missionControlShortcutsOff, .settingsSetAside]
        XCTAssertFalse(shouldOpenSettingsAtLaunch(snapshot))
    }

    func testATouchscreenNotSetUpNoLongerOpensSettings() {
        var desk = PreviewDesk(.desk)
        desk.apply(.unpair(UIFixtures.strip))
        XCTAssertFalse(shouldOpenSettingsAtLaunch(desk.snapshot()))
        var snapshot = desk.snapshot()
        snapshot.offerSetUpTo = [UIFixtures.strip]
        XCTAssertFalse(shouldOpenSettingsAtLaunch(snapshot), "an offer is the first-run window's, not Settings'")
    }

    // MARK: - What the sidebar selects

    func testTheFirstSelection() {
        XCTAssertEqual(SidebarItem.initial(for: UIFixtures.desk), .touchscreen(UIFixtures.ilitek))
        XCTAssertEqual(SidebarItem.initial(for: UIFixtures.snapshot(.nothingPaired)), .touchscreen(UIFixtures.ilitek))
        XCTAssertEqual(SidebarItem.initial(for: UIFixtures.snapshot(.accessibilityMissing)), .general)

        var desk = PreviewDesk(.desk)
        desk.apply(.unpair(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.initial(for: desk.snapshot()), .touchscreen(UIFixtures.strip),
                       "the touchscreen that isn't set up")

        var empty = UIFixtures.desk
        empty.touchscreens = []
        XCTAssertEqual(SidebarItem.initial(for: empty), .general)
    }

    func testAClearedSelectionKeepsThePaneShown() {
        let desk = UIFixtures.desk
        XCTAssertEqual(SidebarItem.resolve(nil, previous: .touchscreen(UIFixtures.strip), in: desk),
                       .touchscreen(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.resolve(nil, previous: .general, in: desk), .general)
        var forgotten = desk
        forgotten.touchscreens.removeAll { $0.id == UIFixtures.oldPanel }
        XCTAssertEqual(SidebarItem.resolve(nil, previous: .touchscreen(UIFixtures.oldPanel), in: forgotten),
                       .touchscreen(UIFixtures.ilitek))
        XCTAssertEqual(SidebarItem.resolve(.general, previous: .touchscreen(UIFixtures.strip), in: desk), .general)
    }

    /// Settings opened on General for Accessibility; once access is granted, and if the person
    /// hasn't chosen a pane, it moves on to the touchscreen that isn't set up.
    func testTheSelectionFollowsWhatNeedsThePersonUntilTheyChoose() {
        var desk = PreviewDesk(.accessibilityMissing)
        desk.apply(.unpair(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.following(.general, chosenByPerson: false, in: desk.snapshot()), .general)
        desk.apply(.askForAccessibility)
        XCTAssertEqual(SidebarItem.following(.general, chosenByPerson: false, in: desk.snapshot()),
                       .touchscreen(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.following(.general, chosenByPerson: true, in: desk.snapshot()), .general)
        var forgotten = desk.snapshot()
        forgotten.touchscreens.removeAll { $0.id == UIFixtures.oldPanel }
        XCTAssertEqual(SidebarItem.following(.touchscreen(UIFixtures.oldPanel), chosenByPerson: true, in: forgotten),
                       .touchscreen(UIFixtures.strip))
    }

    /// Opened on the strip because it wasn't set up; the person pairs it from its own pop-up without
    /// touching the sidebar: the pane stays on the strip.
    func testThePaneStaysOnTheTouchscreenThePersonJustPaired() throws {
        var desk = PreviewDesk(.desk)
        desk.apply(.unpair(UIFixtures.strip))
        let opened = SidebarItem.initial(for: desk.snapshot())
        XCTAssertEqual(opened, .touchscreen(UIFixtures.strip))
        let fhd = try XCTUnwrap(UIFixtures.displayID(named: "12.3FHD", in: desk.snapshot()))
        desk.apply(.pair(UIFixtures.strip, displayID: fhd))
        XCTAssertEqual(SidebarItem.following(opened, chosenByPerson: false, in: desk.snapshot()),
                       .touchscreen(UIFixtures.strip))
    }

    /// Unchosen panes stay put: a touchscreen that needs setting up later doesn't pull the pane away
    /// from another touchscreen, and General stays when nothing needs the person.
    func testAnUnchosenPaneStaysUnlessItWasShownForAccessibility() {
        var desk = PreviewDesk(.desk)
        XCTAssertEqual(SidebarItem.following(.touchscreen(UIFixtures.ilitek), chosenByPerson: false, in: desk.snapshot()),
                       .touchscreen(UIFixtures.ilitek))
        desk.apply(.unpair(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.following(.touchscreen(UIFixtures.ilitek), chosenByPerson: false, in: desk.snapshot()),
                       .touchscreen(UIFixtures.ilitek))
        XCTAssertEqual(SidebarItem.following(.general, chosenByPerson: false, in: UIFixtures.desk), .general,
                       "nothing needs the person")
        XCTAssertEqual(SidebarItem.following(nil, chosenByPerson: false, in: desk.snapshot()),
                       .touchscreen(UIFixtures.strip))
    }

    func testASelectionThatIsGoneFallsBack() {
        let desk = UIFixtures.desk
        XCTAssertEqual(SidebarItem.resolve(.touchscreen(UIFixtures.strip), in: desk), .touchscreen(UIFixtures.strip))
        XCTAssertEqual(SidebarItem.resolve(.general, in: desk), .general)
        XCTAssertEqual(SidebarItem.resolve(nil, in: desk), .touchscreen(UIFixtures.ilitek))
        var forgotten = desk
        forgotten.touchscreens.removeAll { $0.id == UIFixtures.oldPanel }
        XCTAssertEqual(SidebarItem.resolve(.touchscreen(UIFixtures.oldPanel), in: forgotten),
                       .touchscreen(UIFixtures.ilitek))
    }

    // MARK: - Status dots

    func testTheDotForEachStatus() {
        var touchscreen = UIFixtures.desk.touchscreens[0]
        let cases: [(TouchscreenStatus, StatusIndicator)] = [
            (.pairedWith(name: "HDMI", detail: ""), .working),
            (.notSetUp, .needsSetUp),
            (.displayNotConnected(name: "HDMI"), .waiting),
            (.off, .inactive),
            (.tactileOff, .inactive),
            (.accessibilityMissing, .inactive),
            (.stoppedAnswering, .problem),
        ]
        for (status, indicator) in cases {
            touchscreen.status = status
            XCTAssertEqual(StatusIndicator(touchscreen), indicator, "\(status)")
        }
        touchscreen.status = .pairedWith(name: "HDMI", detail: "")
        touchscreen.notes = [.touchesCannotBeRead]
        XCTAssertEqual(StatusIndicator(touchscreen), .problem)
        touchscreen.notes = [.macOSMayAlsoRespond, .oneFingerOnly]
        XCTAssertEqual(StatusIndicator(touchscreen), .working)
        XCTAssertEqual(StatusIndicator(UIFixtures.desk.touchscreens[2]), .inactive, "not connected")
    }

    /// A touchscreen Tactile holds, with its display connected (a mouse-mode panel macOS still sees,
    /// or one whose touches can't be read): never the green "working" dot.
    func testAHeldTouchscreenIsNeverGreen() {
        var touchscreen = UIFixtures.desk.touchscreens[0]
        touchscreen.status = .pairedWith(name: "HDMI", detail: "")
        touchscreen.mode = .held
        touchscreen.notes = [.oneFingerOnly, .macOSMayAlsoRespond]
        XCTAssertEqual(StatusIndicator(touchscreen), .problem)
        touchscreen.mode = .driving
        XCTAssertEqual(StatusIndicator(touchscreen), .working, "driving, shared with macOS")
        touchscreen.mode = .released
        touchscreen.status = .off
        XCTAssertEqual(StatusIndicator(touchscreen), .inactive, "only a paired status changes")
    }

    // MARK: - The menu

    func testTheMenuOfTheDesk() {
        let menu = MenuBarContent(UIFixtures.desk)
        XCTAssertTrue(menu.isOn)
        XCTAssertEqual(menu.warnings, [])
        XCTAssertEqual(menu.touchscreens.map(\.id), [UIFixtures.ilitek, UIFixtures.strip, UIFixtures.oldPanel])
        XCTAssertEqual(menu.touchscreens.map(\.name), ["ILITEK-TP", "TouchScreen", "Old panel"])
        XCTAssertEqual(menu.touchscreens.map(\.indicator), [.working, .working, .inactive])
        XCTAssertEqual(menu.touchscreens.map(\.detail), ["HDMI", "12.3FHD", "Not connected"],
                       "one row each: its display's name, or its state when it has none")
        XCTAssertEqual(menu.touchscreens.map(\.isDimmed), [false, false, true])
        XCTAssertEqual(menu.setUp, .available, "Set Up Touchscreens…: every touchscreen set up, and it can still begin")
    }

    func testTheMenuWithoutAccessibility() {
        let menu = MenuBarContent(UIFixtures.snapshot(.accessibilityMissing))
        XCTAssertEqual(menu.warnings, [
            .init(warning: .accessibilityMissing, title: "Accessibility access missing",
                  detail: "Tactile can’t drive touchscreens without it, so it leaves them all to macOS. If Tactile is already listed and switched on in Accessibility settings, remove it with − and add it again with +.",
                  action: WarningAction(title: "Open Accessibility Settings…", kind: .command(.askForAccessibility))),
        ])
        XCTAssertEqual(menu.touchscreens.map(\.detail), ["Left to macOS", "Left to macOS", "Not connected"])
        XCTAssertEqual(menu.touchscreens.map(\.isDimmed), [true, true, true])
    }

    func testTheMenuWhileTactileIsOff() {
        let menu = MenuBarContent(UIFixtures.snapshot(.tactileOff))
        XCTAssertFalse(menu.isOn)
        XCTAssertEqual(menu.touchscreens.map(\.detail), ["Left to macOS", "Left to macOS", "Not connected"])
        XCTAssertEqual(menu.touchscreens.map(\.isDimmed), [true, true, true])
        XCTAssertEqual(menu.setUp, .unavailable(.tactileOff))
    }

    func testTheMenuListsEveryWarningInOrder() {
        let menu = MenuBarContent(UIFixtures.snapshot(.allWarnings))
        XCTAssertEqual(menu.warnings.map(\.warning), AppWarning.allCases)
        XCTAssertEqual(menu.warnings.compactMap(\.action).map(\.title),
                       ["Open Accessibility Settings…", "Quit Touch Up", "Open Keyboard Settings…"])
    }

    func testATouchscreenTurnedOffCanBeTurnedOnFromItsDetails() throws {
        var desk = PreviewDesk(.desk)
        desk.apply(.setTouchscreenOn(UIFixtures.ilitek, false))
        let row = MenuBarContent(desk.snapshot()).touchscreens[0]
        XCTAssertEqual(row.detail, "Off")
        XCTAssertFalse(row.isDimmed)
        let on = try XCTUnwrap(row.details.controls?.on)
        XCTAssertEqual(on, .init(isOn: false, isEnabled: true))
        XCTAssertEqual(row.details.onCommand(true), .setTouchscreenOn(UIFixtures.ilitek, true))
    }

    // MARK: - The menu-bar icon

    func testTheIconsState() {
        XCTAssertEqual(MenuBarIcon.State(UIFixtures.desk), .normal)
        XCTAssertEqual(MenuBarIcon.State(UIFixtures.snapshot(.tactileOff)), .off)
        XCTAssertEqual(MenuBarIcon.State(UIFixtures.snapshot(.accessibilityMissing)), .attention)
        var offWithWarning = UIFixtures.snapshot(.tactileOff)
        offWithWarning.warnings = [.touchUpRunning]
        XCTAssertEqual(MenuBarIcon.State(offWithWarning), .attention, "a warning shows even while off")
    }

    func testTheIconsDescription() {
        XCTAssertEqual(MenuBarIcon.State.normal.accessibilityDescription, "Tactile")
        XCTAssertEqual(MenuBarIcon.State.off.accessibilityDescription, "Tactile, off")
        XCTAssertEqual(MenuBarIcon.State.attention.accessibilityDescription, "Tactile, needs attention")
    }

    // MARK: - The Display pop-up

    func testWhatTheDisplayPopUpShows() throws {
        let desk = UIFixtures.desk
        let ilitek = try XCTUnwrap(UIFixtures.touchscreen(UIFixtures.ilitek, in: desk))
        let hdmi = try XCTUnwrap(UIFixtures.displayID(named: "HDMI", in: desk))
        XCTAssertEqual(DisplayPick(ilitek), .display(hdmi))
        XCTAssertEqual(DisplayPick(UIFixtures.snapshot(.nothingPaired).touchscreens[0]), .unpaired)
        let unplugged = try XCTUnwrap(UIFixtures.touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.displayUnplugged)))
        XCTAssertEqual(DisplayPick(unplugged), .missing("HDMI"), "paired with a display that is away: shown as such")
    }

    /// Paired, its display away, and a status that names no display: never "Unpaired".
    func testThePopUpNeverSaysUnpairedForAPairedTouchscreen() throws {
        var touchscreen = try XCTUnwrap(
            UIFixtures.touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.displayUnplugged)))
        for status in [TouchscreenStatus.off, .tactileOff, .accessibilityMissing] {
            touchscreen.status = status
            XCTAssertEqual(DisplayPick(touchscreen), .missing("HDMI"), "\(status)")
            XCTAssertTrue(touchscreen.isPaired, "\(status)")
        }
        let off = try XCTUnwrap(
            UIFixtures.touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.tactileOffDisplayUnplugged)))
        XCTAssertEqual(off.status, .tactileOff)
        XCTAssertEqual(DisplayPick(off), .missing("HDMI"))
        XCTAssertNil(DisplayPick.missing("HDMI").command(for: off))
        XCTAssertFalse(UIFixtures.snapshot(.nothingPaired).touchscreens[0].isPaired)
    }

    func testWhatChoosingInTheDisplayPopUpSends() throws {
        let desk = UIFixtures.desk
        let ilitek = try XCTUnwrap(UIFixtures.touchscreen(UIFixtures.ilitek, in: desk))
        let hdmi = try XCTUnwrap(UIFixtures.displayID(named: "HDMI", in: desk))
        let lg = try XCTUnwrap(UIFixtures.displayID(named: "LG HDR 4K", in: desk))
        XCTAssertEqual(DisplayPick.display(lg).command(for: ilitek), .pair(UIFixtures.ilitek, displayID: lg))
        XCTAssertEqual(DisplayPick.unpaired.command(for: ilitek), .unpair(UIFixtures.ilitek))
        XCTAssertNil(DisplayPick.display(hdmi).command(for: ilitek), "already paired with it")
        XCTAssertNil(DisplayPick.missing("HDMI").command(for: ilitek))
    }

    func testADisplayWithoutAUUIDCannotBeRenamed() throws {
        var hdmi = try XCTUnwrap(UIFixtures.desk.displays.first { $0.name == "HDMI" })
        XCTAssertTrue(hdmi.canBeRenamed)
        hdmi.uuid = ""
        XCTAssertFalse(hdmi.canBeRenamed, "every display without a UUID would share the name")
    }

    // MARK: - The diagonal field

    func testWhatTheDiagonalFieldAccepts() {
        XCTAssertEqual(DiagonalEntry.range, SurfaceSize.plausibleDiagonals, "the field accepts what the engine uses")
        XCTAssertEqual(DiagonalEntry.parse(""), .asReported)
        XCTAssertEqual(DiagonalEntry.parse("   "), .asReported)
        XCTAssertEqual(DiagonalEntry.parse("23.8"), .inches(23.8))
        XCTAssertEqual(DiagonalEntry.parse(" 23,8 "), .inches(23.8))
        XCTAssertEqual(DiagonalEntry.parse("12.3″"), .inches(12.3))
        XCTAssertEqual(DiagonalEntry.parse("12.3\""), .inches(12.3))
        XCTAssertEqual(DiagonalEntry.parse("27 inches"), .inches(27))
        XCTAssertEqual(DiagonalEntry.parse("27in"), .inches(27))
        XCTAssertEqual(DiagonalEntry.parse("3"), .inches(3))
        XCTAssertEqual(DiagonalEntry.parse("200"), .inches(200))
        XCTAssertEqual(DiagonalEntry.parse("2.9"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("201"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("big"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("nan"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("inf"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("1e400"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("23.8.1"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("0"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("-3"), .invalid)
        XCTAssertEqual(DiagonalEntry.parse("1e9"), .invalid)
    }

    func testHowTheDiagonalFieldShowsAValue() {
        XCTAssertEqual(DiagonalEntry.text(for: nil), "")
        XCTAssertEqual(DiagonalEntry.text(for: 23.8), "23.8")
        XCTAssertEqual(DiagonalEntry.text(for: 27), "27")
        XCTAssertEqual(DiagonalEntry.text(for: 12.25), "12.25")
        XCTAssertEqual(DiagonalEntry.text(for: 12.3456), "12.35")
    }

    func testTheCommandADiagonalEntrySends() {
        let id = UIFixtures.ilitek
        XCTAssertEqual(DiagonalEntry.command(for: "23.8", current: nil, id: id), .setDiagonal(id, inches: 23.8))
        XCTAssertEqual(DiagonalEntry.command(for: "", current: 23.8, id: id), .setDiagonal(id, inches: nil))
        XCTAssertNil(DiagonalEntry.command(for: "", current: nil, id: id), "nothing changed")
        XCTAssertNil(DiagonalEntry.command(for: "23.8", current: 23.8, id: id), "nothing changed")
        XCTAssertNil(DiagonalEntry.command(for: "big", current: 23.8, id: id), "nothing sensible to send")
    }

    // MARK: - Committing the diagonal field

    /// The ILITEK's diagonal in force, as `model` has it now.
    @MainActor
    private func diagonal(_ model: PreviewModel) -> Double? {
        model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek }?.diagonalInches
    }

    /// Return, or leaving the field: what was typed is sent, and the field shows the diagonal in
    /// force once the model has answered.
    @MainActor
    func testCommittingTheDiagonalField() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        var field = DiagonalField()
        field.show(diagonal(model))
        XCTAssertEqual(field.text, "23.8")
        field.text = " 27,0″ "
        XCTAssertTrue(field.commit(for: id, inForce: { self.diagonal(model) }, perform: model.perform))
        XCTAssertEqual(diagonal(model), 27)
        XCTAssertEqual(field.text, "27")
        field.text = ""
        XCTAssertTrue(field.commit(for: id, inForce: { self.diagonal(model) }, perform: model.perform))
        XCTAssertNil(diagonal(model))
        XCTAssertEqual(field.text, "", "as reported")
        field.text = "big"
        XCTAssertFalse(field.commit(for: id, inForce: { self.diagonal(model) }, perform: model.perform),
                       "not a diagonal: the field beeps")
        XCTAssertEqual(field.text, "", "back to the value in force")
    }

    /// While a set-up runs the model refuses a new diagonal. The field goes back to the one in
    /// force rather than show the refused one as if it were set, and still shows it once the set-up
    /// is cancelled.
    @MainActor
    func testARefusedDiagonalGivesWayToTheOneInForce() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        var field = DiagonalField()
        field.show(diagonal(model))
        model.perform(.beginSetUp(id, .calibrate))
        field.text = "27"
        var sent: [AppCommand] = []
        let perform: PerformCommand = { command in
            sent.append(command)
            model.perform(command)
        }
        XCTAssertTrue(field.commit(for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.setDiagonal(id, inches: 27)], "sent")
        XCTAssertEqual(diagonal(model), 23.8, "and refused")
        XCTAssertEqual(field.text, "23.8")
        model.perform(.cancelSetUp)
        XCTAssertEqual(diagonal(model), 23.8)
        XCTAssertEqual(field.text, "23.8")
    }

    /// A diagonal being typed when a set-up is begun from the pane is set first, while the model
    /// still takes it; any other command from the pane leaves it being typed.
    @MainActor
    func testADiagonalBeingTypedIsSetBeforeASetUpBegins() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        var field = DiagonalField()
        field.show(diagonal(model))
        field.text = "27"
        var sent: [AppCommand] = []
        let perform: PerformCommand = { command in
            sent.append(command)
            model.perform(command)
        }
        XCTAssertTrue(field.send(.setShowsCircles(id, false), for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.setShowsCircles(id, false)])
        XCTAssertEqual(field.text, "27", "still being typed")

        sent = []
        XCTAssertTrue(field.send(.beginSetUp(id, .calibrate), for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.setDiagonal(id, inches: 27), .beginSetUp(id, .calibrate)])
        XCTAssertEqual(diagonal(model), 27)
        XCTAssertNotNil(model.snapshot.setUp)
        XCTAssertEqual(field.text, "27")
    }

    /// The pane's Set Up by Touch… begins set-up mode: a diagonal being typed is set first, while
    /// the model still takes it; the mode's size step starts from it.
    @MainActor
    func testADiagonalBeingTypedIsSetBeforeSetUpModeBegins() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        var field = DiagonalField()
        field.show(diagonal(model))
        field.text = "26"
        var sent: [AppCommand] = []
        let perform: PerformCommand = { command in
            sent.append(command)
            model.perform(command)
        }
        XCTAssertTrue(field.send(.beginSetUpMode, for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.setDiagonal(id, inches: 26), .beginSetUpMode])
        XCTAssertEqual(diagonal(model), 26)
        XCTAssertNotNil(model.snapshot.setUpMode)
        model.perform(.setDiagonal(id, inches: 20))
        XCTAssertEqual(diagonal(model), 26, "refused once the mode is on")
    }

    /// Nothing typed: a set-up begun from the pane, or leaving the field, sends no diagonal, even
    /// when the one in force has more decimals than the field shows (the size step can store the
    /// touchscreen's own report, 21.5049″, shown as 21.5).
    @MainActor
    func testAFieldShowingTheValueInForceSendsNothing() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        model.perform(.setDiagonal(id, inches: 21.5049))
        var field = DiagonalField()
        field.show(diagonal(model))
        XCTAssertEqual(field.text, "21.5")
        var sent: [AppCommand] = []
        let perform: PerformCommand = { command in
            sent.append(command)
            model.perform(command)
        }
        XCTAssertTrue(field.commit(for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [], "leaving the field")
        XCTAssertTrue(field.send(.beginSetUp(id, .calibrate), for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.beginSetUp(id, .calibrate)], "beginning a set-up")
        XCTAssertEqual(diagonal(model), 21.5049, "kept as it was")
        XCTAssertEqual(field.text, "21.5")
    }

    /// Something typed that isn't a diagonal, when a set-up is begun from the pane: the set-up
    /// begins, and the field goes back to the value in force, with a beep.
    @MainActor
    func testANonDiagonalBeingTypedGivesWayWhenASetUpBegins() {
        let model = PreviewModel(.desk)
        let id = UIFixtures.ilitek
        var field = DiagonalField()
        field.show(diagonal(model))
        field.text = "big"
        var sent: [AppCommand] = []
        let perform: PerformCommand = { command in
            sent.append(command)
            model.perform(command)
        }
        XCTAssertFalse(field.send(.beginSetUp(id, .test), for: id, inForce: { self.diagonal(model) }, perform: perform))
        XCTAssertEqual(sent, [.beginSetUp(id, .test)])
        XCTAssertNotNil(model.snapshot.setUp)
        XCTAssertEqual(field.text, "23.8")
    }
}
