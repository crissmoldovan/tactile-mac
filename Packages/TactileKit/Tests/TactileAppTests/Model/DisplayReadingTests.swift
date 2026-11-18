// The conversion from what CoreGraphics and AppKit say about a display to `DisplayFacts`. The
// CoreGraphics calls themselves are in `LiveDisplaySource`, and aren't tested.

import CoreGraphics
import Foundation
@testable import TactileApp
import TactileScreens
import XCTest

/// A mode `width` × `height` pixels, at `points` pixels to the point.
private func mode(_ width: Int, _ height: Int, points: Int = 1, native: Bool = false) -> RawMode {
    RawMode(pixelWidth: width, pixelHeight: height, width: width / points, height: height / points,
            ioFlags: native ? DisplayReading.nativeModeFlag : 0)
}

final class DisplayReadingTests: XCTestCase {

    /// "HDMI" as CoreGraphics and AppKit describe it.
    private let hdmi = RawDisplay(
        displayID: 3, uuid: "4C2D0E10-0000-0000-0A20-0104B53C2278", vendor: 0x4c2d, model: 0x0e10, serial: 1,
        modes: [mode(2560, 1440), mode(1920, 1080), mode(1280, 720, points: 2)], screenSizeMM: CGSize(width: 602, height: 329),
        screenName: "HDMI", bounds: CGRect(x: -252, y: -1440, width: 2560, height: 1440), rotation: 0,
        isBuiltIn: false, isMain: false, mirrors: 0)

    func testADisplayAsItIs() throws {
        let facts = try XCTUnwrap(DisplayReading.facts(from: hdmi))
        XCTAssertEqual(facts, DeskFixture.hdmi)
    }

    func testADisplayWithNoUUIDGetsExactlyNothing() throws {
        for uuid: String? in [nil, "", "   ", "(null)", "00000000-0000-0000-0000-000000000000",
                              "00000000-0000-0000-0000-000000000000\n"] {
            let raw = with(hdmi) { $0.uuid = uuid }
            XCTAssertEqual(try XCTUnwrap(DisplayReading.facts(from: raw)).uuid, "", "\(String(describing: uuid))")
        }
        let lowerCase = with(hdmi) { $0.uuid = "4c2d0e10-0000-0000-0a20-0104b53c2278" }
        XCTAssertEqual(DisplayReading.facts(from: lowerCase)?.uuid, "4c2d0e10-0000-0000-0a20-0104b53c2278",
                       "a real UUID is kept as macOS gives it")
    }

    func testTheReportedSizeIsTakenAsItIs() throws {
        // Turned 90°: CoreGraphics turns the frame and the size together. Neither is turned again.
        let turned = with(hdmi) {
            $0.rotation = 90
            $0.bounds = CGRect(x: -252, y: -2560, width: 1440, height: 2560)
            $0.screenSizeMM = CGSize(width: 329, height: 602)
        }
        let facts = try XCTUnwrap(DisplayReading.facts(from: turned))
        XCTAssertEqual(facts.sizeMM, CGSize(width: 329, height: 602))
        XCTAssertEqual(facts.frame, turned.bounds)
        XCTAssertEqual(facts.rotation, 90)
    }

    func testTheNativeSizeIsUnrotated() throws {
        let turned = with(hdmi) { $0.rotation = 270; $0.bounds = CGRect(x: 0, y: 0, width: 1440, height: 2560) }
        // A mode given as the panel is: kept.
        XCTAssertEqual(DisplayReading.facts(from: turned)?.nativePixels, CGSize(width: 2560, height: 1440))
        // A mode given as macOS has turned it: turned back.
        let rotatedMode = with(turned) { $0.modes = [mode(1440, 2560)] }
        XCTAssertEqual(DisplayReading.facts(from: rotatedMode)?.nativePixels, CGSize(width: 2560, height: 1440))
        // Not turned: kept, whatever its shape.
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.modes = [mode(1080, 1920)] })?
            .nativePixels, CGSize(width: 1080, height: 1920))
        // No mode: no size, which no fingerprint matches by accident.
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.modes = [] })?.nativePixels, .zero)
    }

    func testADisplayThatIsNotFiniteIsLeftOut() {
        let nan = CGFloat.nan, infinity = CGFloat.infinity
        for bounds in [CGRect(x: nan, y: 0, width: 100, height: 100), CGRect(x: 0, y: infinity, width: 100, height: 100),
                       CGRect(x: 0, y: 0, width: nan, height: 100), CGRect(x: 0, y: 0, width: 100, height: -infinity)] {
            XCTAssertNil(DisplayReading.facts(from: with(hdmi) { $0.bounds = bounds }), "\(bounds)")
        }
        // Modes are whole pixels, so a native size can't be anything but finite.
    }

    func testTheNativeModeIsThePanelsOwn() {
        // The 4K LG: its largest mode is a HiDPI one's backing store, 6016 × 3384.
        let lgModes = [mode(6016, 3384, points: 2), mode(3840, 2160, native: true), mode(3008, 1692, points: 2),
                       mode(1920, 1080)]
        XCTAssertEqual(DisplayReading.nativeMode(of: lgModes), mode(3840, 2160, native: true), "flagged native")
        // No flag: the largest mode whose pixels are its points.
        let unflagged = [mode(6016, 3384, points: 2), mode(3840, 2160), mode(1920, 1080)]
        XCTAssertEqual(DisplayReading.nativeMode(of: unflagged), mode(3840, 2160))
        // Only HiDPI modes: the largest.
        XCTAssertEqual(DisplayReading.nativeMode(of: [mode(2880, 1800, points: 2), mode(2560, 1600, points: 2)]),
                       mode(2880, 1800, points: 2))
        XCTAssertNil(DisplayReading.nativeMode(of: []))
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.modes = lgModes })?.nativePixels,
                       CGSize(width: 3840, height: 2160))
    }

    func testNoDisplaysWhileTheyReconfigure() {
        var published = PublishedDisplays(DeskFixture.displays)
        XCTAssertTrue(published.reconfigurationBegan().changed, "a change: the touches on them are cancelled")
        XCTAssertEqual(published.displays, [])
        XCTAssertTrue(published.isReconfiguring)
        XCTAssertFalse(published.reconfigurationBegan().changed, "begun again for another display: no change")

        let after = DeskFixture.displays.filter { $0.displayID != DeskFixture.hdmi.displayID }
        XCTAssertTrue(published.settled(after))
        XCTAssertEqual(published.displays, after)
        XCTAssertFalse(published.isReconfiguring)
        XCTAssertFalse(published.settled(after), "settled again, the same: no change")

        // AppKit's notification without a reconfiguration: whatever CoreGraphics says now.
        XCTAssertTrue(published.settled(DeskFixture.displays))
        XCTAssertEqual(published.displays, DeskFixture.displays)

        var empty = PublishedDisplays([])
        XCTAssertFalse(empty.reconfigurationBegan().changed)
        XCTAssertTrue(empty.isReconfiguring)
    }

    func testAFallbackBelongsToItsOwnReconfiguration() throws {
        var published = PublishedDisplays(DeskFixture.displays)
        let first = try XCTUnwrap(published.reconfigurationBegan().fallback)
        XCTAssertNil(published.reconfigurationBegan().fallback, "the same reconfiguration, another display")
        XCTAssertTrue(published.needsFallback(first), "still under way")
        _ = published.settled(DeskFixture.displays)
        XCTAssertFalse(published.needsFallback(first), "settled")

        // A second reconfiguration begins within 5 s of the first: the first's fallback must not
        // read the displays in the middle of it.
        let second = try XCTUnwrap(published.reconfigurationBegan().fallback)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(published.needsFallback(first))
        XCTAssertTrue(published.needsFallback(second))
    }

    func testTheRest() throws {
        // A mirrored display has no screen of its own.
        let mirror = with(hdmi) { $0.screenName = nil; $0.mirrors = 2 }
        let facts = try XCTUnwrap(DisplayReading.facts(from: mirror))
        XCTAssertEqual(facts.name, "Display")
        XCTAssertEqual(facts.mirrors, 2)
        XCTAssertNil(DisplayReading.facts(from: hdmi)?.mirrors, "0 is no display")
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.rotation = .nan })?.rotation, 0)
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.rotation = 179.9 })?.rotation, 180)
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.rotation = -90 })?.rotation, 270)
        XCTAssertNotNil(DisplayReading.facts(from: with(hdmi) { $0.rotation = 1e300 }), "no trap")
        XCTAssertEqual(DisplayReading.facts(from: with(hdmi) { $0.vendor = .max })?.vendor, Int(UInt32.max))
    }
}
