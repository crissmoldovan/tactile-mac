import CoreGraphics
import Foundation
import XCTest
@testable import TactileScreens

// The desk's displays are `DeskDisplays`, in DisplayMatcherTests.swift.

/// A display with what `SurfaceSize` reads: its frame and the size it reports.
private func display(_ frame: CGRect, reporting sizeMM: CGSize = .zero) -> DisplayFacts {
    DisplayFacts(
        displayID: 80, uuid: "80808080-0000-0000-0000-000000000080", vendor: 0x1234, model: 0x0080, serial: 0,
        nativePixels: CGSize(width: 1920, height: 1080), sizeMM: sizeMM, name: "Test", frame: frame, rotation: 0,
        isBuiltIn: false, isMain: false, mirrors: nil)
}

/// A display whose frame is `width` × `height` points, at the origin.
private func display(_ width: CGFloat, _ height: CGFloat, reporting sizeMM: CGSize = .zero) -> DisplayFacts {
    display(CGRect(x: 0, y: 0, width: width, height: height), reporting: sizeMM)
}

private func assertSize(
    _ actual: CGSize, _ width: CGFloat, _ height: CGFloat, accuracy: CGFloat, _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(actual.width, width, accuracy: accuracy, "width of \(actual) \(message())", file: file, line: line)
    XCTAssertEqual(actual.height, height, accuracy: accuracy, "height of \(actual) \(message())", file: file, line: line)
}

/// Whether the engine can divide by both sides of `size`: each is finite and above zero.
private func isUsable(_ size: CGSize) -> Bool {
    size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
}

final class SurfaceSizeTests: XCTestCase {

    // MARK: - The brief's table

    /// Both displays report a plausible size, 27″ and 10.1″; the diagonal the person confirmed wins.
    func testAnOverrideWinsAndKeepsThePicturesShape() {
        let hdmi = SurfaceSize.millimetres(display: DeskDisplays.hdmi, diagonalInches: 23.8)
        assertSize(hdmi, 526.9, 296.4, accuracy: 0.1)
        XCTAssertEqual(hdmi.width / hdmi.height, 2560 / 1440, accuracy: 1e-12)
        XCTAssertEqual(SurfaceSize.diagonalInches(of: hdmi), 23.8, accuracy: 1e-12)

        let strip = SurfaceSize.millimetres(display: DeskDisplays.strip, diagonalInches: 12.3)
        assertSize(strip, 292.5, 109.7, accuracy: 0.1)
        XCTAssertEqual(strip.width / strip.height, 1600 / 600, accuracy: 1e-12)
        XCTAssertEqual(SurfaceSize.diagonalInches(of: strip), 12.3, accuracy: 1e-12)
    }

    /// 2048 points across 391 mm is 133 points per inch.
    func testAPlausibleReportedSizeIsUsed() {
        let reported = CGSize(width: 391, height: 240)
        XCTAssertEqual(SurfaceSize.millimetres(display: display(2048, 1280, reporting: reported), diagonalInches: nil), reported)
    }

    /// 1600 points across 16 mm is 2,540 points per inch.
    func testAnImplausibleReportedSizeFallsBackTo96() {
        XCTAssertEqual(SurfaceSize.millimetresPerInch, 25.4)
        XCTAssertEqual(SurfaceSize.assumedDensity, 96)
        let size = SurfaceSize.millimetres(display: display(1600, 600, reporting: CGSize(width: 16, height: 6)), diagonalInches: nil)
        assertSize(size, 423.3, 158.75, accuracy: 0.1)
    }

    func testNoReportedSizeFallsBackTo96() {
        let size = SurfaceSize.millimetres(display: display(1600, 600, reporting: .zero), diagonalInches: nil)
        assertSize(size, 423.3, 158.75, accuracy: 0.1)
        XCTAssertTrue(isUsable(size), "\(size)")
        // One side zero is no reported size either.
        for reported in [CGSize(width: 240, height: 0), CGSize(width: 0, height: 90)] {
            let size = SurfaceSize.millimetres(display: display(1600, 600, reporting: reported), diagonalInches: nil)
            assertSize(size, 423.3, 158.75, accuracy: 0.1, "reporting \(reported)")
        }
    }

    func testDiagonalInches() {
        XCTAssertEqual(SurfaceSize.diagonalInches(of: CGSize(width: 526.9, height: 296.4)), 23.8, accuracy: 0.05)
        XCTAssertEqual(SurfaceSize.diagonalInches(of: CGSize(width: 240, height: 90)), 10.1, accuracy: 0.05)
    }

    // MARK: - Beyond the table

    /// What the override is for: without one, the desk's two touchscreen displays give the size they
    /// report, which is plausible (108 and 169 points per inch) and wrong.
    func testWithoutAnOverrideTheDesksDisplaysGiveTheSizeTheyReport() {
        let hdmi = SurfaceSize.millimetres(display: DeskDisplays.hdmi, diagonalInches: nil)
        XCTAssertEqual(hdmi, CGSize(width: 602, height: 329))
        XCTAssertEqual(SurfaceSize.diagonalInches(of: hdmi), 27.0, accuracy: 0.05)
        let strip = SurfaceSize.millimetres(display: DeskDisplays.strip, diagonalInches: nil)
        XCTAssertEqual(strip, CGSize(width: 240, height: 90))
        XCTAssertEqual(SurfaceSize.diagonalInches(of: strip), 10.1, accuracy: 0.05)
    }

    /// A display turned to portrait: its frame is tall, and so is the size it reports.
    func testAPortraitPictureKeepsItsShape() {
        let reported = CGSize(width: 329, height: 602)
        let portrait = display(1440, 2560, reporting: reported)
        XCTAssertEqual(SurfaceSize.millimetres(display: portrait, diagonalInches: nil), reported)
        assertSize(SurfaceSize.millimetres(display: portrait, diagonalInches: 23.8), 296.4, 526.9, accuracy: 0.1)
        assertSize(SurfaceSize.millimetres(display: display(1440, 2560), diagonalInches: nil), 381, 677.33, accuracy: 0.01)
    }

    /// A diagonal that is zero, negative or not a finite number is ignored, and so is one too large
    /// to give a finite size: the reported size, or 96 per inch, is used as if none were given.
    func testAnUnusableOverrideIsIgnored() {
        let bad: [Double] = [0, -0.0, -23.8, .nan, .signalingNaN, .infinity, -.infinity, .greatestFiniteMagnitude]
        for diagonal in bad {
            XCTAssertEqual(
                SurfaceSize.millimetres(display: DeskDisplays.hdmi, diagonalInches: diagonal), CGSize(width: 602, height: 329),
                "\(diagonal)")
            assertSize(
                SurfaceSize.millimetres(display: display(1600, 600), diagonalInches: diagonal), 423.3, 158.75, accuracy: 0.1,
                "\(diagonal)")
        }
    }

    /// The density is the frame's width over the reported width, in points per inch, and must be
    /// 50 to 400. The height is tested too: a plausible width with an odd height is no size.
    func testTheReportedSizeMustImply50To400PointsPerInch() {
        XCTAssertEqual(SurfaceSize.plausibleDensities, 50...400)
        for (density, plausible) in [(49.9, false), (50.1, true), (133.0, true), (399.9, true), (400.1, false)] {
            let reported = CGSize(width: 1000 * 25.4 / density, height: 500 * 25.4 / density)
            let size = SurfaceSize.millimetres(display: display(1000, 500, reporting: reported), diagonalInches: nil)
            if plausible {
                XCTAssertEqual(size, reported, "\(density) per inch")
            } else {
                assertSize(size, 264.58, 132.29, accuracy: 0.01, "\(density) per inch")
            }
        }
        let oddHeight = CGSize(width: 1000 * 25.4 / 133, height: 1)
        assertSize(
            SurfaceSize.millimetres(display: display(1000, 500, reporting: oddHeight), diagonalInches: nil), 264.58, 132.29,
            accuracy: 0.01)
    }

    /// The height's density is tested as the width's: a reported 600 × 1 mm across 2560 × 1440
    /// points is 108 points per inch across and 36,576 down, so it falls back to 96 per inch. Exactly
    /// 50 and exactly 400 are plausible, on either side.
    func testTheReportedHeightMustImply50To400PointsPerInchToo() {
        let flat = SurfaceSize.millimetres(display: display(2560, 1440, reporting: CGSize(width: 600, height: 1)), diagonalInches: nil)
        assertSize(flat, 677.33, 381, accuracy: 0.01)

        // Across 1000 × 500 points: 508 mm is 50 per inch across, 31.75 mm 400 per inch down; 63.5 mm
        // is 400 across and 254 mm 50 down.
        for reported in [CGSize(width: 508, height: 31.75), CGSize(width: 63.5, height: 254)] {
            XCTAssertEqual(
                SurfaceSize.millimetres(display: display(1000, 500, reporting: reported), diagonalInches: nil), reported,
                "\(reported)")
        }
        // The width at 133 per inch, the height just outside.
        for (density, plausible) in [(49.9, false), (50.1, true), (399.9, true), (400.1, false)] {
            let reported = CGSize(width: 1000 * 25.4 / 133, height: 500 * 25.4 / density)
            let size = SurfaceSize.millimetres(display: display(1000, 500, reporting: reported), diagonalInches: nil)
            if plausible {
                XCTAssertEqual(size, reported, "\(density) per inch down")
            } else {
                assertSize(size, 264.58, 132.29, accuracy: 0.01, "\(density) per inch down")
            }
        }
    }

    /// A diagonal the person confirms is used only from 3 to 200 inches, the range the app offers;
    /// any other is passed over as if none were given.
    func testAnOverrideIsUsedOnlyFrom3To200Inches() {
        XCTAssertEqual(SurfaceSize.plausibleDiagonals, 3...200)
        for diagonal in [1e-300, 2.9, 200.1, 1e300] {
            XCTAssertEqual(
                SurfaceSize.millimetres(display: DeskDisplays.hdmi, diagonalInches: diagonal), CGSize(width: 602, height: 329),
                "\(diagonal)")
            assertSize(
                SurfaceSize.millimetres(display: display(1600, 600), diagonalInches: diagonal), 423.3, 158.75, accuracy: 0.1,
                "\(diagonal)")
        }
        for diagonal in [3.0, 200.0] {
            let size = SurfaceSize.millimetres(display: DeskDisplays.hdmi, diagonalInches: diagonal)
            XCTAssertEqual(SurfaceSize.diagonalInches(of: size), diagonal, accuracy: 1e-12, "\(diagonal)")
            XCTAssertEqual(size.width / size.height, 2560 / 1440, accuracy: 1e-12, "\(diagonal)")
        }
    }

    /// A frame with a side that is zero, negative or not finite has no shape and no density: the
    /// answer is the fixed size, 96 per inch on a 1920 × 1080 picture, whatever else is given.
    func testAFrameWithNoUsableSizeGivesTheFixedSize() {
        XCTAssertEqual(SurfaceSize.fallbackPicture, CGSize(width: 1920, height: 1080))
        assertSize(SurfaceSize.fallback, 508, 285.75, accuracy: 1e-9)
        let frames: [CGRect] = [
            .zero, .null,
            CGRect(x: 0, y: 0, width: 1600, height: 0), CGRect(x: 0, y: 0, width: 0, height: 600),
            CGRect(x: 1700, y: 800, width: -1600, height: -600), CGRect(x: 0, y: 0, width: -1600, height: 600),
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 600), CGRect(x: 0, y: 0, width: 1600, height: CGFloat.infinity),
            CGRect(x: 0, y: 0, width: -CGFloat.infinity, height: 600),
        ]
        for frame in frames {
            for diagonal in [nil, 12.3] as [Double?] {
                let size = SurfaceSize.millimetres(
                    display: display(frame, reporting: CGSize(width: 240, height: 90)), diagonalInches: diagonal)
                XCTAssertEqual(size, SurfaceSize.fallback, "\(frame), \(String(describing: diagonal))")
            }
        }
        // A frame so wide that 96 per inch overflows has nothing else to fall back on either.
        let huge = display(.greatestFiniteMagnitude, 1080)
        XCTAssertEqual(SurfaceSize.millimetres(display: huge, diagonalInches: nil), SurfaceSize.fallback)
    }

    /// Whatever it is given, both sides of the answer are finite and above zero.
    func testNeverGivesASideThatIsZeroNegativeOrNotFinite() {
        let big = CGFloat.greatestFiniteMagnitude, tiny = CGFloat.leastNonzeroMagnitude
        let sides: [CGFloat] = [1600, 600, 0, -600, .nan, .infinity, -.infinity, big, tiny, 1e-300, 1e300]
        var frames = sides.flatMap { width in sides.map { height in CGRect(x: 0, y: 0, width: width, height: height) } }
        frames += [.null, .infinite, CGRect(x: 1700, y: 800, width: -1600, height: -600)]
        let reported: [CGSize] = [
            .zero, CGSize(width: 240, height: 90), CGSize(width: 16, height: 6), CGSize(width: -240, height: -90),
            CGSize(width: CGFloat.nan, height: 90), CGSize(width: 240, height: CGFloat.infinity),
            CGSize(width: big, height: big), CGSize(width: tiny, height: tiny),
        ]
        let diagonals: [Double?] = [
            nil, 12.3, 0, -12.3, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude, 1e-300,
            1e300,
        ]
        var checked = 0
        for frame in frames {
            for sizeMM in reported {
                for diagonal in diagonals {
                    let size = SurfaceSize.millimetres(display: display(frame, reporting: sizeMM), diagonalInches: diagonal)
                    if !isUsable(size) {
                        XCTFail("\(size) for frame \(frame), reporting \(sizeMM), diagonal \(String(describing: diagonal))")
                    }
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 124 * 8 * 11)
    }
}
