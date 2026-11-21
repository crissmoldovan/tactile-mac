import AppKit
import SwiftUI
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// Renders the interface to PNG files for a person to look at. Skipped unless `TACTILE_RENDER_UI`
/// names a folder:
///
///     TACTILE_RENDER_UI=/path/to/folder swift test --package-path Packages/TactileKit --filter UIRenderTests
///
/// No window is opened: each view is drawn by an `NSHostingView` that is never put in one. The
/// sidebar's `List` draws nothing that way, so the window's images use a stand-in sidebar made of the
/// same row views; the panes are the real ones. The menu-bar panel is the real panel view.
@MainActor
final class UIRenderTests: XCTestCase {

    private var folder: URL!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["TACTILE_RENDER_UI"], !path.isEmpty else {
            throw XCTSkip("Set TACTILE_RENDER_UI to a folder to render the interface.")
        }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Drawing needs the shared application; it never becomes active or shows in the Dock.
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
    }

    func testRenderTheSettingsWindow() throws {
        for variant in PreviewModel.Variant.allCases {
            let snapshot = PreviewModel(variant).snapshot
            let items = snapshot.touchscreens.map { SidebarItem.touchscreen($0.id) } + SidebarItem.belowTouchscreens
            for item in items {
                let pane: String
                switch item {
                case .general: pane = "general"
                case .touchscreenCheck: pane = "touchscreen-check"
                case .touchscreen(let id): pane = Self.slug(snapshot.touchscreens.first { $0.id == id }?.name ?? "x")
                }
                let notListed = item == .touchscreenCheck ? NotListedDevices(fixed: PreviewDesk.notListedDevices) : nil
                for dark in [false, true] {
                    let size = SettingsView<PreviewModel>.minimumSize
                    try render(
                        SettingsRenderFrame(snapshot: snapshot, item: item, notListed: notListed)
                            .frame(width: size.width, height: size.height),
                        size: size, dark: dark, name: "settings-\(variant.rawValue)-\(pane)")
                }
            }
        }
    }

    /// The longest label of the desk in the Display pop-up, and a long custom name, at the window's
    /// minimum size: nothing may be cut off.
    func testRenderTheLongestLabelsAtTheMinimumSize() throws {
        let model = PreviewModel(.desk)
        let lg = try XCTUnwrap(model.snapshot.displays.first { $0.name == "LG HDR 4K" }).id
        model.perform(.pair(UIFixtures.ilitek, displayID: lg))
        model.perform(.rename(UIFixtures.ilitek, to: "Touchscreen above the MacBook, on the arm"))
        model.perform(.setTouchscreenOn(UIFixtures.strip, false))
        model.perform(.setWhenOff(UIFixtures.strip, .leaveToMacOS))
        let size = SettingsView<PreviewModel>.minimumSize
        for dark in [false, true] {
            for (item, pane) in [(SidebarItem.touchscreen(UIFixtures.ilitek), "ilitek-tp"),
                                 (.touchscreen(UIFixtures.strip), "touchscreen")] {
                try render(
                    SettingsRenderFrame(snapshot: model.snapshot, item: item).frame(width: size.width, height: size.height),
                    size: size, dark: dark, name: "settings-longest-\(pane)")
            }
        }
    }

    func testRenderTheMenuBarPanel() throws {
        for variant in PreviewModel.Variant.allCases {
            let content = MenuBarContent(PreviewModel(variant).snapshot)
            for dark in [false, true] {
                let panel = MenuBarPanel(content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {})
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor)))
                    .padding(12)
                    .fixedSize()
                let host = NSHostingView(rootView: panel)
                let size = host.fittingSize
                try render(panel, size: size, dark: dark, name: "menu-\(variant.rawValue)")
            }
        }
    }

    /// Each touchscreen's details beside the menu, as the window puts them: its row highlighted, the
    /// details' first line level with it. Driving, the one-finger strip, not set up, switched off,
    /// while Tactile is off, one that can't be used, one not connected.
    func testRenderTheTouchscreenDetails() throws {
        let stripOff = PreviewModel(.desk)
        stripOff.perform(.setTouchscreenOn(UIFixtures.strip, false))
        let twins = PreviewModel(.identicalTwins).snapshot
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) }).id
        let cases: [(String, AppSnapshot, TouchscreenID)] = [
            ("ilitek-driving", PreviewModel(.desk).snapshot, UIFixtures.ilitek),
            ("strip-one-finger", PreviewModel(.desk).snapshot, UIFixtures.strip),
            ("ilitek-not-set-up", PreviewModel(.nothingPaired).snapshot, UIFixtures.ilitek),
            ("strip-off", stripOff.snapshot, UIFixtures.strip),
            ("ilitek-tactile-off", PreviewModel(.tactileOff).snapshot, UIFixtures.ilitek),
            ("twin-cannot-be-used", twins, twin),
            ("old-panel-not-connected", PreviewModel(.desk).snapshot, UIFixtures.oldPanel),
        ]
        for (name, snapshot, id) in cases {
            let content = MenuBarContent(snapshot)
            let details = try XCTUnwrap(content.touchscreens.first { $0.id == id }).details
            for dark in [false, true] {
                let menu = MenuBarPanel(
                    content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {}, detailsShown: id)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor)))
                    .overlayPreferenceValue(DetailsRowBounds.self) { row in
                        GeometryReader { proxy in
                            if let row {
                                TouchscreenDetailsView(details: details, perform: { _ in }, actions: .none)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .windowBackgroundColor)))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor)))
                                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                                    .offset(x: proxy.size.width + MenuDetailsPlacement.gap,
                                            y: proxy[row].minY - MenuDetailsPlacement.inset)
                            }
                        }
                    }
                    .padding(12)
                    .frame(width: MenuBarPanel.width + TouchscreenDetailsView.width + 40, height: 560, alignment: .topLeading)
                try render(menu, size: CGSize(width: MenuBarPanel.width + TouchscreenDetailsView.width + 40, height: 560),
                           dark: dark, name: "menu-details-\(name)")
            }
        }
    }

    func testRenderIdentifyOnTheDesk() throws {
        let snapshot = PreviewModel(.desk).snapshot
        let scale: CGFloat = 0.12
        let minX = snapshot.displays.map(\.frame.minX).min() ?? 0
        let minY = snapshot.displays.map(\.frame.minY).min() ?? 0
        let maxX = snapshot.displays.map(\.frame.maxX).max() ?? 0
        let maxY = snapshot.displays.map(\.frame.maxY).max() ?? 0
        let size = CGSize(width: (maxX - minX) * scale + 40, height: (maxY - minY) * scale + 40)
        let desk = ZStack(alignment: .topLeading) {
            Color(white: 0.16)
            ForEach(snapshot.displays) { display in
                IdentifyCard(name: display.name, detail: display.detail, screenSize: display.frame.size)
                    .background(LinearGradient(colors: [Color(red: 0.32, green: 0.45, blue: 0.62),
                                                        Color(red: 0.62, green: 0.48, blue: 0.56)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: display.frame.width * scale, height: display.frame.height * scale, alignment: .topLeading)
                    .clipped()
                    .border(Color.black, width: 2)
                    .offset(x: (display.frame.minX - minX) * scale + 20, y: (display.frame.minY - minY) * scale + 20)
            }
        }
        try render(desk.frame(width: size.width, height: size.height), size: size, dark: true, name: "identify-desk")

        let strip = try XCTUnwrap(snapshot.displays.first { $0.name == "12.3FHD" })
        let half: CGFloat = 0.5
        let card = IdentifyCard(name: strip.name, detail: strip.detail, screenSize: strip.frame.size)
            .background(Color(red: 0.3, green: 0.42, blue: 0.58))
            .scaleEffect(half, anchor: .topLeading)
            .frame(width: strip.frame.width * half, height: strip.frame.height * half, alignment: .topLeading)
        try render(card, size: CGSize(width: strip.frame.width * half, height: strip.frame.height * half), dark: true,
                   name: "identify-strip")
    }

    func testRenderTheMenuBarIcons() throws {
        for dark in [false, true] {
            let states: [MenuBarIcon.State] = [.normal, .off, .attention]
            let bar = HStack(spacing: 18) {
                ForEach(states, id: \.self) { state in
                    Image(nsImage: MenuBarIcon.image(state))
                }
            }
            .foregroundStyle(dark ? Color.white : Color.black)
            .padding(.horizontal, 14)
            .frame(height: 24)
            .background(dark ? Color(white: 0.12) : Color(white: 0.93))
            .scaleEffect(4, anchor: .topLeading)
            .frame(width: 4 * 118, height: 4 * 24, alignment: .topLeading)
            try render(bar, size: CGSize(width: 4 * 118, height: 4 * 24), dark: dark, name: "menubar-icons")
        }
    }

    /// A touchscreen's whole pane, tall enough that nothing scrolls away: the 0.3.0 controls.
    func testRenderTheWholePane() throws {
        let cases: [(PreviewModel.Variant, TouchscreenID, String)] = [
            (.desk, UIFixtures.ilitek, "ilitek-tp"),
            (.desk, UIFixtures.strip, "touchscreen"),
            (.nothingPaired, UIFixtures.ilitek, "ilitek-tp"),
            (.allWarnings, UIFixtures.ilitek, "ilitek-tp"),
            (.tactileOff, UIFixtures.ilitek, "ilitek-tp"),
        ]
        let size = CGSize(width: SettingsView<PreviewModel>.minimumSize.width, height: 1330)
        for (variant, id, pane) in cases {
            let snapshot = PreviewModel(variant).snapshot
            for dark in [false, true] {
                try render(
                    SettingsRenderFrame(snapshot: snapshot, item: .touchscreen(id)).frame(width: size.width, height: size.height),
                    size: size, dark: dark, name: "pane-\(variant.rawValue)-\(pane)")
            }
        }
        let twins = PreviewModel(.identicalTwins).snapshot
        let twin = try XCTUnwrap(twins.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        for dark in [false, true] {
            try render(
                SettingsRenderFrame(snapshot: twins, item: .touchscreen(twin.id)).frame(width: size.width, height: size.height),
                size: size, dark: dark, name: "pane-identicalTwins-twin")
        }
        // Changed from the defaults: a one-finger mode, the pointer staying, circles off, a gesture
        // off, an edge margin, and the Mission Control shortcuts off.
        let changed = PreviewModel(.desk)
        changed.perform(.setOneFinger(UIFixtures.ilitek, .alwaysScroll))
        changed.perform(.setPointerReturn(UIFixtures.ilitek, .staysWhereTouched))
        changed.perform(.setShowsCircles(UIFixtures.ilitek, false))
        var gestures = GestureOptions.all
        gestures.rotate = false
        changed.perform(.setGestures(UIFixtures.ilitek, gestures))
        changed.perform(.setRejection(UIFixtures.ilitek, RejectionRules(palm: true, edgeMarginMM: 4)))
        changed.perform(.clearCalibration(UIFixtures.ilitek))
        var snapshot = changed.snapshot
        snapshot.warnings = [.missionControlShortcutsOff]
        for dark in [false, true] {
            try render(
                SettingsRenderFrame(snapshot: snapshot, item: .touchscreen(UIFixtures.ilitek))
                    .frame(width: size.width, height: size.height),
                size: size, dark: dark, name: "pane-changed-ilitek-tp")
        }
        // A set-up running: the controls that change a fit wait, with one line saying why, on the
        // pane of the touchscreen being set up, the other one's, and a remembered one's.
        let running = PreviewModel(.desk)
        running.perform(.beginSetUp(UIFixtures.ilitek, .calibrate))
        for (id, pane) in [(UIFixtures.ilitek, "ilitek-tp"), (UIFixtures.strip, "touchscreen"),
                           (UIFixtures.oldPanel, "old-panel")] {
            for dark in [false, true] {
                try render(
                    SettingsRenderFrame(snapshot: running.snapshot, item: .touchscreen(id))
                        .frame(width: size.width, height: size.height),
                    size: size, dark: dark, name: "pane-setUpRunning-\(pane)")
            }
        }
        // Set-up mode on: the fit controls wait, and Set Up by Touch…, Calibrate Corners… and Test say
        // why.
        let mode = PreviewModel(.desk)
        mode.perform(.beginSetUpMode)
        for dark in [false, true] {
            try render(
                SettingsRenderFrame(snapshot: mode.snapshot, item: .touchscreen(UIFixtures.ilitek))
                    .frame(width: size.width, height: size.height),
                size: size, dark: dark, name: "pane-setUpMode-ilitek-tp")
        }
        // The one-finger pop-up: the strip with a choice made (Automatic), its default named Always
        // scroll; and the ILITEK with Always scroll and the circles off, where no ring shows.
        let oneFinger = PreviewModel(.desk)
        oneFinger.perform(.setOneFinger(UIFixtures.strip, .automatic))
        oneFinger.perform(.setOneFinger(UIFixtures.ilitek, .alwaysScroll))
        oneFinger.perform(.setShowsCircles(UIFixtures.ilitek, false))
        for (id, pane) in [(UIFixtures.strip, "touchscreen"), (UIFixtures.ilitek, "ilitek-tp")] {
            for dark in [false, true] {
                try render(
                    SettingsRenderFrame(snapshot: oneFinger.snapshot, item: .touchscreen(id))
                        .frame(width: size.width, height: size.height),
                    size: size, dark: dark, name: "pane-oneFinger-\(pane)")
            }
        }
        // The strip in mouse mode, macOS still seeing it: no set-up, calibration or test, and why.
        var shared = PreviewModel(.desk).snapshot
        if let index = shared.touchscreens.firstIndex(where: { $0.id == UIFixtures.strip }) {
            shared.touchscreens[index].notes = [.oneFingerOnly, .macOSMayAlsoRespond]
            shared.touchscreens[index].mode = .held
            shared.touchscreens[index].canBeSetUp = false
        }
        for dark in [false, true] {
            try render(
                SettingsRenderFrame(snapshot: shared, item: .touchscreen(UIFixtures.strip))
                    .frame(width: size.width, height: size.height),
                size: size, dark: dark, name: "pane-macOSAlsoHandlesIt-touchscreen")
        }
    }

    func testRenderGeneralWithRecording() throws {
        let model = PreviewModel(.allWarnings)
        model.perform(.setRecordsFrames(true))
        let size = CGSize(width: SettingsView<PreviewModel>.minimumSize.width, height: 900)
        for dark in [false, true] {
            try render(
                SettingsRenderFrame(snapshot: model.snapshot, item: .general).frame(width: size.width, height: size.height),
                size: size, dark: dark, name: "general-all-warnings-tall")
        }
    }

    /// General in 0.4.0: Launch at login in each of its states, and Swipes follow the fingers off,
    /// on and unavailable.
    func testRenderGeneralForLivingOnTheMac() throws {
        let size = CGSize(width: SettingsView<PreviewModel>.minimumSize.width, height: 980)
        var cases: [(String, AppSnapshot)] = []
        for state in [LaunchAtLogin.off, .on, .needsApproval, .notInstalled, .unavailable] {
            var snapshot = PreviewModel(.desk).snapshot
            snapshot.launchAtLogin = state
            cases.append(("general-login-\(state.rawValue)", snapshot))
        }
        var on = PreviewModel(.desk).snapshot
        on.swipesFollowFingers = true
        cases.append(("general-swipes-on", on))
        var unavailable = PreviewModel(.desk).snapshot
        unavailable.swipesFollowFingers = true
        unavailable.canFollowSwipes = false
        cases.append(("general-swipes-unavailable", unavailable))
        for (name, snapshot) in cases {
            for dark in [false, true] {
                try render(
                    SettingsRenderFrame(snapshot: snapshot, item: .general).frame(width: size.width, height: size.height),
                    size: size, dark: dark, name: name)
            }
        }
    }

    /// For one touchscreen and for two.
    func testRenderTheFirstRunWindow() throws {
        for (names, name) in [(["ILITEK-TP"], "first-run-one"), (["ILITEK-TP", "TouchScreen"], "first-run-two")] {
            for dark in [false, true] {
                try renderFirstRun(names, dark: dark, name: name)
            }
        }
    }

    private func renderFirstRun(_ names: [String], dark: Bool, name: String) throws {
        let window = FirstRunView(names: names, setUp: {}, notNow: {})
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                    Circle().fill(Color.secondary.opacity(0.3)).frame(width: 12, height: 12)
                    Circle().fill(Color.secondary.opacity(0.3)).frame(width: 12, height: 12)
                }
                .padding(10)
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            .padding(30)
            .background(LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.82), Color(red: 0.78, green: 0.7, blue: 0.86)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .fixedSize()
        let size = NSHostingView(rootView: window).fittingSize
        try render(window, size: size, dark: dark, name: name)
    }

    /// Set-up mode's overview at each stage, on the desk: the row of the built-in display (the
    /// session card), HDMI (the ILITEK's), LG HDR 4K (free) and 12.3FHD (the strip's, just set up
    /// again), small; and the displays that matter at each stage at half size, the strip at full
    /// size, to read.
    func testRenderSetUpMode() throws {
        let row = ["Built-in Retina Display", "HDMI", "LG HDR 4K", "12.3FHD"]
        let model = PreviewModel(.desk)
        model.perform(.beginSetUpMode)
        let fhd = try XCTUnwrap(UIFixtures.displayID(named: "12.3FHD", in: model.snapshot))
        let lg = try XCTUnwrap(UIFixtures.displayID(named: "LG HDR 4K", in: model.snapshot))
        try renderSetUp(model.snapshot, name: "mode-0-begun", displays: row, scale: 0.22)

        // The strip set up again on its display: back to the overview, 12.3FHD marked just set up.
        model.perform(.setUpChoose(displayID: fhd))
        model.simulate(.touch(UIFixtures.strip))
        for _ in 0..<4 { model.touchSetUp() }
        model.perform(.setUpConfirmSize(inches: nil))
        model.perform(.setUpDone)
        try renderSetUp(model.snapshot, name: "mode-1-choosing", displays: row, scale: 0.22)
        for name in ["Built-in Retina Display", "HDMI", "LG HDR 4K"] {
            try renderSetUp(model.snapshot, name: "mode-1-choosing-\(Self.slug(name))", displays: [name], scale: 0.5)
        }
        try renderSetUp(model.snapshot, name: "mode-1-choosing-12-3fhd", displays: ["12.3FHD"], scale: 1)

        // LG chosen: bright, waiting for a touch; the others dimmed.
        model.perform(.setUpChoose(displayID: lg))
        try renderSetUp(model.snapshot, name: "mode-2-waiting", displays: row, scale: 0.22)
        try renderSetUp(model.snapshot, name: "mode-2-waiting-lg-hdr-4k", displays: ["LG HDR 4K"], scale: 0.5)
        try renderSetUp(model.snapshot, name: "mode-2-waiting-hdmi", displays: ["HDMI"], scale: 0.5)
        try renderSetUp(model.snapshot, name: "mode-2-waiting-12-3fhd", displays: ["12.3FHD"], scale: 1)

        // LG unplugged while waiting: back to choosing, and the session card says so.
        model.simulate(.displayConnected(lg, false))
        try renderSetUp(model.snapshot, name: "mode-3-notice", displays: ["Built-in Retina Display"], scale: 0.5)
        model.simulate(.displayConnected(lg, true))

        // The ILITEK touched first: every card says so above its button.
        model.simulate(.touch(UIFixtures.ilitek))
        try renderSetUp(model.snapshot, name: "mode-4-touched-first", displays: row, scale: 0.22)
        for name in ["Built-in Retina Display", "HDMI", "LG HDR 4K"] {
            try renderSetUp(model.snapshot, name: "mode-4-touched-first-\(Self.slug(name))", displays: [name], scale: 0.5)
        }

        // A flow in the mode: corners, size and check, with Back.
        model.perform(.setUpChoose(displayID: lg))
        try renderSetUp(model.snapshot, name: "mode-5-corners", displays: ["Built-in Retina Display", "LG HDR 4K", "12.3FHD"],
                        scale: 0.3)
        for _ in 0..<4 { model.touchSetUp() }
        try renderSetUp(model.snapshot, name: "mode-6-size", displays: ["LG HDR 4K"], scale: 0.5)
        model.perform(.setUpConfirmSize(inches: nil))
        try renderSetUp(model.snapshot, name: "mode-7-check", displays: ["LG HDR 4K"], scale: 0.5)

        // The twin can't be set up: its line says why, and its touch is a notice.
        let twins = PreviewModel(.identicalTwins)
        twins.perform(.beginSetUpMode)
        let twin = try XCTUnwrap(twins.snapshot.touchscreens.first { $0.notes.contains(.cannotBeToldApart) })
        twins.simulate(.touch(twin.id))
        try renderSetUp(twins.snapshot, name: "mode-8-twin-notice", displays: ["Built-in Retina Display"], scale: 0.5)

        // No built-in display (the lid closed): the session card beside the first candidate's card.
        let closed = PreviewModel(.nothingPaired)
        closed.perform(.beginSetUpMode)
        closed.simulate(.displayConnected(1, false))
        try renderSetUp(closed.snapshot, name: "mode-9-no-built-in", displays: ["Display"], scale: 0.5)
        closed.perform(.setUpChoose(displayID: try XCTUnwrap(UIFixtures.displayID(named: "Display", in: closed.snapshot))))
        try renderSetUp(closed.snapshot, name: "mode-9-no-built-in-waiting", displays: ["Display"], scale: 0.5)

        // No built-in display, and the strip's display first: it carries the session card, and is
        // chosen. The Back card and the session card below the middle of 600 pt, plain and with the
        // most the session card can say on this desk (the twin's line, its reason, a notice).
        for (variant, name) in [(PreviewModel.Variant.nothingPaired, "mode-10-strip-first"),
                                (.identicalTwins, "mode-10-strip-first-notice")] {
            let first = PreviewModel(variant)
            first.perform(.beginSetUpMode)
            for display in ["Built-in Retina Display", "Display", "HDMI"] {
                first.simulate(.displayConnected(try XCTUnwrap(UIFixtures.displayID(named: display, in: first.snapshot)), false))
            }
            first.perform(.setUpChoose(displayID: try XCTUnwrap(UIFixtures.displayID(named: "12.3FHD", in: first.snapshot))))
            if let twin = first.snapshot.touchscreens.first(where: { $0.notes.contains(.cannotBeToldApart) }) {
                first.simulate(.touch(twin.id))
                XCTAssertNotNil(first.snapshot.setUpMode?.notice)
            }
            try renderSetUp(first.snapshot, name: name, displays: ["12.3FHD"], scale: 1)
        }

        // Review Focus 4: HDMI, the ILITEK's, set up again for the strip: HDMI keeps its buttons.
        let taken = PreviewModel(.desk)
        taken.perform(.beginSetUpMode)
        taken.perform(.setUpChoose(displayID: try XCTUnwrap(UIFixtures.displayID(named: "HDMI", in: taken.snapshot))))
        taken.simulate(.touch(UIFixtures.strip))
        try renderSetUp(taken.snapshot, name: "mode-11-taken-corners", displays: ["HDMI", "12.3FHD"], scale: 0.4)
        for _ in 0..<4 { taken.touchSetUp() }
        try renderSetUp(taken.snapshot, name: "mode-11-taken-size", displays: ["HDMI"], scale: 0.5)
        taken.perform(.setUpConfirmSize(inches: nil))
        try renderSetUp(taken.snapshot, name: "mode-11-taken-check", displays: ["HDMI"], scale: 0.5)

        // The strip on its own display, set up from nothing: the type must fit 1600 × 600.
        let strip = PreviewModel(.nothingPaired)
        strip.perform(.beginSetUpMode)
        try renderSetUp(strip.snapshot, name: "mode-strip-1-choosing", displays: ["12.3FHD"], scale: 1)
        strip.perform(.setUpChoose(displayID: try XCTUnwrap(UIFixtures.displayID(named: "12.3FHD", in: strip.snapshot))))
        try renderSetUp(strip.snapshot, name: "mode-strip-2-waiting", displays: ["12.3FHD"], scale: 1)
        strip.simulate(.touch(UIFixtures.strip))
        strip.touchSetUp(.tooManyFingers)
        try renderSetUp(strip.snapshot, name: "mode-strip-3-corners", displays: ["12.3FHD"], scale: 1)
        for _ in 0..<4 { strip.touchSetUp() }
        try renderSetUp(strip.snapshot, name: "mode-strip-4-size", displays: ["12.3FHD"], scale: 1)
        strip.perform(.setUpConfirmSize(inches: nil))
        try renderSetUp(strip.snapshot, name: "mode-strip-5-check", displays: ["12.3FHD"], scale: 1)
    }

    /// Calibrate Corners… and Test from a pane, outside set-up mode: as before, with Cancel.
    func testRenderTheSetUpScreensOutsideTheMode() throws {
        // A test: the check alone, on HDMI.
        let test = PreviewModel(.desk)
        test.perform(.beginSetUp(UIFixtures.ilitek, .test))
        try renderSetUp(test.snapshot, name: "test-check", displays: ["HDMI"], scale: 0.4)

        // Calibration: the corners, with the other displays.
        let corners = PreviewModel(.desk)
        corners.perform(.beginSetUp(UIFixtures.ilitek, .calibrate))
        corners.touchSetUp()
        corners.touchSetUp(.moved)
        try renderSetUp(corners.snapshot, name: "calibrate-corners", displays: ["HDMI", "LG HDR 4K", "12.3FHD"], scale: 0.4)

        // Calibration refused: the taps didn't fit.
        let calibrate = PreviewModel(.desk)
        calibrate.perform(.beginSetUp(UIFixtures.ilitek, .calibrate))
        calibrate.touchSetUp(.tapsDidNotFit)
        try renderSetUp(calibrate.snapshot, name: "calibrate-refused", displays: ["HDMI"], scale: 0.4)

        // The display turned in macOS mid-round: the corners start again, with no problem.
        let turned = PreviewModel(.desk)
        turned.perform(.beginSetUp(UIFixtures.ilitek, .calibrate))
        turned.touchSetUp()
        turned.touchSetUp()
        let before = SetUpScreens.plan(turned.snapshot)
        turned.restartSetUpCorners()
        try renderSetUp(turned.snapshot, name: "calibrate-started-again", displays: ["HDMI"], scale: 0.4,
                        after: before)
    }

    /// The named displays of `snapshot`'s set-up side by side, each over a stand-in desktop.
    private func renderSetUp(_ snapshot: AppSnapshot, name: String, displays: [String],
                             scale: CGFloat, after previous: [SetUpScreen] = []) throws {
        let plan = SetUpScreens.plan(snapshot, after: previous)
        let shown = try displays.map { displayName -> (SetUpScreen, CGSize) in
            let display = try XCTUnwrap(snapshot.displays.first { $0.name == displayName })
            let screen = try XCTUnwrap(plan.first { $0.displayID == display.id })
            return (screen, display.frame.size)
        }
        let gap: CGFloat = 24
        let width = shown.map { $0.1.width * scale }.reduce(0, +) + gap * CGFloat(shown.count + 1)
        let height = (shown.map { $0.1.height * scale }.max() ?? 0) + 2 * gap
        for dark in [false, true] {
            let row = HStack(alignment: .top, spacing: gap) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                    SetUpRenderScreen(screen: item.0, displaySize: item.1)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: item.1.width * scale, height: item.1.height * scale, alignment: .topLeading)
                        .clipped()
                        .border(Color.black, width: 2)
                }
            }
            .padding(gap)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Color(white: 0.16))
            try render(row, size: CGSize(width: width, height: height), dark: dark, name: "setup-\(name)")
        }
    }

    // MARK: - Drawing

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

    private static func slug(_ name: String) -> String {
        name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { $0.append($1) }
    }
}

/// One display during a set-up, as the overlay puts it there: a stand-in desktop, the backdrop, and
/// the buttons' card where the overlay would place it.
private struct SetUpRenderScreen: View {
    var screen: SetUpScreen
    var displaySize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            StandInDesktop()
            SetUpBackdrop(screen: screen, displaySize: displaySize)
            if screen.hasControls {
                let controls = SetUpControls(screen: screen, displaySize: displaySize, perform: { _ in })
                let size = NSHostingView(rootView: controls).fittingSize
                let frame = SetUpScreens.controlsFrame(
                    screen.placement, size: size, on: CGRect(origin: .zero, size: displaySize))
                controls
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: displaySize.height - frame.maxY)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
    }
}

/// What a desktop might show beneath the set-up screens: a wallpaper and a window.
private struct StandInDesktop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.32, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.48, blue: 0.56)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(0..<8, id: \.self) { line in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(width: geometry.size.width * (0.2 + 0.05 * Double(line % 4)), height: 12)
                            }
                        }
                        .padding(40)
                    }
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.height * 0.6)
                    .offset(x: geometry.size.width * 0.12, y: geometry.size.height * 0.16)
            }
        }
    }
}

/// The Settings window as drawn for the images: a stand-in sidebar of the real row views, and the
/// real pane. Touchscreen Check lists `notListed` as the touch devices Tactile doesn't list.
struct SettingsRenderFrame: View {
    var snapshot: AppSnapshot
    var item: SidebarItem
    var notListed: NotListedDevices? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Wording.touchscreens)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                ForEach(snapshot.touchscreens) { touchscreen in
                    row(SidebarTouchscreenRow(touchscreen: touchscreen), selected: item == .touchscreen(touchscreen.id))
                }
                Spacer().frame(height: 14)
                row(HStack {
                    SidebarGeneralRow()
                    Spacer()
                    if !snapshot.warnings.isEmpty {
                        Text("\(snapshot.warnings.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }, selected: item == .general)
                row(SidebarCheckRow(), selected: item == .touchscreenCheck)
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal, 10)
            .frame(width: 210)
            .background(Color.primary.opacity(0.06))
            Divider()
            SettingsDetail(snapshot: snapshot, item: item, perform: { _ in }, notListed: notListed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func row<Content: View>(_ content: Content, selected: Bool) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .environment(\.backgroundProminence, selected ? .increased : .standard)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor : .clear))
    }
}
