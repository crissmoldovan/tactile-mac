import AppKit
import SwiftUI
import TactileUpdates
import XCTest

@testable import TactileApp

/// The updater's words and what the menu, the update window and General show for each of its states.
/// Nothing here opens a window or touches the network: the views are drawn by hosting views never put
/// in one.
@MainActor
final class UpdatesInterfaceTests: XCTestCase {

    private static let offer = UpdateOffer(
        version: ReleaseVersion("0.6.0")!, build: 412, minimumSystemVersion: SystemVersion(major: 14),
        publishedAt: Date(timeIntervalSince1970: 1_794_996_000), notes: "Faster scrolling.\nPinch is smoother.",
        archive: .init(url: URL(string: "https://tactilemac.com/api/mac/archive/0.6.0")!, size: 7_340_032,
                       sha256: String(repeating: "a", count: 64), signature: Data(count: 64), keyID: "k1"))

    private static func state(_ phase: UpdatePhase = .idle, available: UpdateOffer? = nil, notice: UpdateNotice? = nil,
                              site: String = "tactilemac.com") -> UpdateState {
        UpdateState(phase: phase, available: available, notice: notice, runningVersion: "0.5.0", siteHost: site)
    }

    /// Every reason a check or an install stops, one of each.
    static let everyFailure: [UpdateFailure] = [
        .siteUnreachable, .siteFailed(status: 503), .answerNotFromSite, .answerUnreadable(.notJSON), .translocated,
        .folderNotWritable(folder: "/Applications"), .archiveNotOnSite, .downloadFailed, .downloadNotFromSite,
        .sizeMismatch(expected: 2, actual: 1), .digestMismatch, .unknownKey("k9"), .badSignature, .unpackFailed,
        .notOneApp, .codeSignatureInvalid, .versionMismatch, .notNewer, .couldNotPrepare, .helperDidNotStart, .cancelled,
    ]

    // MARK: - Words

    func testTheWordsOfTheMenuAndTheWindow() {
        XCTAssertEqual(Wording.checkForUpdates, "Check for Updates…")
        XCTAssertEqual(Wording.updateTo("0.6.0"), "Update to 0.6.0…")
        XCTAssertEqual(Wording.installAndRelaunch, "Install and Relaunch")
        XCTAssertEqual(Wording.later, "Later")
        XCTAssertEqual(Wording.newestVersion("0.5.0"), "Tactile 0.5.0 is the newest version.")
        XCTAssertEqual(Wording.downloadingUpdate("0.6.0"), "Downloading Tactile 0.6.0…")
        XCTAssertEqual(Wording.verifyingUpdate("0.6.0"), "Verifying Tactile 0.6.0…")
        XCTAssertEqual(Wording.installingUpdate("0.6.0"), "Installing Tactile 0.6.0…")
        XCTAssertEqual(Wording.updateAvailable("0.6.0"), "Tactile 0.6.0 is available")
        XCTAssertEqual(Wording.youHave("0.5.0"), "You have Tactile 0.5.0.")
        XCTAssertEqual(Wording.needsNewerMacOS(version: "0.6.0", minimum: "15.0"), "Tactile 0.6.0 needs macOS 15.0 or later.")
        XCTAssertEqual(Wording.checkAutomatically, "Check for updates automatically")
        XCTAssertEqual(Wording.checkAutomaticallyExplanation(site: "tactilemac.com"),
                       "Once a day, from tactilemac.com. Nothing is installed until you choose to.")
    }

    func testEveryFailureSaysWhyInItsOwnLine() {
        let lines = Self.everyFailure.map { Wording.updateFailure($0, site: "tactilemac.com") }
        XCTAssertEqual(Set(lines).count, lines.count, "each reason its own words")
        for (failure, line) in zip(Self.everyFailure, lines) {
            XCTAssertFalse(line.isEmpty, failure.name)
            XCTAssertTrue(line.hasSuffix("."), failure.name)
            XCTAssertFalse(line.contains("'"), "typographic apostrophes: \(failure.name)")
            XCTAssertFalse(line.contains("\n"), "one line: \(failure.name)")
        }
        XCTAssertEqual(Wording.updateFailure(.siteUnreachable, site: "tactilemac.com"),
                       "Tactile couldn’t reach tactilemac.com. Check the connection, then try again.")
        XCTAssertEqual(Wording.updateFailure(.siteFailed(status: 502), site: "tactilemac.com"),
                       "tactilemac.com couldn’t answer just now (error 502). Try again later.")
        XCTAssertEqual(Wording.updateFailure(.folderNotWritable(folder: "/Applications"), site: "tactilemac.com"),
                       "Tactile can’t replace itself in “Applications”. Download the new version from tactilemac.com instead.")
        XCTAssertEqual(Wording.updateFailure(.codeSignatureInvalid, site: "tactilemac.com"),
                       "The new Tactile isn’t signed by its developer.")
    }

    func testTheSiteIsNamedAsTactileAsksIt() {
        XCTAssertEqual(Wording.updateFailure(.siteUnreachable, site: "preview.example.com"),
                       "Tactile couldn’t reach preview.example.com. Check the connection, then try again.")
    }

    func testWhenTheLastCheckWas() throws {
        XCTAssertEqual(Wording.lastChecked(nil), "Not checked yet")
        let gb = Locale(identifier: "en_GB"), utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertTrue(Wording.lastChecked(Date(), locale: gb, timeZone: utc).hasPrefix("Last checked today at "),
                      Wording.lastChecked(Date(), locale: gb, timeZone: utc))
        XCTAssertEqual(Wording.lastChecked(Date(timeIntervalSince1970: 1_700_000_000), locale: gb, timeZone: utc),
                       "Last checked 14 Nov 2023 at 22:13")
    }

    // MARK: - The menu

    func testTheMenuWithNothingToSay() {
        let content = UpdateMenuContent(Self.state())
        XCTAssertNil(content.updateTitle)
        XCTAssertTrue(content.canCheck)
        XCTAssertNil(content.line)
    }

    func testTheMenuOffersANewerVersion() {
        let content = UpdateMenuContent(Self.state(available: Self.offer))
        XCTAssertEqual(content.updateTitle, "Update to 0.6.0…")
        XCTAssertTrue(content.canCheck)
    }

    func testTheMenuShowsAManualCheckButNotAnAutomaticOne() {
        let manual = UpdateMenuContent(Self.state(.checking(manual: true)))
        XCTAssertEqual(manual.line, "Checking for updates…")
        XCTAssertFalse(manual.canCheck)
        let automatic = UpdateMenuContent(Self.state(.checking(manual: false)))
        XCTAssertNil(automatic.line, "an automatic check says nothing")
        XCTAssertTrue(automatic.canCheck, "choosing it makes the check a manual one")
    }

    func testTheMenuShowsAnInstallUnderWay() {
        let downloading = UpdateMenuContent(Self.state(.downloading(Self.offer), available: Self.offer))
        XCTAssertEqual(downloading.line, "Downloading Tactile 0.6.0…")
        XCTAssertEqual(downloading.updateTitle, "Update to 0.6.0…", "it opens the window with the progress")
        XCTAssertFalse(downloading.canCheck)
        let verifying = UpdateMenuContent(Self.state(.verifying(Self.offer), available: Self.offer))
        XCTAssertEqual(verifying.line, "Verifying Tactile 0.6.0…")
        let installing = UpdateMenuContent(Self.state(.installing(Self.offer), available: Self.offer))
        XCTAssertEqual(installing.line, "Installing Tactile 0.6.0…")
        XCTAssertNil(installing.updateTitle)
        XCTAssertFalse(installing.canCheck)
    }

    func testTheMenuSaysWhatTheLastManualCheckOrInstallFound() {
        XCTAssertEqual(UpdateMenuContent(Self.state(notice: .upToDate)).line, "Tactile 0.5.0 is the newest version.")
        XCTAssertEqual(UpdateMenuContent(Self.state(notice: .checkFailed(.siteUnreachable))).line,
                       "Tactile couldn’t reach tactilemac.com. Check the connection, then try again.")
        XCTAssertEqual(UpdateMenuContent(Self.state(available: Self.offer, notice: .installFailed(.badSignature))).line,
                       "The update’s signature doesn’t match it.")
        XCTAssertEqual(UpdateMenuContent(Self.state(notice: .needsNewerSystem(Self.offer))).line,
                       "Tactile 0.6.0 needs macOS 14.0 or later.")
    }

    /// The panel itself, with the updater's rows: they add to it, and without an updater it is as
    /// before.
    func testThePanelDrawsTheUpdatersRows() throws {
        let content = MenuBarContent(PreviewModel(.desk).snapshot)
        func height(_ updates: UpdateMenuContent?) -> CGFloat {
            let host = NSHostingView(rootView: MenuBarPanel(
                content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {}, updates: updates))
            return host.fittingSize.height
        }
        let without = height(nil)
        let check = height(UpdateMenuContent(Self.state()))
        let offered = height(UpdateMenuContent(Self.state(available: Self.offer, notice: .upToDate)))
        XCTAssertGreaterThan(check, without, "Check for Updates…")
        XCTAssertGreaterThan(offered, check, "Update to 0.6.0… and the line beneath Check for Updates…")
    }

    // MARK: - The update window

    func testTheWindowWhileAManualCheckRuns() {
        let content = UpdateWindowContent(Self.state(.checking(manual: true)))
        XCTAssertEqual(content.title, "Checking for updates…")
        XCTAssertTrue(content.isBusy)
        XCTAssertNil(content.primary)
        XCTAssertEqual(content.secondary, .cancel)
        XCTAssertFalse(content.closingDismisses, "closing it lets the check go on")
    }

    func testTheWindowWhenNothingIsNewer() {
        let content = UpdateWindowContent(Self.state(notice: .upToDate))
        XCTAssertEqual(content.title, "Tactile 0.5.0 is the newest version.")
        XCTAssertEqual(content.primary, .ok)
        XCTAssertNil(content.secondary)
        XCTAssertTrue(content.closingDismisses)
    }

    func testTheWindowWhenACheckFailed() {
        let content = UpdateWindowContent(Self.state(notice: .checkFailed(.siteFailed(status: 503))))
        XCTAssertEqual(content.title, "Tactile couldn’t check for updates")
        XCTAssertEqual(content.line, "tactilemac.com couldn’t answer just now (error 503). Try again later.")
        XCTAssertTrue(content.lineIsProblem)
        XCTAssertEqual(content.primary, .ok)
    }

    func testTheWindowOffersANewerVersion() {
        let content = UpdateWindowContent(Self.state(available: Self.offer))
        XCTAssertEqual(content.title, "Tactile 0.6.0 is available")
        XCTAssertEqual(content.subtitle, "You have Tactile 0.5.0.")
        XCTAssertEqual(content.notes, ["Faster scrolling.", "Pinch is smoother."])
        XCTAssertEqual(content.primary, .install)
        XCTAssertTrue(content.primaryIsEnabled)
        XCTAssertEqual(content.secondary, .later)
        XCTAssertEqual(content.primary?.title, "Install and Relaunch")
        XCTAssertEqual(content.secondary?.title, "Later")
        XCTAssertNil(content.line)
    }

    func testTheWindowDuringAnInstall() {
        let downloading = UpdateWindowContent(Self.state(.downloading(Self.offer), available: Self.offer))
        XCTAssertEqual(downloading.line, "Downloading Tactile 0.6.0…")
        XCTAssertTrue(downloading.isBusy)
        XCTAssertFalse(downloading.primaryIsEnabled)
        XCTAssertEqual(downloading.secondary, .cancel)
        XCTAssertFalse(downloading.closingDismisses, "closing it lets the download go on")
        let verifying = UpdateWindowContent(Self.state(.verifying(Self.offer), available: Self.offer))
        XCTAssertEqual(verifying.line, "Verifying Tactile 0.6.0…")
        let installing = UpdateWindowContent(Self.state(.installing(Self.offer), available: Self.offer))
        XCTAssertEqual(installing.line, "Installing Tactile 0.6.0… Tactile will quit and open again in a moment.")
        XCTAssertFalse(installing.primaryIsEnabled)
        XCTAssertNil(installing.secondary, "an install whose helper runs can't be stopped")
    }

    func testTheWindowAfterAnInstallFailed() {
        let content = UpdateWindowContent(Self.state(available: Self.offer, notice: .installFailed(.codeSignatureInvalid)))
        XCTAssertEqual(content.title, "Tactile 0.6.0 is available")
        XCTAssertEqual(content.line, "The new Tactile isn’t signed by its developer.")
        XCTAssertTrue(content.lineIsProblem)
        XCTAssertEqual(content.primary, .install, "it can be tried again")
        XCTAssertTrue(content.primaryIsEnabled)
    }

    func testTheWindowForAVersionThisMacCantRun() {
        let content = UpdateWindowContent(Self.state(notice: .needsNewerSystem(Self.offer)))
        XCTAssertEqual(content.title, "Tactile 0.6.0 is available")
        XCTAssertEqual(content.line, "Tactile 0.6.0 needs macOS 14.0 or later.")
        XCTAssertEqual(content.primary, .ok)
        XCTAssertNil(content.secondary)
    }

    func testNothingInstallsDuringAnAutomaticCheck() {
        let content = UpdateWindowContent(Self.state(.checking(manual: false), available: Self.offer))
        XCTAssertEqual(content.primary, .install)
        XCTAssertFalse(content.primaryIsEnabled)
    }

    func testLongNotesScroll() {
        XCTAssertTrue(UpdateNotes.fitWhole(["One.", "Two."]))
        XCTAssertFalse(UpdateNotes.fitWhole(Array(repeating: "A paragraph.", count: 6)))
        XCTAssertFalse(UpdateNotes.fitWhole([String(repeating: "x", count: 421)]))
    }

    func testTheWindowDrawsEveryState() {
        let states = [
            Self.state(.checking(manual: true)), Self.state(notice: .upToDate),
            Self.state(available: Self.offer), Self.state(.downloading(Self.offer), available: Self.offer),
            Self.state(available: Self.offer, notice: .installFailed(.notNewer)),
        ]
        for state in states {
            let host = NSHostingView(rootView: UpdateWindowLayout(content: UpdateWindowContent(state), act: { _ in }))
            XCTAssertEqual(host.fittingSize.width, UpdateWindow.width, accuracy: 1, "\(state.phase)")
            XCTAssertGreaterThan(host.fittingSize.height, 80, "\(state.phase)")
        }
    }

    // MARK: - General

    func testGeneralsUpdatesGroup() throws {
        let gb = Locale(identifier: "en_GB"), utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var state = Self.state()
        state.lastChecked = Date(timeIntervalSince1970: 1_700_000_000)
        let idle = UpdatesSettingsContent(state, locale: gb, timeZone: utc)
        XCTAssertTrue(idle.checksAutomatically)
        XCTAssertEqual(idle.explanation, "Once a day, from tactilemac.com. Nothing is installed until you choose to.")
        XCTAssertEqual(idle.lastChecked, "Last checked 14 Nov 2023 at 22:13")
        XCTAssertEqual(idle.buttonTitle, "Check for Updates…")
        XCTAssertFalse(idle.buttonOpensUpdate)
        XCTAssertTrue(idle.buttonIsEnabled)
        XCTAssertNil(idle.line)

        state.available = Self.offer
        let offered = UpdatesSettingsContent(state, locale: gb, timeZone: utc)
        XCTAssertEqual(offered.buttonTitle, "Update to 0.6.0…")
        XCTAssertTrue(offered.buttonOpensUpdate)

        state.available = nil
        state.phase = .checking(manual: true)
        state.checksAutomatically = false
        let checking = UpdatesSettingsContent(state, locale: gb, timeZone: utc)
        XCTAssertFalse(checking.checksAutomatically)
        XCTAssertFalse(checking.buttonIsEnabled)
        XCTAssertEqual(checking.line, "Checking for updates…")
        XCTAssertEqual(UpdatesSettingsContent(Self.state()).lastChecked, "Not checked yet")
    }

    func testGeneralDrawsTheGroup() {
        let host = NSHostingView(rootView: Form {
            UpdatesSectionContent(content: UpdatesSettingsContent(Self.state(available: Self.offer)),
                                  setAutomatic: { _ in }, press: { _ in })
        }.formStyle(.grouped).frame(width: 600))
        XCTAssertGreaterThan(host.fittingSize.height, 60)
    }

    /// Without an updater (tests, previews) the app shows nothing of updates.
    func testNoUpdaterNoRows() {
        XCTAssertNil(AppUpdates.shared.controller)
        XCTAssertNil(AppUpdates.shared.menuContent)
        XCTAssertFalse(AppUpdates.shared.isOff)
    }

    // MARK: - A build that doesn't update itself

    func testABuildThatDoesntUpdateSaysSoPlainly() {
        XCTAssertEqual(Wording.updatesOff, "Updates are off in this build of Tactile.")
        let menu = UpdateMenuContent.off
        XCTAssertNil(menu.updateTitle)
        XCTAssertFalse(menu.canCheck, "Check for Updates… can't be chosen")
        XCTAssertEqual(menu.line, "Updates are off in this build of Tactile.")
    }

    /// A build that isn't the official one makes no updater, so nothing asks any site; the menu and
    /// General say updates are off.
    func testABuildThatIsntOfficialMakesNoUpdater() {
        let updates = AppUpdates()
        updates.start(availability: .off(.notSignedByTheDeveloper))
        XCTAssertNil(updates.controller)
        XCTAssertTrue(updates.isOff)
        XCTAssertEqual(updates.menuContent, .off)
        updates.start(availability: .off(.otherBundleIdentifier))
        XCTAssertNil(updates.controller, "started once")
        XCTAssertEqual(updates.menuContent, .off)
        let unusable = AppUpdates()
        unusable.start(availability: .off(.unusableSetting("TactileUpdateKeys")))
        XCTAssertNil(unusable.controller)
        XCTAssertEqual(unusable.menuContent, .off)
        XCTAssertFalse(UpdatesLog.isOn, "only the app turns the updater's log on, in start(); a test leaves it off")
    }

    func testThePanelAndGeneralSayUpdatesAreOff() {
        let content = MenuBarContent(PreviewModel(.desk).snapshot)
        func height(_ updates: UpdateMenuContent?) -> CGFloat {
            NSHostingView(rootView: MenuBarPanel(
                content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {}, updates: updates)).fittingSize.height
        }
        XCTAssertGreaterThan(height(.off), height(UpdateMenuContent(Self.state())),
                             "Check for Updates…, and beneath it that updates are off")
        let general = NSHostingView(rootView: Form { UpdatesOffSectionContent() }.formStyle(.grouped).frame(width: 600))
        XCTAssertGreaterThan(general.fittingSize.height, 40)
    }
}

/// Renders the update window, the panel with the updater's rows, and General's group to PNG files for
/// a person to look at. Skipped unless `TACTILE_RENDER_UI` names a folder (see `UIRenderTests`).
@MainActor
final class UpdatesRenderTests: XCTestCase {

    private var folder: URL!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["TACTILE_RENDER_UI"], !path.isEmpty else {
            throw XCTSkip("Set TACTILE_RENDER_UI to a folder to render the interface.")
        }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    private static let offer = UpdateOffer(
        version: ReleaseVersion("0.6.0")!, build: 412, minimumSystemVersion: SystemVersion(major: 14),
        publishedAt: Date(timeIntervalSince1970: 1_794_996_000),
        notes: "Two-finger scrolling follows the fingers more closely.\nPinch to zoom starts sooner.\nThe touch circles fade out faster.",
        archive: .init(url: URL(string: "https://tactilemac.com/api/mac/archive/0.6.0")!, size: 7_340_032,
                       sha256: String(repeating: "a", count: 64), signature: Data(count: 64), keyID: "k1"))

    func testRenderTheUpdateWindow() throws {
        let states: [(String, UpdateState)] = [
            ("checking", UpdateState(phase: .checking(manual: true), runningVersion: "0.5.0")),
            ("newest", UpdateState(notice: .upToDate, runningVersion: "0.5.0")),
            ("failed", UpdateState(notice: .checkFailed(.siteUnreachable), runningVersion: "0.5.0")),
            ("offer", UpdateState(available: Self.offer, runningVersion: "0.5.0")),
            ("downloading", UpdateState(phase: .downloading(Self.offer), available: Self.offer, runningVersion: "0.5.0")),
            ("install-failed", UpdateState(available: Self.offer, notice: .installFailed(.folderNotWritable(folder: "/Applications")),
                                           runningVersion: "0.5.0")),
        ]
        for (name, state) in states {
            for dark in [false, true] {
                let window = UpdateWindowLayout(content: UpdateWindowContent(state), act: { _ in })
                    .background(Color(nsColor: .windowBackgroundColor))
                    .fixedSize()
                try render(window, size: NSHostingView(rootView: window).fittingSize, dark: dark, name: "update-window-\(name)")
            }
        }
    }

    func testRenderThePanelWithUpdates() throws {
        let content = MenuBarContent(PreviewModel(.desk).snapshot)
        let cases: [(String, UpdateState)] = [
            ("idle", UpdateState(runningVersion: "0.5.0")),
            ("offer", UpdateState(available: Self.offer, runningVersion: "0.5.0")),
            ("downloading", UpdateState(phase: .downloading(Self.offer), available: Self.offer, runningVersion: "0.5.0")),
        ]
        for (name, state) in cases {
            for dark in [false, true] {
                let panel = MenuBarPanel(content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {},
                                         updates: UpdateMenuContent(state))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor)))
                    .fixedSize()
                try render(panel, size: NSHostingView(rootView: panel).fittingSize, dark: dark, name: "panel-updates-\(name)")
            }
        }
    }

    func testRenderGeneralsGroup() throws {
        var state = UpdateState(available: Self.offer, runningVersion: "0.5.0")
        state.lastChecked = Date()
        for dark in [false, true] {
            let form = Form {
                UpdatesSectionContent(content: UpdatesSettingsContent(state), setAutomatic: { _ in }, press: { _ in })
            }
            .formStyle(.grouped)
            .frame(width: 600, height: 200)
            try render(form, size: CGSize(width: 600, height: 200), dark: dark, name: "general-updates")
        }
    }

    private func render<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}
