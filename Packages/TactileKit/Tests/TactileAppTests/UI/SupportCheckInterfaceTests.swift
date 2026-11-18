import Foundation
@testable import TactileApp
import TactileDevices
import TactileScreens
import TactileSupport
import XCTest

/// The touchscreen check's interface, as rules and words: where it is offered, which devices
/// Touchscreen Not Listed? shows, what each step says, and what the "what will be sent" sheet offers
/// at each stage. No window is opened, and no device.
@MainActor
final class SupportCheckInterfaceTests: XCTestCase {

    private func device(_ usbID: String, location: String?, kind: SupportDeviceKind = .touchscreen, product: String = "Panel",
                        serial: String = "") -> SupportDevice {
        let parts = usbID.split(separator: ":").map { Int($0, radix: 16) ?? 0 }
        let locationID = location.flatMap { UInt32($0, radix: 16) } ?? 0
        return SupportDevice(
            id: "\(usbID)@\(location ?? "-")", kind: kind, vendorID: parts[0], productID: parts[1], product: product,
            manufacturer: "", serial: serial, locationID: locationID, interfaces: [])
    }

    // MARK: - Where it is offered

    func testEveryConnectedTouchscreenOffersTheCheckUnlessASetUpRuns() throws {
        let model = PreviewModel(.desk)
        let ilitek = try XCTUnwrap(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek })
        XCTAssertEqual(SupportCheckAvailability.of(ilitek, in: model.snapshot), .available)
        let old = try XCTUnwrap(model.snapshot.touchscreens.first { $0.id == UIFixtures.oldPanel })
        XCTAssertEqual(SupportCheckAvailability.of(old, in: model.snapshot), .notConnected)

        let twins = PreviewModel(.identicalTwins).snapshot
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        XCTAssertEqual(SupportCheckAvailability.of(twin, in: twins), .available, "one Tactile can't use is just the kind to check")

        model.perform(.beginSetUpMode)
        let settingUp = try XCTUnwrap(model.snapshot.touchscreens.first { $0.id == UIFixtures.ilitek })
        XCTAssertEqual(SupportCheckAvailability.of(settingUp, in: model.snapshot), .setUpRunning)
        XCTAssertEqual(Wording.supportUnavailable(.setUpRunning), "Not while a set-up runs.")
        XCTAssertEqual(Wording.supportUnavailable(.notConnected), "Connect it first.")
    }

    func testTheMenusDetailsOfferItForEveryConnectedTouchscreen() throws {
        let snapshot = PreviewModel(.desk).snapshot
        let details = MenuBarContent(snapshot).touchscreens.map(\.details)
        XCTAssertEqual(details.first { $0.id == UIFixtures.ilitek }?.support, .available)
        XCTAssertNil(details.first { $0.id == UIFixtures.oldPanel }?.support, "not connected: not offered")
        let twins = PreviewModel(.identicalTwins).snapshot
        let twin = try XCTUnwrap(MenuBarContent(twins).touchscreens.first { $0.details.unusable != nil }).details
        XCTAssertEqual(twin.support, .available, "offered even where nothing else is")
    }

    // MARK: - Touchscreen Not Listed?

    func testNotListedShowsWhatTactileDoesntList() throws {
        let snapshot = PreviewModel(.desk).snapshot
        let listed = try XCTUnwrap(snapshot.touchscreens.first { $0.isConnected })
        let devices = [
            device(listed.usbID, location: listed.location),
            device(listed.usbID, location: "02200000"),
            device("1234:5678", location: "01200000", kind: .mouseOnly),
            device("256c:006d", location: "01300000", kind: .digitizer),
        ]
        XCTAssertEqual(SupportDeviceMatching.unlisted(devices, in: snapshot).map(\.id),
                       ["\(listed.usbID)@02200000", "1234:5678@01200000", "256c:006d@01300000"],
                       "another unit of a listed model, elsewhere, is not listed")
        XCTAssertEqual(SupportDeviceMatching.device(for: listed, among: devices)?.id, "\(listed.usbID)@\(listed.location ?? "")")
    }

    func testATouchscreenWithoutALocationIsFoundByItsSerial() {
        var listed = PreviewModel(.desk).snapshot.touchscreens[0]
        listed.location = nil
        let devices = [device(listed.usbID, location: nil, serial: "OTHER"), device(listed.usbID, location: nil, serial: listed.serial)]
        XCTAssertEqual(SupportDeviceMatching.device(for: listed, among: devices)?.serial, listed.serial)
    }

    func testNotListedWording() {
        XCTAssertEqual(Wording.notListedTitle, "Touchscreen Not Listed?")
        XCTAssertEqual(Wording.interfacesLine([.touch, .mouse]), "2 interfaces: touch and mouse.")
        XCTAssertEqual(Wording.interfacesLine([.touch, .mouse, .other]), "3 interfaces: touch, mouse and 1 other.")
        XCTAssertEqual(Wording.interfacesLine([.pointer]), "1 interface: pointer.")
        XCTAssertEqual(Wording.supportDeviceName(device("1234:5678", location: nil, product: "")), "USB device 1234:5678")
        XCTAssertEqual(Wording.supportDeviceName(device("1234:5678", location: nil, product: "Panel X")), "Panel X")
        XCTAssertEqual(Wording.notListedDetail(device("1234:5678", location: nil, kind: .mouseOnly)), "Acts only as a mouse · 1234:5678")
        XCTAssertEqual(Wording.notListedDetail(device("256c:006d", location: nil, kind: .digitizer)), "A digitiser · 256c:006d")
        XCTAssertEqual(Wording.notListedDetail(device("222a:0001", location: nil)), "A touchscreen · 222a:0001")
    }

    // MARK: - The steps

    func testTheStepMarks() {
        var one = SupportTouchStep(fingers: .one, startedAt: 0)
        one.ending = .done
        var two = SupportTouchStep(fingers: .two, startedAt: 2)
        two.ending = .skipped
        let five = SupportTouchStep(fingers: .five, startedAt: 3)
        XCTAssertEqual(SupportStepMarks(stage: .ready, steps: []).marks, [.current, .pending, .pending, .pending])
        XCTAssertEqual(SupportStepMarks(stage: .touching(.five), steps: [one, two, five]).marks, [.done, .done, .current, .pending])
        XCTAssertEqual(SupportStepMarks(stage: .finished, steps: [one, two]).marks, [.done, .done, .done, .done])
        XCTAssertEqual(SupportStepMarks(stage: .finished, steps: []).marks, [.done, .skipped, .skipped, .done],
                       "a check that couldn't take the device")
    }

    func testTheTouchPromptsAndCounts() {
        XCTAssertEqual(Wording.touchPrompt(.one), "Touch the screen with one finger. Hold it still for a moment, then move it.")
        XCTAssertEqual(Wording.touchPrompt(.two), "Now touch it with two fingers, and move them.")
        XCTAssertEqual(Wording.touchPrompt(.five), "Now touch it with five fingers, and move them.")
        XCTAssertEqual(Wording.touchStepOf(.two), "Step 2 of 3")
        XCTAssertEqual(Wording.secondsLeft(12.2), "13 s")
        XCTAssertEqual(Wording.secondsLeft(-1), "0 s")
        XCTAssertEqual(Wording.fingersSeen(0), "Nothing yet.")
        XCTAssertEqual(Wording.fingersSeen(1), "Seen: 1 finger.")
        XCTAssertEqual(Wording.fingersSeen(5), "Seen: up to 5 fingers at once.")
    }

    func testTheVerdicts() {
        XCTAssertEqual(Wording.verdictTitle(.worksFully), "Works fully")
        XCTAssertEqual(Wording.verdictTitle(.worksWithOneFinger), "Works with one finger")
        XCTAssertEqual(Wording.verdictTitle(.doesNotWork), "Doesn’t work")
        XCTAssertEqual(Wording.verdictSentence(.severalFingersFromTouchInterface),
                       "Tactile saw several fingers at once through its touch interface.")
        XCTAssertEqual(Wording.verdictSentence(.oneFingerFromTouchInterface), "Tactile only saw one finger at a time.")
        XCTAssertEqual(Wording.verdictSentence(.oneFingerFromMouseInterface), "It only sends one finger, as a mouse.")
        XCTAssertEqual(Wording.verdictSentence(.reportsNotReadable), "Its reports came, but Tactile couldn’t read a touch from them.")
        XCTAssertEqual(Wording.verdictSentence(.noReports), "Nothing came from it.")
        XCTAssertEqual(Wording.supportInterruption(.unplugged), "It was unplugged, so the check stopped.")
        XCTAssertEqual(Wording.supportInterruption(.notConnected), "It wasn’t connected when the check began.")
        XCTAssertNil(Wording.supportInterruption(.stopped))
        XCTAssertEqual(Wording.sendToDeveloper, "Send to Tactile’s Developer…")
    }

    // MARK: - The sheet

    func testTheFormIsCheckedAsTheSiteChecksIt() {
        var form = SupportSendForm()
        XCTAssertFalse(form.isReady)
        XCTAssertNil(form.emailProblem, "nothing to say about an empty field")
        form.email = "someone@"
        XCTAssertEqual(form.emailProblem, "That email address doesn’t look right.")
        form.email = " someone@example.com "
        XCTAssertNil(form.emailProblem)
        XCTAssertTrue(form.isReady)
        form.note = String(repeating: "a", count: 1001)
        XCTAssertEqual(form.noteProblem, "The note is longer than 1,000 characters.")
        XCTAssertFalse(form.isReady)
        XCTAssertEqual(form.noteCount, "1,001 / 1,000")
    }

    func testWhatTheSheetOffersAtEachStage() {
        var ready = SupportSendForm()
        ready.email = "someone@example.com"
        typealias Content = SupportSendSheetContent

        let off = Content(stage: .off, form: ready, saved: false)
        XCTAssertFalse(off.showsForm)
        XCTAssertFalse(off.showsSend)
        XCTAssertEqual(off.message, "This build of Tactile doesn’t send reports. Save the report, then attach it to a touchscreen report on GitHub.")
        XCTAssertTrue(off.showsGitHub)

        let checking = Content(stage: .checking, form: ready, saved: false)
        XCTAssertFalse(checking.showsForm)
        XCTAssertEqual(checking.message, "Checking whether reports can be sent…")

        let form = Content(stage: .ready, form: ready, saved: false)
        XCTAssertTrue(form.showsForm)
        XCTAssertTrue(form.showsSend)
        XCTAssertTrue(form.sendEnabled)
        XCTAssertNil(form.message)
        XCTAssertFalse(Content(stage: .ready, form: SupportSendForm(), saved: false).sendEnabled, "no email yet")

        let sending = Content(stage: .sending, form: ready, saved: false)
        XCTAssertFalse(sending.formIsEnabled)
        XCTAssertFalse(sending.sendEnabled)

        let sent = Content(stage: .sent, form: ready, saved: false)
        XCTAssertEqual(sent.message, "Check your email to confirm. Nothing is filed until you do.")
        XCTAssertFalse(sent.showsSend)
        XCTAssertFalse(sent.showsSaveReport)

        let refused = Content(stage: .refused("We couldn't email you; check the address."), form: ready, saved: false)
        XCTAssertEqual(refused.message, "We couldn't email you; check the address.")
        XCTAssertTrue(refused.formIsEnabled, "the person can fix the email and send again")
        XCTAssertTrue(refused.sendEnabled)

        let later = Content(stage: .tryLater, form: ready, saved: false)
        XCTAssertEqual(later.message, "Too many reports from here just now. Try again later, or save the report.")
        let slow = Content(stage: .tooSlow, form: ready, saved: false)
        XCTAssertEqual(slow.message, "Sending took too long. You can save the report instead.")
        XCTAssertTrue(slow.showsSaveReport)
        XCTAssertTrue(slow.sendEnabled, "or try again")

        let unavailable = Content(stage: .unavailable, form: ready, saved: false)
        XCTAssertFalse(unavailable.showsForm)
        XCTAssertEqual(unavailable.message, "Sending isn’t available yet. Save the report, then attach it to a touchscreen report on GitHub.")
        XCTAssertTrue(unavailable.showsGitHub)

        let saved = Content(stage: .ready, form: ready, saved: true)
        XCTAssertTrue(saved.showsGitHub, "once saved, GitHub is offered")
    }

    func testTheSheetsWords() {
        XCTAssertEqual(Wording.supportPrivacy, "We use this only to help with your touchscreen, and delete it on request.")
        XCTAssertEqual(Wording.githubIsPublic,
                       "GitHub issues are public. The report holds no personal data: only the files listed above.")
        XCTAssertEqual(Wording.openGitHubReport, "Open a Touchscreen Report on GitHub")
        XCTAssertEqual(Wording.saveReport, "Save Report…")
        XCTAssertEqual(SupportLinks.touchscreenReport.absoluteString,
                       "https://github.com/crissmoldovan/tactile-mac/issues/new?template=touchscreen_report.yml")
        XCTAssertEqual(Wording.fileSize(812), "812 bytes")
        XCTAssertEqual(Wording.fileSize(1), "1 byte")
        XCTAssertEqual(Wording.fileSize(15_360), "15 KB")
        XCTAssertEqual(Wording.fileSize(1_572_864), "1.5 MB")
        XCTAssertEqual(Wording.reportFileName(usbID: "222a:0001"), "tactile-report-222a-0001.zip")
    }

    func testEveryWordIsWrittenWithTypographicApostrophes() {
        let words = [
            Wording.helpMeSupport, Wording.supportExplanation, Wording.notListedExplanation, Wording.notListedNone,
            Wording.supportIntro, Wording.supportLetGo, Wording.supportStepSentence(0, kind: .touchscreen),
            Wording.supportStepSentence(1, kind: .mouseOnly), Wording.supportStepSentence(2, kind: .touchscreen),
            Wording.supportStepSentence(3, kind: .touchscreen), Wording.sendSheetIntro, Wording.sendToDeveloper,
            Wording.verdictTitle(.doesNotWork), Wording.supportCantFind,
        ]
        for text in words {
            XCTAssertFalse(text.contains("'"), text)
        }
    }
}
