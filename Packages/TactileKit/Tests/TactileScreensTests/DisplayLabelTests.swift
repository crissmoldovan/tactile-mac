import CoreGraphics
import Foundation
import XCTest
import TactileScreens

// The desk's displays are `DeskDisplays`, in DisplayMatcherTests.swift.

private func label(
    _ display: DisplayFacts, among all: [DisplayFacts] = DeskDisplays.all, customName: String? = nil,
    diagonalInches: Double? = nil
) -> (name: String, detail: String) {
    DisplayLabel.label(for: display, among: all, customName: customName, diagonalInches: diagonalInches)
}

/// `display` with `change` made to it.
private func changed(_ display: DisplayFacts, _ change: (inout DisplayFacts) -> Void) -> DisplayFacts {
    var display = display
    change(&display)
    return display
}

final class DisplayLabelTests: XCTestCase {

    // MARK: - The brief's tests

    func testLabelsForTheDesk() {
        let hdmi = label(DeskDisplays.hdmi, diagonalInches: 23.8)
        XCTAssertEqual(hdmi.name, "HDMI")
        XCTAssertEqual(hdmi.detail, "23.8″ · 2560 × 1440 · above the main display")

        let strip = label(DeskDisplays.strip)
        XCTAssertEqual(strip.name, "12.3FHD")
        XCTAssertEqual(strip.detail, "10.1″ · 1600 × 600 · below the main display")

        let lg = label(DeskDisplays.lg)
        XCTAssertEqual(lg.name, "LG HDR 4K")
        XCTAssertTrue(lg.detail.hasSuffix("right of the main display"), lg.detail)

        let builtIn = label(DeskDisplays.builtIn)
        XCTAssertEqual(builtIn.name, "Built-in")
        XCTAssertTrue(builtIn.detail.hasSuffix("the main display"), builtIn.detail)
    }

    func testACustomNameReplacesTheDisplaysOwn() {
        XCTAssertEqual(label(DeskDisplays.hdmi, customName: "Big touch").name, "Big touch")
        XCTAssertEqual(label(DeskDisplays.hdmi, customName: "").name, "HDMI")
        // The detail stays the display's.
        XCTAssertEqual(label(DeskDisplays.hdmi, customName: "Big touch").detail, label(DeskDisplays.hdmi).detail)
    }

    func testADisplayThatReportsNoSizeHasNoDiagonal() {
        let display = changed(DeskDisplays.hdmi) { $0.sizeMM = .zero }
        let detail = label(display).detail
        XCTAssertTrue(detail.hasPrefix("2560 × 1440"), detail)
        XCTAssertEqual(detail, "2560 × 1440 · above the main display")
    }

    // MARK: - More

    func testTheDesksFiveLabelsInFull() {
        XCTAssertEqual(label(DeskDisplays.builtIn).detail, "14.2″ · 2056 × 1329 · the main display")
        XCTAssertEqual(label(DeskDisplays.lg).detail, "27″ · 3008 × 1692 · right of the main display")
        XCTAssertEqual(label(DeskDisplays.hdmi).detail, "27″ · 2560 × 1440 · above the main display")
        XCTAssertEqual(label(DeskDisplays.strip).detail, "10.1″ · 1600 × 600 · below the main display")
        XCTAssertEqual(label(DeskDisplays.display).detail, "18″ · 2048 × 1280 · left of the main display")
        XCTAssertEqual(label(DeskDisplays.display).name, "Display")

        // With the panel's real size, typed in.
        XCTAssertEqual(
            label(DeskDisplays.strip, diagonalInches: 12.3).detail, "12.3″ · 1600 × 600 · below the main display")
    }

    /// The inch mark is U+2033, the multiplication sign U+00D7 and the dot U+00B7, each part apart
    /// from the next by one space each side: not lookalikes typed into both the code and the tests.
    func testTheMarksAreTheRightCharacters() {
        let detail = label(DeskDisplays.hdmi, diagonalInches: 23.8).detail
        let expected = "23.8\u{2033} \u{00B7} 2560 \u{00D7} 1440 \u{00B7} above the main display"
        XCTAssertEqual(detail.unicodeScalars.map(\.value), expected.unicodeScalars.map(\.value))
    }

    func testTheDiagonalHasOneDecimalUnlessItIsWhole() {
        let cases: [(Double, String)] = [
            (26.96, "27″"), (26.94, "26.9″"), (23.8, "23.8″"), (23.75, "23.8″"), (12.3, "12.3″"),
            (9.96, "10″"), (0.96, "1″"), (27, "27″"), (100, "100″"),
        ]
        for (inches, expected) in cases {
            let detail = label(DeskDisplays.hdmi, diagonalInches: inches).detail
            XCTAssertEqual(detail, "\(expected) · 2560 × 1440 · above the main display", "\(inches)")
        }
        // From the reported size: the LG's 597 × 336 mm is 26.97″.
        XCTAssertEqual(label(DeskDisplays.lg).detail, "27″ · 3008 × 1692 · right of the main display")
    }

    func testAnOverrideIsShownWhenNoSizeIsReported() {
        let display = changed(DeskDisplays.hdmi) { $0.sizeMM = .zero }
        XCTAssertEqual(label(display, diagonalInches: 23.8).detail, "23.8″ · 2560 × 1440 · above the main display")
    }

    /// An override that isn't a size is as good as none: the diagonal comes from the reported size.
    func testAnOverrideThatIsNoSizeIsIgnored() {
        for inches in [0, -23.8, 0.04, .nan, .infinity, -.infinity] {
            let detail = label(DeskDisplays.hdmi, diagonalInches: inches).detail
            XCTAssertEqual(detail, "27″ · 2560 × 1440 · above the main display", "\(inches)")
        }
        // A size too large to write is no size either, and doesn't trap.
        XCTAssertEqual(
            label(DeskDisplays.hdmi, diagonalInches: 1e300).detail, "27″ · 2560 × 1440 · above the main display")
    }

    /// A reported size that isn't one: one side zero, negative, not a number, or too large to write.
    func testAReportedSizeThatIsNoSizeHasNoDiagonal() {
        let sizes = [
            CGSize(width: 602, height: 0), CGSize(width: 0, height: 329), CGSize(width: -602, height: -329),
            CGSize(width: CGFloat.nan, height: 329), CGSize(width: 602, height: CGFloat.infinity),
            CGSize(width: 1e300, height: 1e300),
        ]
        for size in sizes {
            let display = changed(DeskDisplays.hdmi) { $0.sizeMM = size }
            XCTAssertEqual(label(display).detail, "2560 × 1440 · above the main display", "\(size)")
        }
    }

    func testANameThatIsOnlySpaceIsNoName() {
        for name in [" ", "   ", "\t\n", "\u{00A0}", "\u{3000}"] {
            XCTAssertEqual(label(DeskDisplays.hdmi, customName: name).name, "HDMI", name.debugDescription)
        }
        XCTAssertEqual(label(DeskDisplays.hdmi, customName: nil).name, "HDMI")
        XCTAssertEqual(label(DeskDisplays.hdmi, customName: "  Big touch \n").name, "Big touch")
    }

    func testABuiltInDisplayThatIsNotMainSaysBuiltIn() {
        let builtIn = changed(DeskDisplays.builtIn) { $0.isMain = false }
        let lg = changed(DeskDisplays.lg) { $0.isMain = true }
        let all = [builtIn, lg, DeskDisplays.hdmi, DeskDisplays.strip, DeskDisplays.display]
        XCTAssertEqual(label(builtIn, among: all).detail, "14.2″ · 2056 × 1329 · built-in")
        XCTAssertEqual(label(lg, among: all).detail, "27″ · 3008 × 1692 · the main display")
        // A main display that is built in is the main display.
        XCTAssertEqual(label(DeskDisplays.builtIn).detail, "14.2″ · 2056 × 1329 · the main display")
    }

    /// Where a display sits follows the larger gap between centres; an exact diagonal counts as
    /// beside, and a display centred on the main one, as one that mirrors it is, has no direction.
    func testWhereADisplaySitsByItsCentre() {
        // The main display's centre is (1028, 664.5). "Display" is 2048 × 1280.
        func detail(centreX: CGFloat, centreY: CGFloat) -> String {
            let display = changed(DeskDisplays.display) {
                $0.frame = CGRect(x: centreX - 1024, y: centreY - 640, width: 2048, height: 1280)
            }
            return label(display).detail
        }
        let size = "18″ · 2048 × 1280"
        XCTAssertEqual(detail(centreX: 1028 + 2001, centreY: 664.5 - 2000), "\(size) · right of the main display")
        XCTAssertEqual(detail(centreX: 1028 + 2000, centreY: 664.5 - 2001), "\(size) · above the main display")
        XCTAssertEqual(detail(centreX: 1028 - 2000, centreY: 664.5 + 2000), "\(size) · left of the main display")
        XCTAssertEqual(detail(centreX: 1028 + 2000, centreY: 664.5 + 2000), "\(size) · right of the main display")
        XCTAssertEqual(detail(centreX: 1028, centreY: 664.5 + 1), "\(size) · below the main display")
        XCTAssertEqual(detail(centreX: 1028, centreY: 664.5), size)

        let mirror = changed(DeskDisplays.hdmi) {
            $0.mirrors = DeskDisplays.builtIn.displayID
            $0.frame = DeskDisplays.builtIn.frame
        }
        XCTAssertEqual(label(mirror).detail, "27″ · 2056 × 1329")
    }

    /// Without exactly one main display among `all`, no other display says where it sits.
    func testWithoutOneMainDisplayNoneSaysWhereItSits() {
        let noMain = changed(DeskDisplays.builtIn) { $0.isMain = false }
        let twoMains = changed(DeskDisplays.lg) { $0.isMain = true }
        for all in [
            [noMain, DeskDisplays.lg, DeskDisplays.hdmi], [DeskDisplays.builtIn, twoMains, DeskDisplays.hdmi], [],
        ] {
            XCTAssertEqual(label(DeskDisplays.hdmi, among: all).detail, "27″ · 2560 × 1440", "\(all.map(\.name))")
        }
        // A main display still says it is one.
        XCTAssertEqual(label(DeskDisplays.builtIn, among: []).detail, "14.2″ · 2056 × 1329 · the main display")
    }

    /// The picture is the frame in points, as the display is turned now; not its native pixels.
    func testThePictureIsTheFrame() {
        let turned = changed(DeskDisplays.hdmi) {
            $0.rotation = 90
            $0.frame = CGRect(x: -1440, y: -2560, width: 1440, height: 2560)
        }
        XCTAssertEqual(label(turned).detail, "27″ · 1440 × 2560 · above the main display")

        // A frame that isn't one leaves out the picture and where it sits, and doesn't trap.
        for frame in [
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1), CGRect(x: 0, y: 0, width: 1e300, height: 1e300),
        ] {
            let display = changed(DeskDisplays.hdmi) { $0.frame = frame }
            XCTAssertEqual(label(display).detail, "27″", "\(frame)")
        }
    }
}
