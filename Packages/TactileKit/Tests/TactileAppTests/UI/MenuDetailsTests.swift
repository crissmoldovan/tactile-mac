import AppKit
import Observation
import SwiftUI
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// The menu-bar menu, one row for each touchscreen, and each touchscreen's details beside it: which
/// row and which details each state gets; what every control sends; that the details are enabled,
/// and say why not, exactly as the pane; where the details go and when they close; and that nothing
/// in the menu reads the gesture tester's live feed.
@MainActor
final class MenuDetailsTests: XCTestCase {

    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip
    private let oldPanel = UIFixtures.oldPanel

    private func row(_ id: TouchscreenID, _ snapshot: AppSnapshot) throws -> MenuBarContent.Touchscreen {
        try XCTUnwrap(MenuBarContent(snapshot).touchscreens.first { $0.id == id }, "\(id)")
    }

    private func touchscreen(_ id: TouchscreenID, _ snapshot: AppSnapshot) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: snapshot), "\(id)")
    }

    /// The desk with `change` made to one touchscreen as the model would report it.
    private func desk(_ id: TouchscreenID, _ change: (inout TouchscreenSnapshot) -> Void) throws -> AppSnapshot {
        var snapshot = UIFixtures.desk
        let index = try XCTUnwrap(snapshot.touchscreens.firstIndex { $0.id == id })
        change(&snapshot.touchscreens[index])
        return snapshot
    }

    // MARK: - The rows

    /// Each touchscreen is one row: its dot, its name, its display's name, or its state when it has
    /// none; greyed as the menu has always greyed one whose switch can't be used.
    func testWhichRowEachStateGets() throws {
        let model = PreviewModel(.desk)
        model.perform(.setTouchscreenOn(strip, false))
        let settingUp = try desk(ilitek) { $0.mode = .settingUp }
        let unreadable = try desk(ilitek) { $0.notes.append(.touchesCannotBeRead) }
        let held = try desk(strip) {
            $0.notes = [.oneFingerOnly, .macOSMayAlsoRespond]
            $0.mode = .held
        }
        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) }).id

        let cases: [(String, AppSnapshot, TouchscreenID, String, StatusIndicator, Bool)] = [
            ("driving", UIFixtures.desk, ilitek, "HDMI", .working, false),
            ("the one-finger strip", UIFixtures.desk, strip, "12.3FHD", .working, false),
            ("not set up", UIFixtures.snapshot(.nothingPaired), ilitek, "Not set up", .needsSetUp, false),
            ("switched off", model.snapshot, strip, "Off", .inactive, false),
            ("its display unplugged", UIFixtures.snapshot(.displayUnplugged), ilitek, "HDMI (not connected)", .waiting, false),
            ("Tactile off", UIFixtures.snapshot(.tactileOff), ilitek, "Left to macOS", .inactive, true),
            ("no Accessibility", UIFixtures.snapshot(.accessibilityMissing), strip, "Left to macOS", .inactive, true),
            ("remembered", UIFixtures.desk, oldPanel, "Not connected", .inactive, true),
            ("being set up", settingUp, ilitek, "Being set up", .settingUp, false),
            ("touches unreadable", unreadable, ilitek, "Can’t be used", .problem, false),
            ("macOS also handles it", held, strip, "Can’t be used", .problem, false),
            ("can't be told apart", twins, twin, "Can’t be used", .needsSetUp, true),
        ]
        for (name, snapshot, id, detail, indicator, isDimmed) in cases {
            let row = try row(id, snapshot)
            XCTAssertEqual(row.detail, detail, name)
            XCTAssertEqual(row.indicator, indicator, name)
            XCTAssertEqual(row.indicator, StatusIndicator(try touchscreen(id, snapshot)), "\(name): the sidebar's dot")
            XCTAssertEqual(row.isDimmed, isDimmed, name)
        }
    }

    // MARK: - The details

    func testTheDetailsOfATouchscreenDriving() throws {
        let snapshot = UIFixtures.desk
        let details = try row(ilitek, snapshot).details
        XCTAssertEqual(details.name, "ILITEK-TP")
        XCTAssertEqual(details.summary, "HDMI · 23.8″ · driving")
        XCTAssertNil(details.unusable)
        let controls = try XCTUnwrap(details.controls)
        XCTAssertEqual(controls.on, .init(isOn: true, isEnabled: true))
        XCTAssertEqual(controls.oneFinger, OneFingerPicker(try touchscreen(ilitek, snapshot)))
        XCTAssertTrue(controls.behaviourIsEnabled)
        XCTAssertTrue(controls.showsTouches)
        XCTAssertEqual(controls.gestureTester, .available)
        XCTAssertEqual(controls.setUp, .calibrateAndTest(.available))
        XCTAssertEqual(details.pane, .touchscreen(ilitek))
    }

    func testTheDetailsOfTheOneFingerStrip() throws {
        let details = try row(strip, UIFixtures.desk).details
        XCTAssertEqual(details.summary, "12.3FHD · 12.3″ · driving · one finger only")
        let controls = try XCTUnwrap(details.controls)
        XCTAssertEqual(controls.oneFinger.title(nil), "Default (Always scroll)", "its default, named")
        XCTAssertEqual(controls.gestureTester, .available)
        XCTAssertEqual(controls.setUp, .calibrateAndTest(.available))
    }

    /// Not set up: Set Up Touchscreens… in place of Calibrate and Test, as the pane's header offers
    /// Set Up by Touch…; the tester says why it can't open.
    func testTheDetailsOfATouchscreenThatIsntSetUp() throws {
        let snapshot = UIFixtures.snapshot(.nothingPaired)
        let details = try row(ilitek, snapshot).details
        XCTAssertEqual(details.summary, "Not set up")
        let controls = try XCTUnwrap(details.controls)
        XCTAssertEqual(controls.setUp, .setUpTouchscreens(.available))
        XCTAssertEqual(controls.gestureTester, .unavailable(.notSetUp))
        XCTAssertEqual(controls.on, .init(isOn: true, isEnabled: true))
    }

    func testTheDetailsOfATouchscreenSwitchedOff() throws {
        let model = PreviewModel(.desk)
        model.perform(.setTouchscreenOn(strip, false))
        let details = try row(strip, model.snapshot).details
        XCTAssertEqual(details.summary, "12.3FHD · 12.3″ · off")
        let controls = try XCTUnwrap(details.controls)
        XCTAssertEqual(controls.on, .init(isOn: false, isEnabled: true), "it can be switched back on here")
        XCTAssertEqual(controls.gestureTester, .unavailable(.off))
    }

    /// Tactile off: the switch can't be used, and the tester and the set-up say why, as the pane.
    func testTheDetailsWhileTactileIsOff() throws {
        let details = try row(ilitek, UIFixtures.snapshot(.tactileOff)).details
        XCTAssertEqual(details.summary, "HDMI · 23.8″ · left to macOS")
        let controls = try XCTUnwrap(details.controls)
        XCTAssertEqual(controls.on, .init(isOn: true, isEnabled: false))
        XCTAssertEqual(controls.gestureTester, .unavailable(.tactileOff))
        XCTAssertEqual(controls.setUp, .calibrateAndTest(.unavailable(.tactileOff)))
    }

    /// A touchscreen Tactile can't use: why, and its pane; no control, since none would work.
    func testTheDetailsOfATouchscreenThatCantBeUsed() throws {
        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) }).id
        let cases: [(AppSnapshot, TouchscreenID, MenuTouchscreenDetails.Unusable)] = [
            (twins, twin, .cannotBeToldApart),
            (try desk(ilitek) { $0.notes.append(.touchesCannotBeRead) }, ilitek, .touchesCannotBeRead),
            (try desk(strip) { $0.notes = [.oneFingerOnly, .macOSMayAlsoRespond] }, strip, .macOSAlsoHandlesIt),
        ]
        for (snapshot, id, reason) in cases {
            let details = try row(id, snapshot).details
            XCTAssertEqual(details.unusable, reason)
            XCTAssertNil(details.controls, "\(reason): nothing that can't work")
            XCTAssertEqual(details.pane, .touchscreen(id))
        }
        XCTAssertEqual(try row(twin, twins).details.summary, "Not set up · can’t be told apart")
    }

    /// Remembered and not connected: its summary and its pane.
    func testTheDetailsOfATouchscreenNotConnected() throws {
        let details = try row(oldPanel, UIFixtures.desk).details
        XCTAssertEqual(details.summary, "Display · not connected")
        XCTAssertNil(details.controls)
        XCTAssertNil(details.unusable)
    }

    // MARK: - What each control sends

    /// Each control sends the pane's command; sent to the preview desk, each changes what the pane
    /// and the details then show.
    func testEveryControlSendsThePanesCommand() throws {
        let model = PreviewModel(.desk)
        var details = try row(ilitek, model.snapshot).details
        XCTAssertEqual(details.onCommand(false), .setTouchscreenOn(ilitek, false))
        XCTAssertEqual(details.showTouchesCommand(false), .setShowsCircles(ilitek, false))
        XCTAssertEqual(details.calibrateCommand, .beginSetUp(ilitek, .calibrate))
        XCTAssertEqual(details.testCommand, .beginSetUp(ilitek, .test))
        XCTAssertEqual(MenuTouchscreenDetails.setUpCommand, .beginSetUpMode)
        XCTAssertEqual(MenuTouchscreenDetails.setUpCommand, SetUpModeAvailability.command,
                       "the menu's own Set Up Touchscreens…")
        let picker = OneFingerPicker(try touchscreen(ilitek, model.snapshot))
        for option in OneFingerPicker.options {
            XCTAssertEqual(details.oneFingerCommand(option), picker.command(option, for: ilitek), "\(String(describing: option))")
        }
        XCTAssertNil(details.oneFingerCommand(nil), "the default, chosen already: nothing")
        XCTAssertEqual(details.oneFingerCommand(.alwaysDrag), .setOneFinger(ilitek, .alwaysDrag))

        model.perform(details.onCommand(false))
        model.perform(details.showTouchesCommand(false))
        try model.perform(XCTUnwrap(details.oneFingerCommand(.alwaysScroll)))
        details = try row(ilitek, model.snapshot).details
        let controls = try XCTUnwrap(details.controls)
        XCTAssertFalse(controls.on.isOn)
        XCTAssertFalse(controls.showsTouches)
        XCTAssertEqual(controls.oneFinger.choice, .alwaysScroll)
        XCTAssertEqual(details.oneFingerCommand(nil), .setOneFinger(ilitek, nil), "Default sends nil, as the pane's")

        model.perform(details.onCommand(true))
        model.perform(try row(ilitek, model.snapshot).details.testCommand)
        XCTAssertEqual(model.snapshot.setUp?.purpose, .test, "Test began a test on its own display")
    }

    // MARK: - The pane's rules

    /// In every state of the desk the details are enabled, and say why not, exactly as the pane:
    /// the header's On switch, the Behaviour group, Gesture Tester…, the Alignment buttons, and Set
    /// Up by Touch… for a touchscreen that isn't set up.
    func testTheDetailsFollowThePanesRules() throws {
        var situations: [(String, AppSnapshot)] = PreviewModel.Variant.allCases.map { ($0.rawValue, UIFixtures.snapshot($0)) }
        let setUpMode = PreviewModel(.desk)
        setUpMode.perform(.beginSetUpMode)
        situations.append(("set-up mode", setUpMode.snapshot))
        let testing = PreviewModel(.desk)
        testing.perform(.beginSetUp(strip, .test))
        situations.append(("a test of the strip", testing.snapshot))
        let off = PreviewModel(.desk)
        off.perform(.setTouchscreenOn(ilitek, false))
        situations.append(("the ILITEK off", off.snapshot))
        let firstRunMode = PreviewModel(.nothingPaired)
        firstRunMode.perform(.beginSetUpMode)
        situations.append(("set-up mode, nothing paired", firstRunMode.snapshot))

        var seen = 0
        for (name, snapshot) in situations {
            for touchscreen in snapshot.touchscreens {
                let details = MenuTouchscreenDetails(touchscreen, in: snapshot)
                let label = "\(name): \(touchscreen.name)"
                guard let controls = details.controls else {
                    XCTAssertTrue(!touchscreen.isConnected || details.unusable != nil, label)
                    continue
                }
                seen += 1
                XCTAssertEqual(controls.on.isEnabled, touchscreen.onSwitchIsEnabled, label)
                XCTAssertEqual(controls.on.isOn, touchscreen.isOn, label)
                XCTAssertEqual(controls.oneFinger, OneFingerPicker(touchscreen), label)
                XCTAssertEqual(controls.behaviourIsEnabled, touchscreen.canChangeSettings, label)
                XCTAssertEqual(controls.showsTouches, touchscreen.behaviour.showsCircles, label)
                XCTAssertEqual(controls.gestureTester, GestureTesterAvailability.of(touchscreen, in: snapshot), label)
                let paneShowsSetUpInHeader = touchscreen.status == .notSetUp && touchscreen.mode != .settingUp
                XCTAssertEqual(
                    controls.setUp,
                    paneShowsSetUpInHeader
                        ? .setUpTouchscreens(SetUpAvailability.full(touchscreen, in: snapshot))
                        : .calibrateAndTest(SetUpAvailability.onItsDisplay(touchscreen, in: snapshot)),
                    label)
            }
        }
        XCTAssertGreaterThan(seen, 20, "the situations cover the touchscreens with controls")
    }

    // MARK: - The steady snapshot

    /// The menu is made from the steady snapshot, and nothing in it depends on the tester's feed: a
    /// tester open with a feed and fingers down gives the same menu as without them.
    func testNothingInTheMenuDependsOnTheTestersFeed() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(ilitek))
        var live = model.snapshot
        XCTAssertFalse(try XCTUnwrap(live.gestureTester).recent.isEmpty)
        XCTAssertEqual(MenuBarContent(live), MenuBarContent(live.withoutTesterFeed))
        live.gestureTester?.fingersDown = 4
        live.gestureTester?.recent[0].summary = "moved on"
        XCTAssertEqual(MenuBarContent(live), MenuBarContent(model.steadySnapshot))
    }

    /// The panel, a touchscreen's details and the plain menu read the model's steady snapshot, never
    /// its live one: the tester's feed, ten updates a second, can't draw them again.
    func testTheMenuReadsOnlyTheSteadySnapshot() throws {
        _ = NSApplication.shared
        let preview = PreviewModel(.desk)
        preview.perform(.openGestureTester(ilitek))
        let model = ReadCountingModel(preview.snapshot)
        let views: [NSView] = [
            NSHostingView(rootView: MenuBarView(model: model)),
            NSHostingView(rootView: TouchscreenDetailsRoot(model: model, id: ilitek, actions: .none)),
            NSHostingView(rootView: TouchscreenDetailsRoot(model: model, id: strip, actions: .none)),
            NSHostingView(rootView: VStack { MenuBarMenu(model: model) }),
        ]
        for view in views {
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 700)
            view.layoutSubtreeIfNeeded()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        model.feed()
        for view in views {
            view.layoutSubtreeIfNeeded()
        }
        XCTAssertGreaterThan(model.steadyReads, 3, "each read the steady snapshot")
        XCTAssertEqual(model.liveReads, 0, "none read the live snapshot")
    }

    // MARK: - Opening, moving and closing the details

    func testChoosingARowOpensMovesOrKeepsItsDetails() {
        var presenter = MenuDetailsPresenter()
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek))
        XCTAssertEqual(presenter.shown, ilitek)
        XCTAssertEqual(presenter.chosen(strip), .show(strip), "another row moves them")
        XCTAssertEqual(presenter.shown, strip)
        XCTAssertEqual(presenter.chosen(strip), .show(strip), "the same row again keeps them up")
        XCTAssertEqual(presenter.shown, strip)
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek))
        presenter.closed()
        XCTAssertNil(presenter.shown, "Esc, a click elsewhere, the menu closing")
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek), "and the row opens them again")
    }

    func testTheDetailsCloseWhenTheirTouchscreenGoes() {
        var presenter = MenuDetailsPresenter()
        _ = presenter.chosen(oldPanel)
        XCTAssertNil(presenter.follow(MenuBarContent(UIFixtures.desk)), "still there")
        var desk = PreviewDesk(.desk)
        desk.apply(.forget(oldPanel))
        XCTAssertEqual(presenter.follow(MenuBarContent(desk.snapshot())), .close)
        XCTAssertNil(presenter.shown)
    }

    // MARK: - Where the details go

    /// Beside the menu, as a submenu: on the right where there is room, else on the left; the
    /// details' first line level with the row; kept on the screen.
    func testWhereTheDetailsGo() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let size = CGSize(width: 300, height: 260)
        // A menu in the middle of the menu bar, its row 100 points below its top.
        let menu = CGRect(x: 1000, y: 915, width: 348, height: 500)
        let row = CGRect(x: 1006, y: 1291, width: 336, height: 24)
        let right = MenuDetailsPlacement.frame(size: size, row: row, menu: menu, screen: screen)
        XCTAssertEqual(right.minX, menu.maxX + MenuDetailsPlacement.gap)
        XCTAssertEqual(right.maxY, row.maxY + MenuDetailsPlacement.inset, "its top at the row's, less its padding")
        XCTAssertEqual(right.size, size)

        // At the right of the screen, where menu-bar items are: on the left.
        let atTheEdge = CGRect(x: 2200, y: 915, width: 348, height: 500)
        let edgeRow = CGRect(x: 2206, y: 1291, width: 336, height: 24)
        let left = MenuDetailsPlacement.frame(size: size, row: edgeRow, menu: atTheEdge, screen: screen)
        XCTAssertEqual(left.maxX, atTheEdge.minX - MenuDetailsPlacement.gap)

        // A row near the bottom of the screen: lifted to stay on it. One at the very top: lowered.
        let low = MenuDetailsPlacement.frame(
            size: size, row: CGRect(x: 1006, y: 100, width: 336, height: 24), menu: menu, screen: screen)
        XCTAssertEqual(low.minY, screen.minY)
        let high = MenuDetailsPlacement.frame(
            size: size, row: CGRect(x: 1006, y: 1405, width: 336, height: 24), menu: menu, screen: screen)
        XCTAssertEqual(high.maxY, screen.maxY)

        // A screen too narrow for either side: kept on it, over the menu.
        let narrow = MenuDetailsPlacement.frame(
            size: size, row: row, menu: CGRect(x: 0, y: 915, width: 348, height: 500),
            screen: CGRect(x: 0, y: 0, width: 500, height: 1415))
        XCTAssertEqual(narrow.minX, 0)
    }

    // MARK: - Settings for <name>…

    func testSettingsForATouchscreenAsksForItsPaneOnce() {
        let requests = SettingsPaneRequests()
        XCTAssertNil(requests.take())
        requests.post(.touchscreen(strip))
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.take(), .touchscreen(strip))
        XCTAssertNil(requests.take(), "taken once")
        requests.post(.touchscreen(ilitek))
        XCTAssertEqual(requests.count, 2)
    }

    // MARK: - Wording

    func testTheMenusWords() {
        XCTAssertEqual(Wording.settingsFor(name: "ILITEK-TP"), "Settings for ILITEK-TP…")
        XCTAssertEqual(Wording.showTouches, Wording.touchCircles)
        XCTAssertEqual(Wording.menuRow(name: "ILITEK-TP", detail: "HDMI"), "ILITEK-TP — HDMI")
        XCTAssertEqual(
            Wording.menuCannotBeUsed(.cannotBeToldApart),
            "It can’t be told apart from an identical touchscreen, so Tactile can’t keep settings for it.")
        XCTAssertEqual(Wording.menuCannotBeUsed(.touchesCannotBeRead), "Tactile can’t read its touches.")
        XCTAssertEqual(
            Wording.menuCannotBeUsed(.macOSAlsoHandlesIt),
            "macOS is also handling this touchscreen, so Tactile doesn’t drive it. Quit any other app that reads it, then unplug it and plug it back in.")
        for reason in MenuTouchscreenDetails.Unusable.allCases {
            XCTAssertTrue(Wording.menuCannotBeUsed(reason).hasSuffix("."), "\(reason)")
        }
    }

    /// The summary: the display, the diagonal in force (the override, else what the display
    /// reports), the state, and the notes that limit it.
    func testTheSummaryLine() throws {
        let reported = try desk(ilitek) { $0.diagonalInches = nil }
        XCTAssertEqual(try row(ilitek, reported).details.summary, "HDMI · 27″ · driving", "as HDMI reports")
        let held = try desk(ilitek) { $0.mode = .released }
        XCTAssertEqual(try row(ilitek, held).details.summary, "HDMI · 23.8″ · not driving")
        let settingUp = try desk(ilitek) { $0.mode = .settingUp }
        XCTAssertEqual(try row(ilitek, settingUp).details.summary, "HDMI · 23.8″ · being set up")
        XCTAssertEqual(try row(ilitek, UIFixtures.snapshot(.displayUnplugged)).details.summary,
                       "HDMI · 23.8″ · display not connected")
    }
}

/// A model that counts which snapshot is read: the live one, with the tester's feed, or the steady
/// one.
@MainActor
@Observable
private final class ReadCountingModel: AppModel {
    @ObservationIgnored private(set) var liveReads = 0
    @ObservationIgnored private(set) var steadyReads = 0
    private var live: AppSnapshot
    private var steady: AppSnapshot

    init(_ snapshot: AppSnapshot) {
        live = snapshot
        steady = snapshot.withoutTesterFeed
    }

    var snapshot: AppSnapshot {
        liveReads += 1
        return live
    }

    var steadySnapshot: AppSnapshot {
        steadyReads += 1
        return steady
    }

    /// A gesture goes on: the feed changes, and the steady snapshot doesn't.
    func feed() {
        live.gestureTester?.fingersDown += 1
        if live.gestureTester?.recent.isEmpty == false {
            live.gestureTester?.recent[0].summary += "."
        }
    }

    func perform(_ command: AppCommand) {}
}
