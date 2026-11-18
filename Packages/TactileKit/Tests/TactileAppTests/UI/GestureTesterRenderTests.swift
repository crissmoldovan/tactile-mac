import AppKit
import SwiftUI
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// Renders the gesture tester to PNG files for a person to look at, as `UIRenderTests` does, and
/// skipped unless `TACTILE_RENDER_UI` names a folder:
///
///     TACTILE_RENDER_UI=/path/to/folder swift test --package-path Packages/TactileKit --filter GestureTesterRenderTests
///
/// No window is opened: each view is drawn by an `NSHostingView` that is never put in one. The
/// window's content is drawn at the size the window would give it on each display: the display's
/// frame less a 25-point menu bar, less the tester's margin, less the title bar.
@MainActor
final class GestureTesterRenderTests: XCTestCase {

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

    /// A multi-touch and a one-finger touchscreen, each on a 16:9 display and on the strip's shape.
    func testRenderTheTesterWindow() throws {
        let sixteenByNine = CGSize(width: 2560, height: 1440)
        let strip = CGSize(width: 1600, height: 600)
        let cases: [(TouchscreenID, CGSize, String)] = [
            (UIFixtures.ilitek, sixteenByNine, "tester-ilitek-16x9"),
            (UIFixtures.strip, strip, "tester-strip-strip"),
            (UIFixtures.strip, sixteenByNine, "tester-strip-16x9"),
            (UIFixtures.ilitek, strip, "tester-ilitek-strip"),
        ]
        for (id, display, name) in cases {
            let model = PreviewModel(.desk)
            model.perform(.openGestureTester(id))
            if id == UIFixtures.strip {
                model.perform(.setOneFinger(id, .alwaysScroll))
            }
            try renderWindow(model.snapshot, display: display, name: name)
        }
    }

    /// The strip's 600 points less the menu bar (575), and less a 70-point Dock as well (505): the
    /// one-finger strip and the multi-touch ILITEK in the wide arrangement. Nothing may be clipped;
    /// the rows scroll only where they can't fit.
    func testRenderTheStripWithAndWithoutTheDock() throws {
        let strip = CGSize(width: 1600, height: 600)
        for (id, name) in [(UIFixtures.strip, "strip"), (UIFixtures.ilitek, "ilitek")] {
            let model = PreviewModel(.desk)
            model.perform(.openGestureTester(id))
            if id == UIFixtures.strip {
                model.perform(.setOneFinger(id, .alwaysScroll))
            }
            for visible: CGFloat in [575, 505] {
                try renderWindow(model.snapshot, display: strip, visibleHeight: visible,
                                 name: "tester-\(name)-strip-\(Int(visible))")
            }
        }
    }

    /// The states a person may meet: swipes let through, a gesture switched off, followed swipes on,
    /// Clear pressed, the one-finger default, and a Mac that can't follow swipes.
    func testRenderTheTesterInOtherStates() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(UIFixtures.ilitek))
        model.perform(.setGestureTesterPerformsSwipes(true))
        var gestures = GestureOptions.all
        gestures.rotate = false
        gestures.twoFingerTap = false
        model.perform(.setGestures(UIFixtures.ilitek, gestures))
        model.perform(.setSwipesFollowFingers(true))
        model.perform(.setOneFinger(UIFixtures.ilitek, .alwaysDrag))
        try renderWindow(model.snapshot, display: CGSize(width: 2560, height: 1440), name: "tester-ilitek-changed")

        model.perform(.clearGestureTester)
        var cleared = model.snapshot
        cleared.canFollowSwipes = false
        cleared.gestureTester?.fingersDown = 0
        try renderWindow(cleared, display: CGSize(width: 1600, height: 600), name: "tester-ilitek-cleared-strip")

        let strip = PreviewModel(.desk)
        strip.perform(.openGestureTester(UIFixtures.strip))
        var byDefault = strip.snapshot
        if let index = byDefault.touchscreens.firstIndex(where: { $0.id == UIFixtures.strip }) {
            byDefault.touchscreens[index].behaviour.oneFinger = .alwaysScroll
            byDefault.touchscreens[index].behaviour.oneFingerChoice = nil
        }
        try renderWindow(byDefault, display: CGSize(width: 1600, height: 600), name: "tester-strip-default")
    }

    /// The feed alone, tall enough to show every entry: every kind of gesture.
    func testRenderTheFeedWithEveryKind() throws {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(UIFixtures.ilitek))
        let tester = try XCTUnwrap(model.snapshot.gestureTester)
        XCTAssertEqual(Set(tester.recent.map(\.kind)), Set(RecognisedGesture.Kind.allCases))
        for layout in [GestureTesterLayout.regular, .wide] {
            let metrics = GestureTesterMetrics(layout)
            let size = CGSize(width: metrics.feedWidth + 40, height: layout == .wide ? 980 : 1500)
            let feed = FeedPanel(tester: tester, metrics: metrics, perform: { _ in })
                .padding(20)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            for dark in [false, true] {
                try render(feed, size: size, dark: dark, name: "tester-feed-\(layout == .wide ? "wide" : "regular")")
            }
        }
    }

    /// Gesture Tester… in a touchscreen's pane, and in each touchscreen's details beside the menu.
    func testRenderTheEntries() throws {
        let width = SettingsView<PreviewModel>.minimumSize.width - 210
        var cases: [(String, AppSnapshot, TouchscreenID)] = [
            ("desk-ilitek", UIFixtures.desk, UIFixtures.ilitek),
            ("desk-strip", UIFixtures.desk, UIFixtures.strip),
            ("nothingPaired-ilitek", UIFixtures.snapshot(.nothingPaired), UIFixtures.ilitek),
        ]
        let switchedOff = PreviewModel(.desk)
        switchedOff.perform(.setTouchscreenOn(UIFixtures.strip, false))
        cases.append(("stripOff-strip", switchedOff.snapshot, UIFixtures.strip))
        for (name, snapshot, id) in cases {
            let size = CGSize(width: width, height: 1500)
            for dark in [false, true] {
                try render(
                    SettingsDetail(snapshot: snapshot, item: .touchscreen(id), perform: { _ in })
                        .frame(width: size.width, height: size.height)
                        .background(Color(nsColor: .windowBackgroundColor)),
                    size: size, dark: dark, name: "tester-pane-\(name)")
            }
        }
        let menus: [(String, AppSnapshot)] = [
            ("desk", UIFixtures.desk), ("tactileOff", UIFixtures.snapshot(.tactileOff)),
            ("stripOff", switchedOff.snapshot), ("nothingPaired", UIFixtures.snapshot(.nothingPaired)),
        ]
        for (name, snapshot) in menus {
            for touchscreen in MenuBarContent(snapshot).touchscreens where touchscreen.details.controls != nil {
                for dark in [false, true] {
                    let details = TouchscreenDetailsView(details: touchscreen.details, perform: { _ in }, actions: .none)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor)))
                        .padding(12)
                        .fixedSize()
                    let size = NSHostingView(rootView: details).fittingSize
                    try render(details, size: size, dark: dark,
                               name: "tester-details-\(name)-\(touchscreen.id == UIFixtures.ilitek ? "ilitek" : "strip")")
                }
            }
        }
    }

    // MARK: - Drawing

    /// The tester's window content for `snapshot`'s tester, at the size its window takes on a display
    /// of `display` points.
    private func renderWindow(_ snapshot: AppSnapshot, display: CGSize, visibleHeight: CGFloat? = nil, name: String) throws {
        let tester = try XCTUnwrap(snapshot.gestureTester)
        let touchscreen = try XCTUnwrap(snapshot.touchscreens.first { $0.id == tester.touchscreen })
        let visible = CGRect(x: 0, y: 0, width: display.width, height: visibleHeight ?? display.height - 25)
        let frame = GestureTesterWindowFrame.frame(in: visible)
        let content = NSWindow.contentRect(forFrameRect: frame, styleMask: GestureTesterNSWindow.style).size
        let layout = GestureTesterLayout(displaySize: display)
        for dark in [false, true] {
            let view = VStack(spacing: 0) {
                StandInTitleBar(title: Wording.gestureTesterWindowTitle(name: tester.touchscreenName))
                    .frame(height: frame.height - content.height)
                GestureTesterView(snapshot: snapshot, tester: tester, touchscreen: touchscreen, layout: layout,
                                  perform: { _ in })
                    .frame(width: content.width, height: content.height)
            }
            try render(view.frame(width: frame.width, height: frame.height), size: frame.size, dark: dark, name: name)
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

/// The window's title bar, as drawn for the images: its buttons and its title.
private struct StandInTitleBar: View {
    var title: String

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 12, height: 12)
                Circle().fill(Color.yellow).frame(width: 12, height: 12)
                Circle().fill(Color.secondary.opacity(0.3)).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .overlay(alignment: .bottom) { Divider() }
    }
}
