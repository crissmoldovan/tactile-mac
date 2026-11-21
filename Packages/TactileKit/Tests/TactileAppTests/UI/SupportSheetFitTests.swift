import AppKit
import XCTest

@testable import TactileApp

/// The sizes of the touchscreen check's window, its "what will be sent" sheet and the file viewer on
/// that, worked out from what shows each: never larger than it, on an ordinary display and on a short
/// bar. The sheet and the viewer laid out at these sizes are in `SupportCheckSessionTests`.
final class SupportSheetFitTests: XCTestCase {

    /// The title bars the tests try: macOS 14 and 15's, and macOS 26's.
    private static let titleBars: [CGFloat] = [28, 32]

    func testTheWindowTakesItsSizeWhereThereIsRoom() {
        // The MacBook's display, 1470 × 956, less a 33-point menu bar.
        let macBook = CGRect(x: 0, y: 0, width: 1470, height: 923)
        let frame = SupportCheckWindowFrame.frame(in: macBook, titleBar: 32)
        XCTAssertEqual(frame, CGRect(x: 345, y: 96, width: 780, height: 732), "its content and the title bar, in the middle")
        XCTAssertEqual(SupportCheckWindowFrame.frame(in: macBook, titleBar: 28).height, 728)
    }

    /// On a short touchscreen the window is as tall as the visible frame less the margin, never more;
    /// on a narrow one, as wide.
    func testTheWindowIsNeverLargerThanItsScreen() {
        // The strip, 1600 × 600, less its menu bar.
        let strip = CGRect(x: 228, y: -600, width: 1600, height: 575)
        XCTAssertEqual(SupportCheckWindowFrame.frame(in: strip, titleBar: 32), CGRect(x: 638, y: -592, width: 780, height: 559))
        // A bar of 1920 × 480, less its menu bar.
        let bar = CGRect(x: 0, y: 1440, width: 1920, height: 455)
        XCTAssertEqual(SupportCheckWindowFrame.frame(in: bar, titleBar: 32), CGRect(x: 570, y: 1448, width: 780, height: 439))
        // Upright and narrow.
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 1000)
        XCTAssertEqual(SupportCheckWindowFrame.frame(in: narrow, titleBar: 28), CGRect(x: 8, y: 136, width: 584, height: 728))
        for visible in [strip, bar, narrow, CGRect(x: 0, y: 0, width: 300, height: 200)] {
            for titleBar in Self.titleBars {
                let frame = SupportCheckWindowFrame.frame(in: visible, titleBar: titleBar)
                let room = visible.insetBy(dx: SupportCheckWindowFrame.margin, dy: SupportCheckWindowFrame.margin)
                XCTAssertTrue(room.contains(frame), "\(frame) inside \(room)")
            }
        }
        XCTAssertEqual(SupportCheckWindowFrame.frame(in: CGRect(x: 0, y: 0, width: 10, height: 10), titleBar: 32).size, .zero,
                       "no room at all: nothing, never a negative size")
    }

    func testTheSheetFitsTheWindowsContent() {
        XCTAssertEqual(SupportSheetFit.sheet(in: SupportCheckWindowFrame.content), CGSize(width: 580, height: 676))
        XCTAssertEqual(SupportSheetFit.sheet(in: CGSize(width: 2000, height: 2000)), SupportSheetFit.idealSheet,
                       "never larger than its own size")
        XCTAssertEqual(SupportSheetFit.sheet(in: CGSize(width: 780, height: 508)), CGSize(width: 580, height: 484),
                       "the window that hid Send, on macOS 26")
        XCTAssertEqual(SupportSheetFit.sheet(in: CGSize(width: 500, height: 300)), CGSize(width: 476, height: 276))
        XCTAssertEqual(SupportSheetFit.sheet(in: .zero), .zero)
    }

    func testTheFileViewerFitsTheSheet() {
        XCTAssertEqual(SupportSheetFit.viewer(on: SupportSheetFit.idealSheet), CGSize(width: 556, height: 520),
                       "narrower than its own size, as the sheet is")
        XCTAssertEqual(SupportSheetFit.viewer(on: CGSize(width: 580, height: 383)), CGSize(width: 556, height: 359))
        XCTAssertEqual(SupportSheetFit.viewer(on: CGSize(width: 2000, height: 2000)), SupportSheetFit.idealViewer)
    }

    /// At every height of display from a sliver to a tall one, in both title bars: the window inside
    /// the visible frame, the sheet inside the window's content and the viewer inside the sheet, each
    /// less its margin.
    func testEachFitsWhatShowsItAtAnySize() {
        for height in stride(from: CGFloat(120), through: 1600, by: 7) {
            for titleBar in Self.titleBars {
                let visible = CGRect(x: -1920, y: 300, width: 1920, height: height)
                let frame = SupportCheckWindowFrame.frame(in: visible, titleBar: titleBar)
                XCTAssertTrue(visible.contains(frame) || frame.isEmpty, "the window at \(height)")
                let content = CGSize(width: frame.width, height: max(0, frame.height - titleBar))
                let sheet = SupportSheetFit.sheet(in: content)
                XCTAssertLessThanOrEqual(sheet.height, max(0, content.height - 2 * SupportSheetFit.margin), "the sheet at \(height)")
                XCTAssertLessThanOrEqual(sheet.width, max(0, content.width - 2 * SupportSheetFit.margin), "the sheet at \(height)")
                let viewer = SupportSheetFit.viewer(on: sheet)
                XCTAssertLessThanOrEqual(viewer.height, max(0, sheet.height - 2 * SupportSheetFit.margin), "the viewer at \(height)")
                XCTAssertLessThanOrEqual(viewer.width, max(0, sheet.width - 2 * SupportSheetFit.margin), "the viewer at \(height)")
            }
        }
    }
}
