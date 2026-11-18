import XCTest
@testable import tactile_probe

/// The review's findings that can be decided without a survey (2026-11-14, fix round 1).
final class FixRoundOneTests: XCTestCase {
    private let desk = ChoosingTests.deskDisplays
    private let ilitek = "ILITEK-TP by ILITEK"

    private func screen(knows: Bool) -> InstructionScreen {
        instructionScreen(take: Takes.take(16)!, position: 1, of: 7, phase: .waiting(secondsLeft: 30, fraction: 1),
                          knowsDisplay: knows, touchscreenName: ilitek, warning: nil)
    }

    // MARK: 1. Every window catches clicks, so a stray touch on the strip can't make Finder active

    func testWithAKnownDisplayEveryWindowCatchesClicks() {
        let plan = BoardPlan(target: desk[2], displays: desk)
        let windows = boardWindows(plan: plan, instruction: screen(knows: true))
        XCTAssertEqual(Set(windows.contents.keys), [2, 3, 4, 5])
        XCTAssertEqual(windows.catchingClicks, [2, 3, 4, 5], "the Not this one windows too: the strip is never held")
        XCTAssertNil(windows.contents[1], "the Mac's own display, where the terminal is, shows nothing")
    }

    func testWithNoDisplayKnownEveryWindowCatchesClicksToo() {
        let plan = BoardPlan(target: nil, displays: desk)
        let windows = boardWindows(plan: plan, instruction: screen(knows: false))
        XCTAssertEqual(windows.catchingClicks, Set(windows.contents.keys))
        XCTAssertEqual(windows.catchingClicks, [2, 3, 4, 5])
    }

    // MARK: 8. A display with no screen of its own to draw on

    func testATargetWithNoScreenOfItsOwnShowsNoWindowsAnywhere() {
        // Mirrored onto another display: a "Not this one" there would show on the touchscreen's glass too.
        let plan = BoardPlan(target: desk[3], displays: desk, drawable: [1, 2, 3, 5])
        XCTAssertTrue(plan.instructionDisplays.isEmpty)
        XCTAssertTrue(plan.notThisOneDisplays.isEmpty)
        XCTAssertTrue(plan.targetCannotBeDrawnOn)
        XCTAssertTrue(boardWindows(plan: plan, instruction: screen(knows: true)).contents.isEmpty)
    }

    func testDisplaysWithNoScreenOfTheirOwnAreLeftOut() {
        let plan = BoardPlan(target: desk[2], displays: desk, drawable: [1, 2, 3])
        XCTAssertEqual(plan.instructionDisplays.map(\.displayID), [3])
        XCTAssertEqual(plan.notThisOneDisplays.map(\.displayID), [2])
        XCTAssertFalse(plan.targetCannotBeDrawnOn)
        let unknown = BoardPlan(target: nil, displays: desk, drawable: [1, 3, 4])
        XCTAssertEqual(unknown.instructionDisplays.map(\.displayID), [3, 4])
    }

    // MARK: 2. The red warning only while nothing has come from the right touchscreen

    func testTheWarningShowsOnlyBeforeTheRightTouchscreenIsTouched() {
        let before = wrongScreenWarning(otherReports: 40, started: false, otherName: "TouchScreen by wch.cn",
                                        knowsDisplay: true, product: "ILITEK-TP")
        XCTAssertEqual(before, "That was the OTHER touchscreen (TouchScreen by wch.cn). Touch THIS screen.")
        XCTAssertNil(wrongScreenWarning(otherReports: 40, started: true, otherName: "TouchScreen by wch.cn",
                                        knowsDisplay: true, product: "ILITEK-TP"),
                     "once the right one is recording, the warning would contradict the status line")
        XCTAssertNil(wrongScreenWarning(otherReports: 0, started: false, otherName: nil, knowsDisplay: true, product: "ILITEK-TP"))
        let unknown = wrongScreenWarning(otherReports: 3, started: false, otherName: nil, knowsDisplay: false, product: "ILITEK-TP")
        XCTAssertEqual(unknown, "That was the OTHER touchscreen. Use ILITEK-TP instead.")
    }

    // MARK: 3. A redo never loses a good take

    private func attempt(_ result: String, _ number: Int = 1) -> Take {
        Take(id: "pinch", number: 15, title: "Pinch out, then in", prompt: "", mode: "exclusive", inputMode: nil,
             exclusiveInterfaces: [], attempt: number, result: result, endReason: nil, summary: "", promptedAtNs: 0,
             startedAtNs: result == "no touch seen" ? nil : 1, endedAtNs: nil, waitedSeconds: nil, durationSeconds: nil,
             reportSpanSeconds: nil, reportCounts: [:], otherTouchscreenReports: 0, staleReportsDiscarded: 0,
             pointer: nil, facts: nil, tap: nil, reports: [])
    }

    func testTheFirstAttemptIsAlwaysKept() {
        XCTAssertTrue(newAttemptReplaces(earlier: nil, with: attempt("recorded")))
        XCTAssertTrue(newAttemptReplaces(earlier: nil, with: attempt("no touch seen")))
        XCTAssertTrue(newAttemptReplaces(earlier: nil, with: attempt("interrupted")))
    }

    func testANewRecordingReplacesTheEarlierOne() {
        XCTAssertTrue(newAttemptReplaces(earlier: attempt("recorded"), with: attempt("recorded", 2)))
        XCTAssertTrue(newAttemptReplaces(earlier: attempt("no touch seen"), with: attempt("recorded", 2)))
    }

    func testARedoWithoutATouchOrCutShortKeepsTheEarlierRecording() {
        XCTAssertFalse(newAttemptReplaces(earlier: attempt("recorded"), with: attempt("no touch seen", 2)))
        XCTAssertFalse(newAttemptReplaces(earlier: attempt("recorded"), with: attempt("interrupted", 2)))
    }

    func testWithNothingGoodEarlierTheNewerAttemptIsKept() {
        XCTAssertTrue(newAttemptReplaces(earlier: attempt("no touch seen"), with: attempt("no touch seen", 2)))
        XCTAssertTrue(newAttemptReplaces(earlier: attempt("no touch seen"), with: attempt("interrupted", 2)))
    }

    // MARK: 7. How the run ended, at the top of the file and in its name

    func testAFinishedRunSaysWhichTakesItRan() {
        XCTAssertEqual(runEnding(.finished, selection: .from(16)).endedBecause, "finished: takes 16 to 22 (7 takes)")
        XCTAssertTrue(runEnding(.finished, selection: .from(16)).completed)
        XCTAssertEqual(runEnding(.finished, selection: .all).endedBecause, "finished: all 22 takes")
    }

    func testStoppingWithSIsNotCompleted() {
        let end = runEnding(.stoppedByPerson(afterTake: 18), selection: .from(16))
        XCTAssertFalse(end.completed)
        XCTAssertEqual(end.endedBecause, "stopped by the person after take 18, of takes 16 to 22 (7 takes)")
    }

    func testASignalSaysWhereTheRunWas() {
        XCTAssertEqual(runEnding(.signal(2, take: 17, duringTake: true), selection: .from(16)).endedBecause,
                       "stopped by signal 2 during take 17, of takes 16 to 22 (7 takes)")
        XCTAssertEqual(runEnding(.signal(15, take: 17, duringTake: false), selection: .from(16)).endedBecause,
                       "stopped by signal 15 after take 17, of takes 16 to 22 (7 takes)")
        XCTAssertEqual(runEnding(.signal(2, take: nil, duringTake: false), selection: .only([21, 22])).endedBecause,
                       "stopped by signal 2 before the first take, of takes 21 and 22 (2 takes)")
        XCTAssertFalse(runEnding(.signal(2, take: nil, duringTake: false), selection: .all).completed)
    }

    func testARunInProgressSaysSo() {
        XCTAssertEqual(runEnding(.stillRunning, selection: .from(16)).endedBecause, "still running: takes 16 to 22 (7 takes)")
    }

    func testTheEndingsKeepTheirOldOpeningWords() {
        // 1.0 files say "finished", "stopped by signal N" or "still running"; a reader matching the start still works.
        XCTAssertTrue(runEnding(.finished, selection: .only([3])).endedBecause.hasPrefix("finished"))
        XCTAssertTrue(runEnding(.signal(2, take: 3, duringTake: true), selection: .only([3])).endedBecause.hasPrefix("stopped by signal 2"))
        XCTAssertTrue(runEnding(.stillRunning, selection: .all).endedBecause.hasPrefix("still running"))
    }

    func testTheFileNameSaysWhichTakes() {
        XCTAssertEqual(TakeSelection.all.fileNameTag, "")
        XCTAssertEqual(TakeSelection.from(16).fileNameTag, "-takes16to22")
        XCTAssertEqual(TakeSelection.from(22).fileNameTag, "-take22")
        XCTAssertEqual(TakeSelection.only([16, 17, 18, 19, 20, 22]).fileNameTag, "-takes16to20+22")
        XCTAssertEqual(TakeSelection.only([21, 22]).fileNameTag, "-takes21+22")
        XCTAssertEqual(TakeSelection.only([9]).fileNameTag, "-take9")
        XCTAssertEqual(surveyFileName(stamp: "20261115-101500", selection: .from(16)), "tactile-survey-20261115-101500-takes16to22.json")
        XCTAssertEqual(surveyFileName(stamp: "20261115-101500", selection: .all), "tactile-survey-20261115-101500.json")
    }

    // MARK: 9. The display question uses the IDs `list` and --display use

    func testTheQuestionNumbersDisplaysByTheirIDs() {
        XCTAssertEqual(displayQuestionChoices(desk).map(\.number), [2, 3, 4, 5])
        XCTAssertEqual(displayQuestionChoices(desk).map(\.displayID), [2, 3, 4, 5])
    }

    // MARK: 10 and 5, 6. Words

    func testBeforeEnterTheGlassSaysGetReadyNotTouch() {
        let ready = instructionScreen(take: Takes.take(16)!, position: 1, of: 7, phase: .getReady, knowsDisplay: true,
                                      touchscreenName: ilitek, warning: nil)
        XCTAssertEqual(ready.cue, "GET READY")
        XCTAssertFalse(ready.allText.contains("TOUCH THIS SCREEN"), ready.allText)
        XCTAssertTrue(ready.framed, "the green frame already marks the screen")
        let unknown = instructionScreen(take: Takes.take(16)!, position: 1, of: 7, phase: .getReady, knowsDisplay: false,
                                        touchscreenName: ilitek, warning: nil)
        XCTAssertEqual(unknown.cue, "GET READY")
    }

    func testTheEndDoesNotAskForATouch() {
        let done = instructionScreen(take: Takes.take(16)!, position: 7, of: 7, phase: .finished, knowsDisplay: true,
                                     touchscreenName: ilitek, warning: nil)
        XCTAssertFalse(done.cue.contains("TOUCH"), done.cue)
    }

    func testNotThisOnePointsAtTheGreenFrameWhichIsThereFromTheStart() {
        let plate = NotThisOneScreen(targetName: "HDMI")
        XCTAssertTrue(plate.detail.contains("HDMI"), plate.detail)
        XCTAssertTrue(plate.detail.contains("green frame"), plate.detail)
        XCTAssertFalse(plate.detail.contains("TOUCH THIS SCREEN"), "the target says GET READY before Enter")
    }

    func testTheIntroductionMatchesWhatTheSurveyDoes() {
        let lines = surveyIntroduction(stepTimeout: 30, windows: true).joined(separator: "\n")
        XCTAssertTrue(lines.contains("the Mac's own display"), lines)
        XCTAssertFalse(lines.contains("without touch"), lines)
        XCTAssertFalse(lines.contains("moves on by itself"), "a take with no touch waits for Enter: \(lines)")
        XCTAssertTrue(lines.contains("30 s"), lines)
        XCTAssertTrue(lines.contains("held"), "it says the touchscreen is held between takes: \(lines)")
        let plain = surveyIntroduction(stepTimeout: 30, windows: false).joined(separator: "\n")
        XCTAssertFalse(plain.contains("Watch the screen"), plain)
    }

    // Re-review of finding 8: the line printed at every take

    func testTheWaitingLineNamesTheFramedScreenOnlyWhenWindowsAreShown() {
        let hdmi = desk[2]
        let shown = waitingLine(stepTimeout: 30, target: hdmi, product: "ILITEK-TP", windowsShown: true)
        XCTAssertEqual(shown, "  Waiting up to 30 s for your touch on HDMI, the screen that says TOUCH THIS SCREEN...")

        let strip = desk[3]
        let mirrored = waitingLine(stepTimeout: 30, target: strip, product: "ILITEK-TP", windowsShown: false)
        XCTAssertEqual(mirrored, "  Waiting up to 30 s for your touch on 12.3FHD...", "a target with no screen of its own: no window says anything")

        let noWindows = waitingLine(stepTimeout: 30, target: hdmi, product: "ILITEK-TP", windowsShown: false)
        XCTAssertEqual(noWindows, "  Waiting up to 30 s for your touch on HDMI...", "--no-windows")

        let unknown = waitingLine(stepTimeout: 30, target: nil, product: "ILITEK-TP", windowsShown: true)
        XCTAssertEqual(unknown, "  Waiting up to 30 s for your touch on ILITEK-TP...")
        let unnamed = waitingLine(stepTimeout: 45, target: ChoosingTests.display(6, nil, uuid: "U-6"), product: nil, windowsShown: false)
        XCTAssertEqual(unnamed, "  Waiting up to 45 s for your touch on display 6...")
    }

    func testAMirroredTargetIsANoteThatCannotBeMissed() {
        let lines = noScreenNote(displayName: "12.3FHD")
        XCTAssertTrue(lines[0].hasPrefix("Note: 12.3FHD has no screen of its own"), lines[0])
        XCTAssertTrue(lines.joined(separator: " ").contains("in the terminal"), lines.joined(separator: " "))
    }

    func testAFailedHoldSaysRecordingCarriesOn() {
        let failed = holdingLine(interface: "mouse", ok: false, ioReturn: "0xe00002c5")
        XCTAssertTrue(failed.contains("FAILED"), failed)
        XCTAssertTrue(failed.contains("recording carries on"), failed)
        XCTAssertTrue(failed.contains("shared with macOS"), failed)
        XCTAssertEqual(holdingLine(interface: "touchscreen", ok: true, ioReturn: "0x00000000"),
                       "  Holding the touchscreen interface for this tool alone: done (IOReturn 0x00000000).")
    }
}
