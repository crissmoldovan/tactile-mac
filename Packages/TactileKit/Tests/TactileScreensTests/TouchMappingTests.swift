import CoreGraphics
import Foundation
import XCTest
import TactileScreens

// The desk's displays are `DeskDisplays`, in DisplayMatcherTests.swift.

/// A display with what the mapping reads: its native size, its frame and its rotation.
private func display(
    native: CGSize = CGSize(width: 1920, height: 1080), frame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
    rotation: Int = 0
) -> DisplayFacts {
    DisplayFacts(
        displayID: 70, uuid: "70707070-0000-0000-0000-000000000070", vendor: 0x1234, model: 0x0070, serial: 0,
        nativePixels: native, sizeMM: .zero, name: "Test", frame: frame, rotation: rotation, isBuiltIn: false,
        isMain: false, mirrors: nil)
}

/// `display` showing `content`'s picture. Its own frame is left as it was, unlike `content`'s, so a
/// test can tell which of the two a desktop point went through.
private func mirroring(_ display: DisplayFacts, _ content: DisplayFacts) -> DisplayFacts {
    var display = display
    display.mirrors = content.displayID
    return display
}

/// The mapping, or `nil` when there is none.
private func maybeMapping(
    _ orientation: Orientation = .asFitted, _ alignment: GlassAlignment = .wholeGlass, display: DisplayFacts = display(),
    content: DisplayFacts? = nil
) -> TouchMapping? {
    TouchMapping(orientation: orientation, alignment: alignment, display: display, content: content)
}

/// The mapping, which the test expects there to be.
private func mapping(
    _ orientation: Orientation = .asFitted, _ alignment: GlassAlignment = .wholeGlass, display: DisplayFacts = display(),
    content: DisplayFacts? = nil, file: StaticString = #filePath, line: UInt = #line
) throws -> TouchMapping {
    try XCTUnwrap(
        maybeMapping(orientation, alignment, display: display, content: content),
        "no mapping for \((content ?? display).frame)", file: file, line: line)
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

private func assertPoint(
    _ actual: CGPoint, _ expected: CGPoint, accuracy: CGFloat = 1e-12, _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(
        actual.x, expected.x, accuracy: accuracy, "x: \(actual) ≠ \(expected) \(message())", file: file, line: line)
    XCTAssertEqual(
        actual.y, expected.y, accuracy: accuracy, "y: \(actual) ≠ \(expected) \(message())", file: file, line: line)
}

private func isClose(_ a: CGPoint, _ b: CGPoint, accuracy: CGFloat = 1e-9) -> Bool {
    abs(a.x - b.x) <= accuracy && abs(a.y - b.y) <= accuracy
}

/// 0…1 brought into range, as step 2 does.
private func clamped(_ value: CGFloat) -> CGFloat {
    min(max(value, 0), 1)
}

/// A grid over `range` in `steps` equal steps, on both axes.
private func grid(_ range: ClosedRange<CGFloat>, steps: Int) -> [CGPoint] {
    let values = (0...steps).map { range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat($0) / CGFloat(steps) }
    return values.flatMap { x in values.map { y in point(x, y) } }
}

/// A frame of `size` as macOS gives it for a display turned `rotation` degrees: the sides swap at
/// 90° and 270°.
private func turned(_ size: CGSize, _ rotation: Int) -> CGRect {
    rotation == 90 || rotation == 270
        ? CGRect(x: 0, y: 0, width: size.height, height: size.width) : CGRect(origin: .zero, size: size)
}

final class TouchMappingTests: XCTestCase {

    // MARK: - The brief's tests

    func testAsFittedWholeGlassUnrotatedIsTheIdentity() throws {
        assertPoint(try mapping().displayPoint(forGlass: point(0.2, 0.7)), point(0.2, 0.7))
        assertPoint(Orientation.asFitted.apply(point(0.2, 0.7)), point(0.2, 0.7))
        XCTAssertEqual(Orientation.asFitted, Orientation(quarterTurns: 0, isFlipped: false))
        XCTAssertEqual(GlassAlignment.wholeGlass.pictureRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testEachQuarterTurn() {
        let p = point(0.2, 0.7)
        assertPoint(Orientation(quarterTurns: 1, isFlipped: false).apply(p), point(0.3, 0.2))
        assertPoint(Orientation(quarterTurns: 2, isFlipped: false).apply(p), point(0.8, 0.3))
        assertPoint(Orientation(quarterTurns: 3, isFlipped: false).apply(p), point(0.7, 0.8))
    }

    func testAFlipMirrorsLeftAndRightBeforeTurning() {
        let p = point(0.2, 0.7)
        assertPoint(Orientation(quarterTurns: 0, isFlipped: true).apply(p), point(0.8, 0.7))
        assertPoint(Orientation(quarterTurns: 1, isFlipped: true).apply(p), point(0.3, 0.8))
    }

    func testInverseUndoesApplyForAllEight() {
        // Past the glass's edges too: neither clamps.
        let points = grid(-0.2...1.2, steps: 14)
        for orientation in Orientation.allCases {
            for p in points {
                assertPoint(orientation.inverse(orientation.apply(p)), p, "\(orientation), \(p)")
                assertPoint(orientation.apply(orientation.inverse(p)), p, "\(orientation), \(p)")
            }
        }
    }

    func testTheEightOrientationsAreAllDifferent() {
        XCTAssertEqual(Orientation.allCases.count, 8)
        XCTAssertEqual(Set(Orientation.allCases).count, 8)
        XCTAssertEqual(Orientation.allCases.first, Orientation.asFitted)
        let images = Orientation.allCases.map { $0.apply(point(0.2, 0.7)) }
        for i in images.indices {
            for j in images.indices where j != i {
                XCTAssertFalse(isClose(images[i], images[j]), "\(Orientation.allCases[i]) and \(Orientation.allCases[j])")
            }
        }
    }

    func testAlignmentRescalesAndClamps() throws {
        let aligned = try mapping(.asFitted, GlassAlignment(pictureRect: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9)))
        assertPoint(aligned.displayPoint(forGlass: point(0.5, 0.5)), point(0.5, 0.5))
        assertPoint(aligned.displayPoint(forGlass: point(0.1, 0.05)), point(0, 0))
        assertPoint(aligned.displayPoint(forGlass: point(0.02, 0.5)), point(0, 0.5))
        assertPoint(aligned.displayPoint(forGlass: point(0.9, 0.95)), point(1, 1))
    }

    func testMacOSRotationMatchesTheAppsOwn() {
        let p = point(0.2, 0.7)
        assertPoint(TouchMapping.rotate(p, by: 90), point(0.3, 0.2))
        assertPoint(TouchMapping.rotate(p, by: 180), point(0.8, 0.3))
        assertPoint(TouchMapping.rotate(p, by: 270), point(0.7, 0.8))
        XCTAssertEqual(TouchMapping.rotate(p, by: 0), p)
    }

    func testAllEightOrientationsAgainstAllFourRotations() throws {
        let rect = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9)
        let alignment = GlassAlignment(pictureRect: rect)
        // Some of these fall outside the picture and are clamped.
        let points = grid(-0.25...1.25, steps: 12)
        var checked = 0
        for orientation in Orientation.allCases {
            for rotation in [0, 90, 180, 270] {
                let native = CGSize(width: 1920, height: 1080)
                let mapping = try mapping(
                    orientation, alignment,
                    display: display(native: native, frame: turned(native, rotation), rotation: rotation))
                for glass in points {
                    let oriented = orientation.apply(glass)
                    let aligned = point(
                        clamped((oriented.x - rect.minX) / rect.width), clamped((oriented.y - rect.minY) / rect.height))
                    let shown = mapping.displayPoint(forGlass: glass)
                    assertPoint(shown, TouchMapping.rotate(aligned, by: rotation), "\(orientation), \(rotation)°, \(glass)")
                    assertPoint(mapping.nativePoint(forDisplay: shown), aligned, "\(orientation), \(rotation)°, \(glass)")
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 8 * 4 * 13 * 13)

        // One worked by hand: flipped, (0.2, 0.7) → (0.8, 0.7); one turn → (0.3, 0.8); aligned →
        // (0.25, 0.8333…); macOS's 90° → (0.1666…, 0.25).
        let worked = try mapping(
            Orientation(quarterTurns: 1, isFlipped: true), alignment,
            display: display(frame: CGRect(x: 0, y: 0, width: 1080, height: 1920), rotation: 90))
        assertPoint(worked.displayPoint(forGlass: point(0.2, 0.7)), point(1.0 / 6, 0.25))
        assertPoint(worked.nativePoint(forDisplay: point(1.0 / 6, 0.25)), point(0.25, 5.0 / 6))
    }

    func testDesktopPointUsesTheDisplaysFrame() throws {
        let left = display(frame: CGRect(x: -1600, y: 1329, width: 1600, height: 600))
        assertPoint(try mapping(display: left).desktopPoint(forDisplay: point(0.5, 0.5)), point(-800, 1629))
    }

    func testATouchAtTheFarEdgeStaysOnItsOwnDisplay() throws {
        let left = display(frame: CGRect(x: -1600, y: 1329, width: 1600, height: 600))
        // The far edges, x = 0 and y = 1929, aren't this display's: one point in.
        assertPoint(try mapping(display: left).desktopPoint(forDisplay: point(1, 1)), point(-1, 1928))
        // The near edges are.
        assertPoint(try mapping(display: left).desktopPoint(forDisplay: point(0, 0)), point(-1600, 1329))
    }

    /// A frame that isn't finite, or has no area, is nowhere a touch can land: no mapping, so no
    /// touches. A display that has just gone away can report exactly that.
    func testNoMappingForADisplayWithNowhereToLand() {
        let nowhere = [
            CGRect.zero, CGRect(x: 100, y: 200, width: 0, height: 600), CGRect(x: 100, y: 200, width: 1600, height: 0),
            CGRect(x: 100, y: 200, width: 1600, height: -600), CGRect(x: 1700, y: 200, width: -1600, height: 600),
            CGRect(x: CGFloat.nan, y: 200, width: 1600, height: 600),
            CGRect(x: 100, y: 200, width: 1600, height: CGFloat.nan),
            CGRect(x: 100, y: CGFloat.infinity, width: 1600, height: 600),
            CGRect(x: 100, y: 200, width: CGFloat.infinity, height: 600), CGRect.null,
            // Finite sides whose far corner isn't.
            CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 1),
        ]
        let strip = display(native: CGSize(width: 1600, height: 600))
        for frame in nowhere {
            XCTAssertNil(maybeMapping(display: display(frame: frame)), "\(frame)")
            // A mirroring display whose content has such a frame, though its own frame is fine.
            var content = DeskDisplays.hdmi
            content.frame = frame
            XCTAssertNil(maybeMapping(display: mirroring(strip, content), content: content), "\(frame)")
            // While it mirrors, its own frame isn't where touches land: the content's is.
            var lost = mirroring(strip, DeskDisplays.hdmi)
            lost.frame = frame
            XCTAssertNotNil(maybeMapping(display: lost, content: DeskDisplays.hdmi), "\(frame)")
        }

        // A display with somewhere to land still gets one, whatever else is odd about it: no native
        // size means no letterbox, an unusable alignment rectangle means the whole glass.
        XCTAssertNotNil(maybeMapping(display: display()))
        for shown in DeskDisplays.all {
            XCTAssertNotNil(maybeMapping(display: shown), shown.name)
        }
        XCTAssertNotNil(
            maybeMapping(
                .asFitted, GlassAlignment(pictureRect: .zero), display: mirroring(display(native: .zero), DeskDisplays.hdmi),
                content: DeskDisplays.hdmi))
    }

    /// A frame that reaches more than a million points from the desktop's origin is no display's,
    /// and gets no mapping either: the points on it would be meaningless (`CGRect.infinite` would
    /// put the middle of the glass at (0, 0)).
    func testNoMappingForAFrameNoDisplayCanHave() {
        let impossible = [
            CGRect.infinite, CGRect(x: 0, y: 0, width: 1e300, height: 1e300), CGRect(x: 1e7, y: 0, width: 100, height: 100),
            CGRect(x: 1700, y: 800, width: -1600, height: -600),
            // Just past the reach, at each end of each axis.
            CGRect(x: 999_900, y: 0, width: 101, height: 100), CGRect(x: -1_000_001, y: 0, width: 100, height: 100),
            CGRect(x: 0, y: 999_900, width: 100, height: 101), CGRect(x: 0, y: -1_000_001, width: 100, height: 100),
        ]
        for frame in impossible {
            XCTAssertNil(maybeMapping(display: display(frame: frame)), "\(frame)")
            var content = DeskDisplays.hdmi
            content.frame = frame
            XCTAssertNil(maybeMapping(display: mirroring(display(), content), content: content), "\(frame)")
        }
        // Reaching exactly a million points is still a display's frame.
        for frame in [
            CGRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000),
            CGRect(x: 999_900, y: 999_900, width: 100, height: 100),
        ] {
            XCTAssertNotNil(maybeMapping(display: display(frame: frame)), "\(frame)")
        }
    }

    func testAMirroredDisplayShowingNarrowerContentHasBarsAtTheSides() throws {
        // 1600 × 600 is 2.667 wide; the content, 2560 × 1440, is 1.778. The picture fills the height
        // and two thirds of the width, from 1/6 to 5/6.
        let strip = mirroring(display(native: CGSize(width: 1600, height: 600)), DeskDisplays.hdmi)
        let mirrored = try mapping(display: strip, content: DeskDisplays.hdmi)
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.5)), point(0.5, 0.5))
        assertPoint(mirrored.displayPoint(forGlass: point(0.1, 0.5)), point(0, 0.5))
        assertPoint(mirrored.displayPoint(forGlass: point(0.9, 0.5)), point(1, 0.5))
        assertPoint(mirrored.displayPoint(forGlass: point(1.0 / 6, 0.2)), point(0, 0.2))
        assertPoint(mirrored.displayPoint(forGlass: point(0.25, 0.2)), point(0.125, 0.2))
        assertPoint(mirrored.displayPoint(forGlass: point(5.0 / 6, 1)), point(1, 1))

        // The desktop point is on the content's frame, (−252, −1440, 2560, 1440), not this display's.
        assertPoint(mirrored.desktopPoint(forDisplay: point(0.5, 0.5)), point(1028, -720))
        assertPoint(mirrored.desktopPoint(forDisplay: point(0, 0)), point(-252, -1440))
    }

    // MARK: - More

    /// The desk's touchscreen displays sit against the main one: "HDMI" above it, its bottom edge at
    /// y = 0, the main display's top row and menu bar; the strip below it. A touch at the very edge of
    /// either picture, or clamped there, lands on its own display, never on the main one.
    func testADesktopPointStaysOnItsDisplay() throws {
        let hdmi = try mapping(display: DeskDisplays.hdmi)
        assertPoint(hdmi.desktopPoint(forDisplay: point(0.5, 1)), point(1028, -1))
        assertPoint(hdmi.desktopPoint(forDisplay: point(1, 0)), point(2307, -1440))
        XCTAssertFalse(DeskDisplays.builtIn.frame.contains(hdmi.desktopPoint(forDisplay: point(0.5, 1))))

        for shown in DeskDisplays.all {
            let mapping = try mapping(display: shown)
            for p in grid(-0.5...1.5, steps: 8) {
                let desktop = mapping.desktopPoint(forDisplay: p)
                XCTAssertTrue(shown.frame.contains(desktop), "\(shown.name): \(p) → \(desktop)")
                for other in DeskDisplays.all where other.displayID != shown.displayID {
                    XCTAssertFalse(other.frame.contains(desktop), "\(shown.name): \(p) → \(desktop), on \(other.name)")
                }
            }
        }

        // A frame less than a point across puts every point at its origin.
        let sliver = try mapping(display: display(frame: CGRect(x: 10, y: 20, width: 0.5, height: 0.25)))
        for p in grid(0...1, steps: 4) {
            XCTAssertEqual(sliver.desktopPoint(forDisplay: p), point(10, 20))
        }
    }

    func testAMirroredDisplayShowingWiderContentHasBarsAboveAndBelow() throws {
        // "Display", 2560 × 1600, is 1.6 wide; the strip's picture, 1600 × 600, is 2.667. The picture
        // fills the width and 0.6 of the height, from 0.2 to 0.8.
        let shown = mirroring(DeskDisplays.display, DeskDisplays.strip)
        let mirrored = try mapping(display: shown, content: DeskDisplays.strip)
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.5)), point(0.5, 0.5))
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.1)), point(0.5, 0))
        assertPoint(mirrored.displayPoint(forGlass: point(0.25, 0.35)), point(0.25, 0.25))
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.95)), point(0.5, 1))
        assertPoint(mirrored.desktopPoint(forDisplay: point(0.5, 0.5)), point(1028, 1629))
        assertPoint(mirrored.nativePoint(forDisplay: point(0.25, 0.25)), point(0.25, 0.35))
    }

    func testMirroredContentOfTheSameShapeHasNoBars() throws {
        // The LG's 3840 × 2160 and HDMI's 2560 × 1440 are both 16 : 9.
        let shown = mirroring(DeskDisplays.lg, DeskDisplays.hdmi)
        let mirrored = try mapping(display: shown, content: DeskDisplays.hdmi)
        for glass in grid(0...1, steps: 10) {
            assertPoint(mirrored.displayPoint(forGlass: glass), glass)
            assertPoint(mirrored.nativePoint(forDisplay: glass), glass)
        }
        assertPoint(mirrored.desktopPoint(forDisplay: point(0.5, 0.5)), point(1028, -720))
    }

    /// The letterbox is worked out on the panel as macOS has turned it: `nativePixels` is unrotated,
    /// so at 90° and 270° its sides swap before they are compared with the content's frame.
    func testARotatedMirroringDisplayFitsThePictureToThePanelAsTurned() throws {
        // 1600 × 600 turned 90° is 600 × 1600: 0.375 wide. The content is 1.778 wide, so it fills the
        // width and 0.375 ÷ 1.778 = 0.2109375 of the height, from 0.39453125 to 0.60546875.
        let strip = mirroring(display(native: CGSize(width: 1600, height: 600), rotation: 90), DeskDisplays.hdmi)
        let mirrored = try mapping(display: strip, content: DeskDisplays.hdmi)
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.5)), point(0.5, 0.5))
        // Glass (0.1, 0.3) is (0.7, 0.1) once turned: on the bar above the picture.
        assertPoint(mirrored.displayPoint(forGlass: point(0.1, 0.3)), point(0.7, 0))
        // 0.39453125 + 0.2109375 × 0.25 = 0.447265625.
        assertPoint(mirrored.displayPoint(forGlass: point(0.447265625, 0.25)), point(0.75, 0.25))
        assertPoint(mirrored.displayPoint(forGlass: point(0.9, 0.3)), point(0.7, 1))
        assertPoint(mirrored.nativePoint(forDisplay: point(0.5, 0)), point(0.39453125, 0.5))
        assertPoint(mirrored.nativePoint(forDisplay: point(0.75, 0.25)), point(0.447265625, 0.25))
    }

    /// The same at 270°, worked by hand on its own: 270 sends (x, y) to (y, 1 − x).
    func testAMirroringDisplayTurned270FitsThePictureToThePanelAsTurned() throws {
        // Turned 270° the panel is again 600 × 1600, so the bars are again 0.39453125 above and below
        // a picture 0.2109375 high.
        let strip = mirroring(display(native: CGSize(width: 1600, height: 600), rotation: 270), DeskDisplays.hdmi)
        let mirrored = try mapping(display: strip, content: DeskDisplays.hdmi)
        assertPoint(mirrored.displayPoint(forGlass: point(0.5, 0.5)), point(0.5, 0.5))
        // Glass (0.1, 0.3) is (0.3, 0.9) once turned: on the bar below the picture. (Unswapped, the
        // panel would be 2.667 wide with bars at the sides, giving (0.2, 0.9).)
        assertPoint(mirrored.displayPoint(forGlass: point(0.1, 0.3)), point(0.3, 1))
        // Glass (0.9, 0.3) is (0.3, 0.1): on the bar above.
        assertPoint(mirrored.displayPoint(forGlass: point(0.9, 0.3)), point(0.3, 0))
        // Glass (0.447265625, 0.25) is (0.25, 0.552734375); (0.552734375 − 0.39453125) ÷ 0.2109375 = 0.75.
        assertPoint(mirrored.displayPoint(forGlass: point(0.447265625, 0.25)), point(0.25, 0.75))
        // Back: display (0.5, 1) is (0.5, 0.60546875) on the panel; undoing 270° gives (1 − y, x).
        assertPoint(mirrored.nativePoint(forDisplay: point(0.5, 1)), point(0.39453125, 0.5))
        assertPoint(mirrored.nativePoint(forDisplay: point(0.25, 0.75)), point(0.447265625, 0.25))
    }

    /// `nativePoint` is the way back from a display point to the display's own unrotated picture:
    /// with the alignment and orientation undone too, it gives a glass point that maps to the same
    /// display point.
    func testNativePointUndoesTheLetterboxAndTheRotation() throws {
        let rect = CGRect(x: 0.02, y: 0.03, width: 0.95, height: 0.93)
        let alignment = GlassAlignment(pictureRect: rect)
        let strip = display(native: CGSize(width: 1600, height: 600))
        let cases: [(DisplayFacts, DisplayFacts?)] = [
            (strip, nil), (mirroring(strip, DeskDisplays.hdmi), DeskDisplays.hdmi),
            (mirroring(DeskDisplays.display, DeskDisplays.strip), DeskDisplays.strip),
            (mirroring(DeskDisplays.lg, DeskDisplays.hdmi), DeskDisplays.hdmi),
        ]
        var checked = 0
        for (shown, content) in cases {
            for rotation in [0, 90, 180, 270] {
                var turnedDisplay = shown
                turnedDisplay.rotation = rotation
                for orientation in Orientation.allCases {
                    let mapping = try mapping(orientation, alignment, display: turnedDisplay, content: content)
                    for target in grid(0...1, steps: 8) {
                        let native = mapping.nativePoint(forDisplay: target)
                        XCTAssertTrue((0...1).contains(native.x) && (0...1).contains(native.y), "\(native)")
                        let glass = orientation.inverse(
                            point(rect.minX + native.x * rect.width, rect.minY + native.y * rect.height))
                        assertPoint(
                            mapping.displayPoint(forGlass: glass), target,
                            "\(shown.name) showing \(content?.name ?? "itself"), \(rotation)°, \(orientation)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 4 * 4 * 8 * 81)
    }

    /// A clamp loses where the finger was: the way back gives the picture's edge.
    func testNativePointCannotRecoverAClampedPoint() throws {
        let aligned = try mapping(.asFitted, GlassAlignment(pictureRect: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9)))
        let outside = aligned.displayPoint(forGlass: point(0.02, 0.5))
        assertPoint(outside, point(0, 0.5))
        assertPoint(aligned.nativePoint(forDisplay: outside), point(0, 0.5))

        let strip = mirroring(display(native: CGSize(width: 1600, height: 600)), DeskDisplays.hdmi)
        let mirrored = try mapping(display: strip, content: DeskDisplays.hdmi)
        let onABar = mirrored.displayPoint(forGlass: point(0.1, 0.5))
        assertPoint(onABar, point(0, 0.5))
        assertPoint(mirrored.nativePoint(forDisplay: onABar), point(1.0 / 6, 0.5))
    }

    /// The 8 are the 8 symmetries of a square's corners: each sends corners to corners and
    /// neighbours to neighbours, no two do it alike, and one after another is one of the 8.
    func testTheEightOrientationsAreTheSymmetriesOfTheSquare() {
        let corners = [point(0, 0), point(1, 0), point(1, 1), point(0, 1)]
        var permutations: Set<[Int]> = []
        for orientation in Orientation.allCases {
            let images = corners.map { orientation.apply($0) }
            let indices = images.compactMap { image in corners.firstIndex(of: image) }
            XCTAssertEqual(indices.count, 4, "\(orientation) sends a corner off the corners: \(images)")
            XCTAssertEqual(Set(indices).count, 4, "\(orientation)")
            for i in 0..<4 {
                let neighbour = (indices[i] - indices[(i + 1) % 4] + 4) % 4
                XCTAssertTrue(neighbour == 1 || neighbour == 3, "\(orientation) parts neighbours")
            }
            permutations.insert(indices)
        }
        XCTAssertEqual(permutations.count, 8)

        // Closed under composition, with an inverse among the eight: (0.2, 0.7)'s eight images are all
        // different, so it tells which one a composition is; a grid confirms it everywhere.
        let probe = point(0.2, 0.7)
        let points = grid(-0.5...1.5, steps: 8)
        for first in Orientation.allCases {
            for second in Orientation.allCases {
                let matches = Orientation.allCases.filter { isClose($0.apply(probe), second.apply(first.apply(probe))) }
                XCTAssertEqual(matches.count, 1, "\(first) then \(second)")
                guard let composed = matches.first else { continue }
                for p in points {
                    assertPoint(second.apply(first.apply(p)), composed.apply(p), "\(first) then \(second)")
                }
            }
            let inverses = Orientation.allCases.filter { isClose($0.apply(first.apply(probe)), probe) }
            XCTAssertEqual(inverses.count, 1, "\(first)")
            for p in points {
                assertPoint(first.inverse(p), inverses[0].apply(p), "\(first)")
            }
        }
    }

    func testAnOrientationCodesAndComesBack() throws {
        for orientation in Orientation.allCases {
            let data = try JSONEncoder().encode(orientation)
            XCTAssertEqual(try JSONDecoder().decode(Orientation.self, from: data), orientation)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(Orientation(quarterTurns: 3, isFlipped: true))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"isFlipped":true,"quarterTurns":3}"#)
    }

    func testQuarterTurnsOutOfRangeAreBroughtIntoRange() throws {
        let cases = [(4, 0), (5, 1), (6, 2), (7, 3), (-1, 3), (-2, 2), (-3, 1), (-4, 0), (Int.max, 3), (Int.min, 0)]
        for (given, kept) in cases {
            let json = #"{"quarterTurns":\#(given),"isFlipped":true}"#
            let decoded = try JSONDecoder().decode(Orientation.self, from: Data(json.utf8))
            XCTAssertEqual(decoded, Orientation(quarterTurns: kept, isFlipped: true), "\(given)")
            XCTAssertEqual(decoded.quarterTurns, kept, "\(given)")

            XCTAssertEqual(Orientation(quarterTurns: given, isFlipped: false).quarterTurns, kept, "\(given)")

            var set = Orientation.asFitted
            set.quarterTurns = given
            XCTAssertEqual(set.quarterTurns, kept, "\(given)")
            XCTAssertTrue(Orientation.allCases.contains(set), "\(given)")
        }
    }

    func testAnAlignmentCodesAndComesBack() throws {
        let fitted = GlassAlignment(pictureRect: CGRect(x: 0.02, y: 0.03, width: 0.95, height: 0.93))
        for alignment in [GlassAlignment.wholeGlass, fitted] {
            let data = try JSONEncoder().encode(alignment)
            XCTAssertEqual(try JSONDecoder().decode(GlassAlignment.self, from: data), alignment)
        }
    }

    // MARK: - Input that isn't what it should be

    /// A rectangle that isn't one, with no width or height, a negative one, or a side that isn't a
    /// number, maps as the whole glass.
    func testADegenerateAlignmentIsTheWholeGlass() throws {
        let degenerate = [
            CGRect(x: 0.1, y: 0.1, width: 0, height: 0.8), CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0),
            CGRect(x: 0.9, y: 0.1, width: -0.8, height: 0.8), CGRect(x: 0.1, y: 0.9, width: 0.8, height: -0.8),
            CGRect(x: CGFloat.nan, y: 0.1, width: 0.8, height: 0.8), CGRect(x: 0.1, y: 0.1, width: CGFloat.nan, height: 0.8),
            CGRect(x: 0.1, y: 0.1, width: CGFloat.infinity, height: 0.8),
            CGRect(x: 0.1, y: -CGFloat.infinity, width: 0.8, height: 0.8),
            CGRect.null, CGRect.zero,
        ]
        for rotation in [0, 90] {
            let whole = try mapping(Orientation(quarterTurns: 1, isFlipped: true), display: display(rotation: rotation))
            for rect in degenerate {
                let odd = try mapping(
                    Orientation(quarterTurns: 1, isFlipped: true), GlassAlignment(pictureRect: rect),
                    display: display(rotation: rotation))
                for glass in grid(-0.25...1.25, steps: 6) {
                    XCTAssertEqual(odd.displayPoint(forGlass: glass), whole.displayPoint(forGlass: glass), "\(rect)")
                }
            }
        }
    }

    /// A rotation is taken modulo 360; one that isn't then 0, 90, 180 or 270 leaves the point, as 0 does.
    func testARotationIsTakenModulo360AndAnUnknownOneIsNone() throws {
        let p = point(0.2, 0.7)
        for degrees in [1, 45, 89, 91, 359, -1, -45, 1_000, Int.max, Int.min] {
            XCTAssertEqual(TouchMapping.rotate(p, by: degrees), p, "\(degrees)")
            XCTAssertEqual(
                try mapping(display: display(rotation: degrees)).displayPoint(forGlass: p), p, "\(degrees)")
        }
        for (degrees, same) in [(360, 0), (-360, 0), (720, 0), (-90, 270), (-180, 180), (-270, 90), (450, 90), (630, 270)] {
            XCTAssertEqual(TouchMapping.rotate(p, by: degrees), TouchMapping.rotate(p, by: same), "\(degrees)")
            XCTAssertEqual(
                try mapping(display: display(rotation: degrees)).displayPoint(forGlass: p),
                try mapping(display: display(rotation: same)).displayPoint(forGlass: p), "\(degrees)")
        }
    }

    /// A native size that isn't one, or two shapes so far apart that their ratio, or the picture's
    /// share of the panel, can't be written: no letterbox. None of these stops the mapping; only the
    /// frame touches land on can do that.
    func testADegenerateLetterboxIsNone() throws {
        let content = DeskDisplays.hdmi
        let natives = [
            CGSize.zero, CGSize(width: 0, height: 600), CGSize(width: 1600, height: 0), CGSize(width: -1600, height: 600),
            CGSize(width: 1600, height: -600), CGSize(width: -1600, height: -600),
            CGSize(width: CGFloat.nan, height: 600), CGSize(width: CGFloat.infinity, height: 600),
            CGSize(width: 1600, height: CGFloat.infinity),
            // Both sides fine, their ratio not: it overflows, or underflows to 0.
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude),
            CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude),
        ]
        for native in natives {
            for rotation in [0, 90] {
                var shown = mirroring(display(native: native), content)
                shown.rotation = rotation
                let mirrored = try mapping(display: shown, content: content)
                let unmirrored = try mapping(display: shown)
                for glass in grid(0...1, steps: 4) {
                    let message = "\(native), \(rotation)°"
                    assertPoint(mirrored.displayPoint(forGlass: glass), unmirrored.displayPoint(forGlass: glass), message)
                    assertPoint(mirrored.nativePoint(forDisplay: glass), unmirrored.nativePoint(forDisplay: glass), message)
                }
            }
        }

        // A content frame with somewhere to land, within a million points of the origin, but a shape
        // whose ratio can't be written: it overflows, or underflows to 0. And a picture whose share
        // of the panel, 1e-300 ÷ 1e300, rounds to nothing.
        let extremes = [
            (CGSize(width: 1600, height: 600), CGRect(x: 10, y: 20, width: 999_000, height: CGFloat.leastNonzeroMagnitude)),
            (CGSize(width: 1600, height: 600), CGRect(x: 10, y: 20, width: CGFloat.leastNonzeroMagnitude, height: 999_000)),
            (CGSize(width: 1e300, height: 1), CGRect(x: 10, y: 20, width: 1e-295, height: 1e5)),
        ]
        for (native, frame) in extremes {
            var odd = content
            odd.frame = frame
            let mirrored = try mapping(display: display(native: native), content: odd)
            for glass in grid(0...1, steps: 4) {
                assertPoint(mirrored.displayPoint(forGlass: glass), glass, "\(native), \(frame)")
                assertPoint(mirrored.nativePoint(forDisplay: glass), glass, "\(native), \(frame)")
            }
        }
    }

    /// A point off the picture or that isn't a number is brought onto the picture first: NaN counts
    /// as 0, and an infinity as the edge it points to.
    func testPointsThatAreNotOnThePictureAreClamped() throws {
        let left = try mapping(display: display(frame: CGRect(x: -1600, y: 1329, width: 1600, height: 600)))
        assertPoint(left.displayPoint(forGlass: point(-0.5, 1.5)), point(0, 1))
        assertPoint(left.displayPoint(forGlass: point(CGFloat.nan, CGFloat.infinity)), point(0, 1))
        assertPoint(left.displayPoint(forGlass: point(-CGFloat.infinity, CGFloat.nan)), point(0, 0))
        assertPoint(left.desktopPoint(forDisplay: point(-0.5, 1.5)), point(-1600, 1928))
        assertPoint(left.desktopPoint(forDisplay: point(CGFloat.nan, CGFloat.infinity)), point(-1600, 1928))
        assertPoint(left.nativePoint(forDisplay: point(2, CGFloat.nan)), point(1, 0))
    }

    /// Whatever a mapping is built from, and whatever point it is given, it never traps and never
    /// gives a point that isn't finite; display and native points are always 0…1. There is no
    /// mapping exactly when the frame touches land on has nowhere for them.
    func testNothingGivesANonFinitePoint() {
        let values: [CGFloat] = [
            0, 0.5, 1, -1, 2, 1e308, -1e308, .infinity, -.infinity, .nan, .leastNonzeroMagnitude,
            .greatestFiniteMagnitude,
        ]
        let points = values.flatMap { x in values.map { y in point(x, y) } }
        let alignments = [
            CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9),
            CGRect(x: 0.5, y: 0.5, width: CGFloat.leastNonzeroMagnitude, height: CGFloat.leastNonzeroMagnitude),
            CGRect(x: -1e308, y: 1e308, width: 1e-308, height: 1e-308), CGRect.infinite, CGRect.null,
            CGRect(x: 0.1, y: 0.1, width: -0.5, height: CGFloat.nan),
        ].map { GlassAlignment(pictureRect: $0) }
        let sizes = [
            CGSize(width: 1600, height: 600), .zero, CGSize(width: CGFloat.nan, height: 1),
            CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.leastNonzeroMagnitude),
        ]
        let frames = [
            CGRect(x: -252, y: -1440, width: 2560, height: 1440), .zero, .null, .infinite,
            CGRect(x: 1e308, y: -1e308, width: 1e308, height: 1e308), CGRect(x: 0, y: 0, width: -100, height: 100),
            CGRect(x: 0, y: 0, width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude),
        ]
        var displays: [DisplayFacts] = []
        for (i, size) in sizes.enumerated() {
            for (j, rotation) in [0, 90, 180, 270, 45, Int.min].enumerated() {
                displays.append(display(native: size, frame: frames[(i + j) % frames.count], rotation: rotation))
            }
        }
        let contents: [DisplayFacts?] = [nil] + frames.map { frame in
            var content = DeskDisplays.hdmi
            content.frame = frame
            return content
        }
        func finite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }
        func onPicture(_ p: CGPoint) -> Bool { (0...1).contains(p.x) && (0...1).contains(p.y) }
        /// Somewhere a touch can land: finite, far corner included, with a width and a height, and its
        /// origin and far corner within a million points of the desktop's origin.
        func landable(_ frame: CGRect) -> Bool {
            let edges = [
                frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, frame.origin.x + frame.size.width,
                frame.origin.y + frame.size.height,
            ]
            let corners = [
                frame.origin.x, frame.origin.y, frame.origin.x + frame.size.width, frame.origin.y + frame.size.height,
            ]
            return edges.allSatisfy(\.isFinite) && frame.size.width > 0 && frame.size.height > 0
                && corners.allSatisfy { abs($0) <= 1_000_000 }
        }

        var checked = 0, mapped = 0, refused = 0
        for (i, shown) in displays.enumerated() {
            for (j, content) in contents.enumerated() {
                let orientation = Orientation.allCases[(i + j) % 8]
                let landing = (content ?? shown).frame
                for alignment in alignments {
                    guard let mapping = maybeMapping(orientation, alignment, display: shown, content: content) else {
                        XCTAssertFalse(landable(landing), "no mapping for \(landing)")
                        refused += 1
                        continue
                    }
                    XCTAssertTrue(landable(landing), "a mapping for \(landing)")
                    mapped += 1
                    for p in points {
                        let onDisplay = mapping.displayPoint(forGlass: p)
                        XCTAssertTrue(onPicture(onDisplay), "\(onDisplay) from \(p), \(mapping)")
                        let native = mapping.nativePoint(forDisplay: p)
                        XCTAssertTrue(onPicture(native), "\(native) from \(p), \(mapping)")
                        let desktop = mapping.desktopPoint(forDisplay: p)
                        XCTAssertTrue(finite(desktop), "\(desktop) from \(p), \(mapping)")
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(mapped + refused, displays.count * contents.count * alignments.count)
        XCTAssertGreaterThan(mapped, 0)
        XCTAssertGreaterThan(refused, 0)
        XCTAssertEqual(checked, mapped * points.count)
    }
}
