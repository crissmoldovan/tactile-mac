import Foundation
@testable import TactileApp
import TactileDevices
import TactileScreens
import XCTest

/// Where the touchscreen check starts, as rules and words: Touchscreen Check in the sidebar after
/// General, and its pane; Check This Touchscreen… in a touchscreen's header, whose status line goes
/// when it says what the Display row says; and the way in from set-up mode's session card, which
/// leaves set-up mode first. No window is opened, and no device.
@MainActor
final class TouchscreenCheckEntryTests: XCTestCase {

    private func device(_ usbID: String, location: String?, kind: SupportDeviceKind = .touchscreen, product: String = "Panel",
                        interface: UInt64 = 1) -> SupportDevice {
        let parts = usbID.split(separator: ":").map { Int($0, radix: 16) ?? 0 }
        let locationID = location.flatMap { UInt32($0, radix: 16) } ?? 0
        return SupportDevice(
            id: "\(usbID)@\(location ?? "-")", kind: kind, vendorID: parts[0], productID: parts[1], product: product,
            manufacturer: "", serial: "", locationID: locationID,
            interfaces: [SupportInterface(id: interface, role: .touch, usages: [], descriptor: nil, maxInputReportSize: nil)])
    }

    private func touchscreen(_ id: TouchscreenID, in snapshot: AppSnapshot) throws -> TouchscreenSnapshot {
        try XCTUnwrap(UIFixtures.touchscreen(id, in: snapshot))
    }

    // MARK: - The sidebar

    func testTouchscreenCheckComesAfterGeneral() {
        XCTAssertEqual(SidebarItem.belowTouchscreens, [.general, .touchscreenCheck])
        XCTAssertEqual(Wording.touchscreenCheck, "Touchscreen Check")
    }

    /// Settings still opens where it did: never on Touchscreen Check, which waits for the person.
    func testTheFirstSelectionIsUnchanged() {
        XCTAssertEqual(SidebarItem.initial(for: UIFixtures.desk), .touchscreen(UIFixtures.ilitek))
        XCTAssertEqual(SidebarItem.initial(for: UIFixtures.snapshot(.accessibilityMissing)), .general)
        var empty = UIFixtures.desk
        empty.touchscreens = []
        XCTAssertEqual(SidebarItem.initial(for: empty), .general)
        for variant in PreviewModel.Variant.allCases {
            XCTAssertNotEqual(SidebarItem.initial(for: UIFixtures.snapshot(variant)), .touchscreenCheck, variant.rawValue)
        }
    }

    func testTouchscreenCheckStaysShownOnceChosen() {
        let desk = UIFixtures.desk
        XCTAssertEqual(SidebarItem.resolve(.touchscreenCheck, in: desk), .touchscreenCheck)
        XCTAssertEqual(SidebarItem.resolve(nil, previous: .touchscreenCheck, in: desk), .touchscreenCheck,
                       "a click in the sidebar's empty space keeps it")
        XCTAssertEqual(SidebarItem.following(.touchscreenCheck, chosenByPerson: true, in: desk), .touchscreenCheck)
        XCTAssertEqual(SidebarItem.following(.touchscreenCheck, chosenByPerson: false, in: UIFixtures.snapshot(.nothingPaired)),
                       .touchscreenCheck, "only General gives way by itself")
    }

    // MARK: - General

    func testGeneralNoLongerListsTouchDevices() {
        XCTAssertEqual(GeneralPane.order, [.warnings, .tactile, .diagnostics, .experimental, .updates, .version])
        XCTAssertEqual(Set(GeneralPane.Group.allCases), Set(GeneralPane.order))
    }

    // MARK: - The Touchscreen Check pane

    /// Every connected touchscreen Tactile lists, with its name and its device's own name when it has
    /// another; then the touch devices it doesn't list. A remembered touchscreen isn't there.
    func testThePaneListsTheConnectedTouchscreensAndTheDevicesNotListed() throws {
        let model = PreviewModel(.desk)
        model.perform(.rename(UIFixtures.ilitek, to: "Main Touch"))
        let snapshot = model.snapshot
        let ilitek = try touchscreen(UIFixtures.ilitek, in: snapshot)
        let devices = [
            device(ilitek.usbID, location: ilitek.location),
            device("1234:5678", location: "01200000", kind: .mouseOnly, product: "Touch Bar Mouse", interface: 2),
            device("256c:006d", location: "01300000", kind: .digitizer, product: "", interface: 3),
        ]
        let list = TouchscreenCheckList(snapshot, devices: devices, finishing: SupportChecksFinishing())

        XCTAssertEqual(list.listed.map(\.id), [UIFixtures.ilitek, UIFixtures.strip], "connected only, in the sidebar's order")
        XCTAssertEqual(list.listed.map(\.name), ["Main Touch", "TouchScreen"])
        XCTAssertEqual(list.listed.map(\.deviceName), ["ILITEK-TP", nil], "the device's name, when the touchscreen has another")
        XCTAssertEqual(list.listed.first?.target, SupportTarget(ilitek))
        XCTAssertEqual(list.listed.map(\.availability), [.available, .available])

        XCTAssertEqual(list.unlisted.map(\.id), ["1234:5678@01200000", "256c:006d@01300000"],
                       "the ILITEK itself is listed, so it isn't here")
        XCTAssertEqual(list.unlisted.map(\.name), ["Touch Bar Mouse", "USB device 256c:006d"])
        XCTAssertEqual(list.unlisted.map(\.detail), ["Acts only as a mouse · 1234:5678", "A digitiser · 256c:006d"])
        XCTAssertEqual(list.unlisted.map(\.availability), [.available, .available])
    }

    func testThePaneWithNothingConnected() {
        var snapshot = UIFixtures.desk
        snapshot.touchscreens = snapshot.touchscreens.filter { !$0.isConnected }
        let list = TouchscreenCheckList(snapshot, devices: [], finishing: SupportChecksFinishing())
        XCTAssertTrue(list.listed.isEmpty, "a remembered touchscreen can't be checked")
        XCTAssertTrue(list.unlisted.isEmpty)
        XCTAssertEqual(Wording.noTouchscreens, "None connected")
        XCTAssertEqual(Wording.notListedNone, "No other touch devices are connected.")

        let empty = TouchscreenCheckList(UIFixtures.desk, devices: [], finishing: SupportChecksFinishing())
        XCTAssertEqual(empty.listed.count, 2)
        XCTAssertTrue(empty.unlisted.isEmpty, "no devices found: the not-listed group says none")
    }

    /// Each Check… follows `SupportCheckAvailability`: a set-up running, a check still letting go, a
    /// touchscreen or device that stopped answering. Each says why.
    func testEachCheckIsEnabledOrDisabledByTheAvailabilityRule() throws {
        let model = PreviewModel(.desk)
        let mouse = device("1234:5678", location: "01200000", kind: .mouseOnly, interface: 2)
        let digitiser = device("256c:006d", location: "01300000", kind: .digitizer, interface: 3)
        let other = device("0eef:0002", location: "01400000", interface: 4)

        let finishing = SupportChecksFinishing()
        finishing.began(touchscreen: UIFixtures.strip, device: "27c0:0859@x")
        finishing.began(touchscreen: nil, device: mouse.id)
        finishing.stoppedAnswering(digitiser)
        var snapshot = model.snapshot
        if let index = snapshot.touchscreens.firstIndex(where: { $0.id == UIFixtures.ilitek }) {
            snapshot.touchscreens[index].status = .stoppedAnswering
        }
        let list = TouchscreenCheckList(snapshot, devices: [mouse, digitiser, other], finishing: finishing)
        XCTAssertEqual(list.listed.map(\.availability), [.stoppedAnswering, .lastCheckFinishing])
        XCTAssertEqual(list.unlisted.map(\.availability), [.lastCheckFinishing, .stoppedAnswering, .available])
        XCTAssertEqual(list.listed.map(\.reason), ["It stopped answering. Unplug it and plug it back in.",
                                                   "The last check is still finishing. Try again in a moment."])
        XCTAssertNil(list.unlisted.last?.reason)

        model.perform(.beginSetUpMode)
        let settingUp = TouchscreenCheckList(model.snapshot, devices: [other], finishing: SupportChecksFinishing())
        XCTAssertEqual(settingUp.listed.map(\.availability), [.setUpRunning, .setUpRunning])
        XCTAssertEqual(settingUp.unlisted.map(\.availability), [.setUpRunning], "a device Tactile doesn't list waits too")
        XCTAssertEqual(settingUp.unlisted.first?.reason, "Not while a set-up runs.")
    }

    func testThePanesWords() {
        XCTAssertEqual(Wording.checkIntro,
                       "Check what a touchscreen sends. You can then send the results to Tactile’s developer, to help it work fully.")
        XCTAssertEqual(Wording.checkButton, "Check…")
        XCTAssertEqual(Wording.notListedTitle, "Touchscreen Not Listed?")
        XCTAssertEqual(Wording.notListedExplanation,
                       "Touch devices Tactile doesn’t list show here: digitisers, and touchscreens that only act as a mouse. "
                       + "Check one, so Tactile can learn to support it.")
    }

    // MARK: - A touchscreen's header

    /// The status line goes only when it says "Paired with …", which the Display row beneath says too;
    /// every other status, and a touchscreen being set up, keeps it.
    func testTheStatusLineIsHiddenOnlyWhenItSaysPairedWith() throws {
        let desk = UIFixtures.desk
        let ilitek = try touchscreen(UIFixtures.ilitek, in: desk)
        XCTAssertTrue(Wording.statusLine(for: ilitek).hasPrefix("Paired with "))
        XCTAssertFalse(TouchscreenHeaderContent(ilitek, in: desk).showsStatusLine)

        var shown: [(String, TouchscreenSnapshot, AppSnapshot)] = []
        shown.append(("not set up", try touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.nothingPaired)),
                      UIFixtures.snapshot(.nothingPaired)))
        shown.append(("not connected", try touchscreen(UIFixtures.oldPanel, in: desk), desk))
        shown.append(("Tactile off", try touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.tactileOff)),
                      UIFixtures.snapshot(.tactileOff)))
        shown.append(("no Accessibility", try touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.accessibilityMissing)),
                      UIFixtures.snapshot(.accessibilityMissing)))
        shown.append(("display away", try touchscreen(UIFixtures.ilitek, in: UIFixtures.snapshot(.displayUnplugged)),
                      UIFixtures.snapshot(.displayUnplugged)))
        let off = PreviewModel(.desk)
        off.perform(.setTouchscreenOn(UIFixtures.ilitek, false))
        shown.append(("off", try touchscreen(UIFixtures.ilitek, in: off.snapshot), off.snapshot))
        var stopped = ilitek
        stopped.status = .stoppedAnswering
        shown.append(("stopped answering", stopped, desk))
        let mode = PreviewModel(.desk)
        mode.perform(.beginSetUpMode)
        let settingUp = try touchscreen(UIFixtures.ilitek, in: mode.snapshot)
        XCTAssertEqual(settingUp.mode, .settingUp)
        shown.append(("being set up", settingUp, mode.snapshot))
        for (name, touchscreen, snapshot) in shown {
            XCTAssertFalse(Wording.statusLine(for: touchscreen).hasPrefix("Paired with "), name)
            XCTAssertTrue(TouchscreenHeaderContent(touchscreen, in: snapshot).showsStatusLine, name)
        }
    }

    /// Check This Touchscreen…: for a connected touchscreen only, enabled only when the check can
    /// start, with the reason otherwise.
    func testCheckThisTouchscreenInTheHeader() throws {
        let desk = UIFixtures.desk
        let ilitek = try touchscreen(UIFixtures.ilitek, in: desk)
        XCTAssertEqual(TouchscreenHeaderContent(ilitek, in: desk).check, .available)
        XCTAssertNil(TouchscreenHeaderContent(try touchscreen(UIFixtures.oldPanel, in: desk), in: desk).check,
                     "not connected: not shown")
        XCTAssertEqual(TouchscreenHeaderContent(ilitek, in: desk, finishing: true).check, .lastCheckFinishing)

        let twins = UIFixtures.snapshot(.identicalTwins)
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertEqual(TouchscreenHeaderContent(twin, in: twins).check, .available, "one Tactile can't use is the kind to check")

        let mode = PreviewModel(.desk)
        mode.perform(.beginSetUpMode)
        XCTAssertEqual(TouchscreenHeaderContent(try touchscreen(UIFixtures.ilitek, in: mode.snapshot), in: mode.snapshot).check,
                       .setUpRunning)
        var stopped = ilitek
        stopped.status = .stoppedAnswering
        XCTAssertEqual(TouchscreenHeaderContent(stopped, in: desk).check, .stoppedAnswering)
        XCTAssertEqual(Wording.checkThisTouchscreen, "Check This Touchscreen…")
    }

    // MARK: - Set-up mode's session card

    private func session(_ snapshot: AppSnapshot) throws -> SetUpModeSession {
        try XCTUnwrap(SetUpScreens.plan(snapshot).lazy.compactMap(\.role.session).first)
    }

    func testWithOneTouchscreenTheCardOffersCheckThisTouchscreen() throws {
        let model = PreviewModel(.desk)
        model.simulate(.touchscreenConnected(UIFixtures.strip, false))
        model.perform(.beginSetUpMode)
        let card = try session(model.snapshot)
        XCTAssertEqual(card.lines.map(\.id), [UIFixtures.ilitek])
        XCTAssertEqual(card.checkOffer, .one(UIFixtures.ilitek))
        XCTAssertEqual(card.checks, [UIFixtures.ilitek: .available], "as it will be once set-up has let go")
        XCTAssertEqual(Wording.setUpModeCheckLine, "Touch not working right?")
        XCTAssertEqual(Wording.checkThisTouchscreen, "Check This Touchscreen…")
    }

    func testWithSeveralEachLineOffersCheck() throws {
        let model = PreviewModel(.identicalTwins)
        model.perform(.beginSetUpMode)
        let card = try session(model.snapshot)
        XCTAssertEqual(card.lines.count, 3)
        XCTAssertEqual(card.checkOffer, .eachLine)
        XCTAssertEqual(Set(card.checks.keys), Set(card.lines.map(\.id)), "every line, one that can't be set up too")
        XCTAssertTrue(card.checks.values.allSatisfy { $0 == .available })
        XCTAssertEqual(Wording.setUpModeCheckEachLine, "Touch not working right? Click Check… beside the touchscreen.")
        XCTAssertEqual(Wording.checkButton, "Check…")
    }

    func testACardLineThatStoppedAnsweringSaysSo() {
        var stopped = UIFixtures.desk.touchscreens[0]
        stopped.status = .stoppedAnswering
        XCTAssertEqual(SupportCheckAvailability.leavingSetUp(stopped), .stoppedAnswering)
        XCTAssertEqual(SupportCheckAvailability.leavingSetUp(UIFixtures.desk.touchscreens[0]), .available)
        XCTAssertEqual(SupportCheckAvailability.leavingSetUp(UIFixtures.desk.touchscreens[0], finishing: true), .lastCheckFinishing)
    }

    /// Pressing it leaves set-up mode as Finish does, keeping what was set up, and only then opens
    /// that touchscreen's check, once set-up has let go of it.
    func testPressingItLeavesSetUpModeThenOpensTheCheck() throws {
        let model = PreviewModel(.desk)
        model.perform(.beginSetUpMode)
        let fhd = try XCTUnwrap(UIFixtures.displayID(named: "12.3FHD", in: model.snapshot))
        model.perform(.setUpChoose(displayID: fhd))
        model.simulate(.touch(UIFixtures.strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: nil))
        model.perform(.setUpDone)
        XCTAssertNotNil(model.snapshot.setUpMode, "back to the overview, the strip set up")

        var steps: [String] = []
        SetUpModeCheck.leaveThenCheck(
            UIFixtures.ilitek,
            perform: { command in
                steps.append("\(command)")
                model.perform(command)
            },
            snapshot: { model.snapshot },
            open: { target in
                steps.append("open \(target.id.rawValue)")
                XCTAssertNil(model.snapshot.setUpMode, "set-up mode has ended")
                XCTAssertNil(model.snapshot.setUp)
                XCTAssertNotEqual(model.snapshot.touchscreens.first { $0.id == target.id }?.mode, .settingUp,
                                  "set-up has let go of it")
            })
        XCTAssertEqual(steps, ["cancelSetUp", "open \(UIFixtures.ilitek.rawValue)"])
        XCTAssertEqual(try touchscreen(UIFixtures.strip, in: model.snapshot).pairedDisplayID, fhd, "what was set up stays")
    }

    /// The same with the model itself, on its fakes: set-up mode left, the touchscreen driving again,
    /// then the check opened; and the model lets go of it when the check begins.
    func testWithTheModelTheCheckOpensOnceSetUpModeHasLetGo() throws {
        let harness = try ModelHarness(settings: DeskFixture.settings)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.plugIn(DeskFixture.ilitek())
        harness.source.plugIn(DeskFixture.stripScreen())
        harness.model.start()
        harness.model.perform(.beginSetUpMode)
        XCTAssertEqual(harness.touchscreen(DeskFixture.ilitekID)?.mode, .settingUp)
        XCTAssertEqual(try session(harness.model.snapshot).checkOffer, .eachLine)

        var opened: [TouchscreenID] = []
        SetUpModeCheck.leaveThenCheck(
            DeskFixture.ilitekID, perform: { harness.model.perform($0) }, snapshot: { harness.model.snapshot },
            open: { target in
                opened.append(target.id)
                XCTAssertNil(harness.model.snapshot.setUpMode)
                XCTAssertEqual(harness.touchscreen(DeskFixture.ilitekID)?.mode, .driving, "set-up has let go of it")
                XCTAssertEqual(harness.touchscreen(DeskFixture.ilitekID).map { SupportCheckAvailability.of($0, in: harness.model.snapshot) },
                               .available)
            })
        XCTAssertEqual(opened, [DeskFixture.ilitekID])

        let claim = UUID()
        harness.model.perform(.beginSupportCheck(DeskFixture.ilitekID, claim: claim))
        XCTAssertEqual(harness.touchscreen(DeskFixture.ilitekID)?.mode, .released, "the check can take it")
        harness.model.perform(.endSupportCheck(claim: claim))
        XCTAssertEqual(harness.touchscreen(DeskFixture.ilitekID)?.mode, .driving)
    }

    /// Set-up mode that doesn't end (the model refused) opens no check: set-up still has the
    /// touchscreen.
    func testNoCheckOpensWhileSetUpStillHasTheTouchscreen() {
        let model = PreviewModel(.desk)
        model.perform(.beginSetUpMode)
        var opened = false
        SetUpModeCheck.leaveThenCheck(UIFixtures.ilitek, perform: { _ in }, snapshot: { model.snapshot },
                                      open: { _ in opened = true })
        XCTAssertFalse(opened)

        let gone = PreviewModel(.desk)
        gone.perform(.beginSetUpMode)
        SetUpModeCheck.leaveThenCheck(TouchscreenID(rawValue: "ffff:ffff:"), perform: { gone.perform($0) },
                                      snapshot: { gone.snapshot }, open: { _ in opened = true })
        XCTAssertNil(gone.snapshot.setUpMode, "it still leaves")
        XCTAssertFalse(opened, "a touchscreen that has gone isn't checked")
    }

    // MARK: - The words

    func testTheMenusDetailsAndTheCheckWindowSayCheckThisTouchscreen() {
        XCTAssertEqual(Wording.checkThisTouchscreen, "Check This Touchscreen…")
        XCTAssertEqual(Wording.supportWindowTitle(name: "Bar"), "Touchscreen Check: Bar", "the window's title stays")
    }

    func testEveryNewWordIsWrittenWithTypographicApostrophes() {
        for text in [Wording.checkIntro, Wording.checkThisTouchscreen, Wording.touchscreenCheck, Wording.setUpModeCheckLine,
                     Wording.setUpModeCheckEachLine] {
            XCTAssertFalse(text.contains("'"), text)
            XCTAssertFalse(text.contains("..."), text)
        }
    }

    /// Nothing the interface shows, and no document in the repository, still names the old entries.
    func testNothingSaysHelpMeSupportAnyMore() throws {
        let root = try Self.repositoryRoot()
        let files = FileManager.default
        var texts: [URL] = []
        let sources = root.appendingPathComponent("Packages/TactileKit/Sources/TactileApp")
        let enumerator = try XCTUnwrap(files.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("Wording") && url.pathExtension == "swift" {
            texts.append(url)
        }
        XCTAssertGreaterThanOrEqual(texts.count, 4, "the wording files")
        for folder in ["", "docs", ".github", ".github/ISSUE_TEMPLATE"] {
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder)
            for name in (try? files.contentsOfDirectory(atPath: url.path)) ?? []
            where name.hasSuffix(".md") || name.hasSuffix(".yml") {
                texts.append(url.appendingPathComponent(name))
            }
        }
        for url in texts {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("Help Me Support"), url.lastPathComponent)
            XCTAssertFalse(text.contains("Not Listed?** in General"), url.lastPathComponent)
        }
    }

    /// The repository's root (where Tactile.xcodeproj is), found from this file's own path.
    private static func repositoryRoot(from file: String = #filePath) throws -> URL {
        var folder = URL(fileURLWithPath: file).deletingLastPathComponent()
        while folder.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("Tactile.xcodeproj").path) {
                return folder
            }
            folder.deleteLastPathComponent()
        }
        throw XCTSkip("Not inside the repository: no Tactile.xcodeproj above \(file)")
    }
}
