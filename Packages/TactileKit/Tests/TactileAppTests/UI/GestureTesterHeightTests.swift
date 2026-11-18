import AppKit
import SwiftUI
import TactileScreens
import XCTest

@testable import TactileApp

/// "What this touchscreen can do" scrolls, or not, by arithmetic alone (`GestureTesterMetrics`): its
/// rows' heights are worked out from the sizes of its type, never measured. These hold that
/// arithmetic to the layout: each line is the line of the size its text is drawn at, and the column
/// of rows, hosted as the window hosts it in an `NSHostingView` that is never put in a window, takes
/// the height worked out for it.
@MainActor
final class GestureTesterHeightTests: XCTestCase {

    override func setUp() async throws {
        _ = NSApplication.shared
    }

    /// The store of `id`'s tester, as its window on a display of `display` points makes it.
    private func store(_ id: TouchscreenID, display: CGSize) -> GestureTesterStore {
        let model = PreviewModel(.desk)
        model.perform(.openGestureTester(id))
        return GestureTesterStore(
            touchscreen: id, layout: GestureTesterLayout(displaySize: display), snapshot: model.snapshot,
            perform: { _ in })
    }

    /// The fonts and the lines measured for the rows' heights come from one formula, in both
    /// arrangements, at every size of type the window may take.
    func testEachLineIsTheLineOfTheSizeItsTextIsDrawnAt() {
        for layout in [GestureTesterLayout.wide, .regular] {
            for body: CGFloat in [12, 14, 17, GestureTesterType.largestBody] {
                let floor = GestureTesterType.floor(layout)
                let type = GestureTesterType(body: body, title: body + (floor.title - floor.body))
                let metrics = GestureTesterMetrics(layout, type: type)
                let name = "\(layout) at \(body)"
                XCTAssertEqual(metrics.bodyLine, GestureTesterMetrics.line(metrics.bodySize), name)
                XCTAssertEqual(metrics.smallLine, GestureTesterMetrics.line(metrics.smallSize), name)
                XCTAssertEqual(metrics.titleLine, GestureTesterMetrics.line(metrics.titleSize, weight: .medium), name)
                XCTAssertEqual(metrics.sectionLine, GestureTesterMetrics.line(metrics.sectionSize, weight: .semibold), name)
                XCTAssertEqual(metrics.headingLine, GestureTesterMetrics.line(metrics.headingSize, weight: .bold), name)
            }
        }
    }

    /// The column of rows, at the width the part gives it, is as tall as `rowsHeight` says, within a
    /// point: on the strip's shape (the wide arrangement) and at 16:9 (the regular one), for the
    /// one-finger strip and the multi-touch ILITEK in each. Were it taller, rows the arithmetic says
    /// fit would not, and the part would not scroll.
    func testTheRowsTakeTheHeightWorkedOutForThem() {
        let stripShape = CGSize(width: 1600, height: 600)
        let sixteenByNine = CGSize(width: 2560, height: 1440)
        let cases: [(String, TouchscreenID, CGSize, GestureTesterLayout, Bool)] = [
            ("the strip on its own shape", UIFixtures.strip, stripShape, .wide, false),
            ("the ILITEK at 16:9", UIFixtures.ilitek, sixteenByNine, .regular, true),
            ("the ILITEK on the strip's shape", UIFixtures.ilitek, stripShape, .wide, true),
            ("the strip at 16:9", UIFixtures.strip, sixteenByNine, .regular, false),
        ]
        for (name, id, display, layout, multiTouch) in cases {
            let store = store(id, display: display)
            XCTAssertEqual(store.layout, layout, name)
            XCTAssertEqual(store.header.multiTouch, multiTouch, name)
            let metrics = store.metrics
            let rows = store.checklist.rows
            XCTAssertEqual(rows.count, GestureTesterRow.Kind.allCases.count, name)
            let column = CanDoColumn(store: store, checklist: store.checklist, metrics: metrics)
                .frame(width: metrics.canDoWidth - 2 * metrics.panelPadding)
            let height = NSHostingView(rootView: column).fittingSize.height
            XCTAssertEqual(height, metrics.rowsHeight(rows), accuracy: 1,
                           "\(name): laid out \(height), worked out \(metrics.rowsHeight(rows))")
        }
    }
}
