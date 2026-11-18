import AppKit
import SwiftUI
import TactileGestures
import TactileScreens
import XCTest

@testable import TactileApp

/// Renders the gesture tester's palm tile to PNG files for a person to look at, in each state it can
/// be in, on both touchscreens, in both arrangements, as `GestureTesterRenderTests` does, and skipped
/// unless `TACTILE_RENDER_UI` names a folder:
///
///     TACTILE_RENDER_UI=/path/to/folder swift test --package-path Packages/TactileKit --filter PalmTileRenderTests
///
/// The tile is drawn on the window's store, which is handed the snapshots one after another, as the
/// window's observer hands them, so its line follows them as it does in the window.
@MainActor
final class PalmTileRenderTests: XCTestCase {

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

    /// The tile's size in each arrangement, about as the practice area gives it.
    private static let sizes: [(String, GestureTesterLayout, CGSize)] = [
        ("wide", .wide, CGSize(width: 270, height: 232)),
        ("regular", .regular, CGSize(width: 560, height: 330)),
    ]

    /// A step: what the feed and the fingers are, from the snapshot before.
    private typealias Step = (inout GestureTesterSnapshot) -> Void

    private static func ignored(_ reason: IgnoredBecause, fingers: Int) -> Step {
        { tester in
            let id = (tester.recent.map(\.id).max() ?? 0) + 1
            tester.recent.insert(
                RecognisedGesture(id: id, kind: .ignored, fingers: fingers, summary: GestureNarrator.ignored(reason), at: 0),
                at: 0)
            if let index = tester.seen.firstIndex(where: { $0.id == .ignored }) {
                tester.seen[index].count += 1
            } else {
                tester.seen.append(GestureSeenCount(id: .ignored, count: 1))
            }
            tester.fingersDown = fingers
        }
    }

    private static func fingers(_ count: Int) -> Step {
        { $0.fingersDown = count }
    }

    func testRenderThePalmTile() throws {
        let ilitek = UIFixtures.ilitek, strip = UIFixtures.strip
        let cases: [(String, TouchscreenID, (inout AppSnapshot) -> Void, [Step])] = [
            ("hand-rule", ilitek, { _ in }, []),
            ("hand-3-fingers", ilitek, { _ in }, [Self.fingers(1), Self.fingers(3)]),
            ("hand-ignored", ilitek, { _ in }, [Self.fingers(2), Self.ignored(.hand, fingers: 5)]),
            ("hand-ignored-lifted", ilitek, { _ in }, [Self.ignored(.hand, fingers: 5), Self.fingers(0)]),
            ("hand-not-at-once", ilitek, { _ in }, [Self.fingers(3), Self.fingers(5)]),
            ("hand-palm-off", ilitek, { Self.change(ilitek, in: &$0) { $0.behaviour.rejection.palm = false } }, []),
            ("palm-rule", ilitek, { Self.change(ilitek, in: &$0) { $0.behaviour.reportsPalms = true } }, []),
            ("palm-ignored", ilitek, { Self.change(ilitek, in: &$0) { $0.behaviour.reportsPalms = true } },
             [Self.ignored(.palm, fingers: 1)]),
            ("edge-rule", strip, { Self.change(strip, in: &$0) { $0.behaviour.rejection.edgeMarginMM = 4 } }, []),
            ("edge-ignored", strip, { Self.change(strip, in: &$0) { $0.behaviour.rejection.edgeMarginMM = 4 } },
             [Self.ignored(.edge, fingers: 1), Self.fingers(0)]),
            ("edge-off", strip, { _ in }, []),
        ]
        for (name, id, setting, steps) in cases {
            for (arrangement, layout, size) in Self.sizes {
                for dark in [false, true] {
                    let model = PreviewModel(.desk)
                    model.perform(.openGestureTester(id))
                    model.perform(.clearGestureTester)
                    var snapshot = model.snapshot
                    snapshot.gestureTester?.fingersDown = 0
                    setting(&snapshot)
                    try render(snapshot, id: id, layout: layout, steps: steps, size: size, dark: dark,
                               name: "palm-tile-\(name)-\(arrangement)")
                }
            }
        }
    }

    private static func change(_ id: TouchscreenID, in snapshot: inout AppSnapshot, _ change: (inout TouchscreenSnapshot) -> Void) {
        guard let index = snapshot.touchscreens.firstIndex(where: { $0.id == id }) else { return }
        change(&snapshot.touchscreens[index])
    }

    private func render(
        _ first: AppSnapshot, id: TouchscreenID, layout: GestureTesterLayout, steps: [Step], size: CGSize, dark: Bool,
        name: String
    ) throws {
        let store = GestureTesterStore(touchscreen: id, layout: layout, snapshot: first, perform: { _ in })
        let practice = store.practice
        let kind = PalmTileKind(multiTouch: practice.multiTouch, reportsPalms: practice.reportsPalms)
        let metrics = store.metrics
        let tile = PracticeTile(
            title: Wording.practicePalmTitle(kind), hint: Wording.practicePalmHint(kind, edgeMarginMM: practice.edgeMarginMM),
            metrics: metrics
        ) {
            PalmPractice(store: store, kind: kind, edgeMarginMM: practice.edgeMarginMM, metrics: metrics)
        }
        .padding(10)
        .frame(width: size.width + 20, height: size.height + 20)
        .background(Color(nsColor: .underPageBackgroundColor))
        let host = NSHostingView(rootView: tile.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: size.width + 20, height: size.height + 20)
        func settle() {
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
        }
        settle()
        var snapshot = first
        for step in steps {
            guard var tester = snapshot.gestureTester else { break }
            step(&tester)
            snapshot.gestureTester = tester
            store.update(snapshot)
            settle()
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }
}
