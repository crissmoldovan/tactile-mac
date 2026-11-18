import XCTest
@testable import tactile_probe

/// What the person reads: the summary after a take, the line on the glass, the opening lines,
/// and the apps that must not run alongside.
final class WordsTests: XCTestCase {
    private func take(fingers: Int? = 2, pointerMoved: Bool = true, others: Int = 0, endReason: String? = "lifted") -> Take {
        let facts = fingers.map {
            TakeFacts(interfacesReporting: ["touchscreen"], reportRateHz: ["touchscreen": 97.4], contactIDsSeen: Array(0..<$0),
                      maxContactsDown: $0, maxContactCountField: $0, fingersChangeSlots: false, slotChanges: 0,
                      liftedWithTipUpReport: $0, liftedWithoutTipUpReport: 0, stillDownAtEnd: 0, finalTipUp: "every contact",
                      lastTouchReportHadNoContacts: false, hybridObserved: false, touchFramesSplitAcrossReports: 0,
                      mouseButtonsSeen: nil, mouseButtonReleased: nil)
        }
        let pointer = PointerRecord(from: Point(x: 0, y: 0), to: Point(x: 900, y: 40), moved: pointerMoved, maxDistance: pointerMoved ? 900 : 0,
                                    endDisplayID: 4, endDisplayName: "12.3FHD", samples: [])
        return Take(id: "two-finger-tap", number: 16, title: "Two-finger tap", prompt: "", mode: "exclusive", inputMode: nil,
                    exclusiveInterfaces: ["touchscreen"], attempt: 1, result: fingers == nil ? "no touch seen" : "recorded",
                    endReason: fingers == nil ? nil : endReason, summary: "", promptedAtNs: 0, startedAtNs: fingers == nil ? nil : 1,
                    endedAtNs: nil, waitedSeconds: nil, durationSeconds: nil, reportSpanSeconds: fingers == nil ? nil : 0.3,
                    reportCounts: fingers == nil ? [:] : ["touchscreen": 31], otherTouchscreenReports: others,
                    staleReportsDiscarded: 0, pointer: pointer, facts: facts, tap: nil, reports: [])
    }

    // MARK: The pointer is not mentioned

    func testTheSummaryNeverMentionsThePointer() {
        for moved in [true, false] {
            let text = summarize(take(pointerMoved: moved), stepTimeout: 30, isCorner: false, otherTouchscreen: nil)
            XCTAssertTrue(text.hasPrefix("Got it: 2 fingers, lifted cleanly."), text)
            XCTAssertFalse(text.lowercased().contains("pointer"), text)
        }
    }

    func testThePointerStaysInTheFile() {
        XCTAssertEqual(take(pointerMoved: true).pointer?.moved, true)
    }

    // MARK: The other touchscreen

    func testNoTouchButTheOtherTouchscreenSaysTheWrongScreenWasTouched() {
        let text = summarize(take(fingers: nil, others: 140), stepTimeout: 30, isCorner: false, otherTouchscreen: "TouchScreen by wch.cn")
        XCTAssertTrue(text.contains("No touch seen in 30 s"), text)
        XCTAssertTrue(text.contains("TouchScreen by wch.cn"), text)
        XCTAssertTrue(text.lowercased().contains("wrong screen"), text)
    }

    func testATouchWhileTheOtherTouchscreenWasAlsoTouchedSaysSo() {
        let text = summarize(take(others: 12), stepTimeout: 30, isCorner: false, otherTouchscreen: "TouchScreen by wch.cn")
        XCTAssertTrue(text.hasPrefix("Got it: 2 fingers"), text)
        XCTAssertTrue(text.contains("TouchScreen by wch.cn"), text)
    }

    func testNoTouchAndNothingElseIsPlain() {
        XCTAssertEqual(summarize(take(fingers: nil), stepTimeout: 30, isCorner: false, otherTouchscreen: nil), "No touch seen in 30 s.")
    }

    // MARK: The line on the glass

    func testTheGlassShowsOnlyTheVerdict() {
        XCTAssertEqual(glassVerdict(take(), otherTouchscreen: nil), GlassVerdict(text: "Got it: 2 fingers, lifted cleanly.", good: true))
        XCTAssertEqual(glassVerdict(take(fingers: nil), otherTouchscreen: nil), GlassVerdict(text: "No touch seen.", good: false))
        let wrong = glassVerdict(take(fingers: nil, others: 50), otherTouchscreen: "TouchScreen by wch.cn")
        XCTAssertFalse(wrong.good)
        XCTAssertTrue(wrong.text.contains("OTHER touchscreen"), wrong.text)
        let quiet = glassVerdict(take(endReason: "went quiet with contacts down"), otherTouchscreen: nil)
        XCTAssertTrue(quiet.text.hasPrefix("Got it: 2 fingers"), quiet.text)
    }

    // MARK: Opening lines

    func testTheFirstThingTheSurveySaysIsToQuitTactile() {
        let first = surveyOpeningLine
        XCTAssertTrue(first.hasPrefix("Quit Tactile"), first)
        XCTAssertTrue(first.contains("Touch Up"), first)
    }

    // MARK: Apps that read the touchscreens too

    func testTactileAndTouchUpAreRecognisedWhereverTheyRun() {
        XCTAssertEqual(conflictingAppName(path: "/Applications/Tactile.app/Contents/MacOS/Tactile"), "Tactile")
        XCTAssertEqual(conflictingAppName(path: "/Volumes/Home/someone/src/tactile-mac/build/Build/Products/Release/Tactile.app/Contents/MacOS/Tactile"), "Tactile")
        XCTAssertEqual(conflictingAppName(path: "/Applications/Touch Up.app/Contents/MacOS/Touch Up"), "Touch Up")
        XCTAssertEqual(conflictingAppName(path: "/usr/local/bin/Tactile"), "Tactile")
    }

    func testTheToolsThemselvesAreNotConflictingApps() {
        for path in ["/Volumes/Home/someone/src/tactile-mac/Tools/tactile-probe/.build/release/tactile-probe",
                     "/Volumes/Home/someone/src/tactile-mac/Packages/TactileKit/.build/debug/tactile-devices-check",
                     "/Volumes/Home/someone/src/tactile-mac/Tools/tactile-input-mode/.build/release/tactile-input-mode",
                     "/Applications/Xcode.app/Contents/MacOS/Xcode",
                     "/Volumes/Home/someone/src/tactile-mac/Tactile.xcodeproj"] {
            XCTAssertNil(conflictingAppName(path: path), path)
        }
    }
}
