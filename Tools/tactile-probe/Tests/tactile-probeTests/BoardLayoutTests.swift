import XCTest
@testable import tactile_probe

/// What the windows on the glass say, and that it fits, in type large enough to read at arm's
/// length. Nothing here opens a window: the layout is measured, not shown.
final class BoardLayoutTests: XCTestCase {
    /// The external displays on the desk, in points: HDMI and 12.3FHD carry the touchscreens.
    let sizes: [CGSize] = [
        CGSize(width: 2560, height: 1440), CGSize(width: 1600, height: 600),
        CGSize(width: 3008, height: 1692), CGSize(width: 2048, height: 1280),
    ]
    let touchDisplays: [CGSize] = [CGSize(width: 2560, height: 1440), CGSize(width: 1600, height: 600)]

    private let ilitek = "ILITEK-TP by ILITEK"

    private var everyPhase: [BoardPhase] {
        [.getReady, .waiting(secondsLeft: 30, fraction: 1), .waiting(secondsLeft: 3, fraction: 0.1), .recording(seconds: 12.4),
         .result(GlassVerdict(text: "That came from the OTHER touchscreen (TouchScreen by wch.cn), not this one.", good: false), isLast: false),
         .result(GlassVerdict(text: "Got it: 4 fingers, lifted (some lifts were not reported, the fingers just disappeared).", good: true), isLast: true),
         .finished]
    }

    private func screens(knowsDisplay: Bool) -> [InstructionScreen] {
        var all: [InstructionScreen] = []
        let selection = Takes.all
        for (index, spec) in selection.enumerated() {
            for phase in everyPhase {
                all.append(instructionScreen(take: spec, position: index + 1, of: selection.count, phase: phase,
                                             knowsDisplay: knowsDisplay, touchscreenName: ilitek,
                                             warning: phase == .getReady ? nil : "That was the OTHER touchscreen. Touch THIS screen."))
            }
        }
        return all
    }

    // MARK: Words

    func testATakeSaysItsNumberOfTheTotalItsNameAndWhatToDo() {
        let spec = Takes.take(17)!
        let screen = instructionScreen(take: spec, position: 2, of: 7, phase: .waiting(secondsLeft: 27, fraction: 0.9),
                                       knowsDisplay: true, touchscreenName: ilitek, warning: nil)
        XCTAssertEqual(screen.cue, "TOUCH THIS SCREEN")
        XCTAssertEqual(screen.heading, "Take 17 of 22 · Two-finger twist")
        XCTAssertEqual(screen.body, spec.prompt)
        XCTAssertTrue(screen.footer.contains("2 of 7 in this run"), screen.footer)
        XCTAssertEqual(screen.statusLine, "Waiting for your touch · 27 s")
    }

    func testWithoutAKnownDisplayTheCueNamesTheTouchscreenInstead() {
        let screen = instructionScreen(take: Takes.take(1)!, position: 1, of: 22, phase: .waiting(secondsLeft: 30, fraction: 1),
                                       knowsDisplay: false, touchscreenName: ilitek, warning: nil)
        XCTAssertFalse(screen.cue.contains("THIS SCREEN"), screen.cue)
        XCTAssertTrue(screen.cue.contains("ILITEK-TP"), screen.cue)
    }

    func testThePhasesSayWhatIsHappening() {
        let spec = Takes.take(16)!
        func line(_ phase: BoardPhase) -> String {
            instructionScreen(take: spec, position: 1, of: 7, phase: phase, knowsDisplay: true, touchscreenName: ilitek, warning: nil).statusLine
        }
        XCTAssertTrue(line(.getReady).contains("Enter"))
        XCTAssertEqual(line(.recording(seconds: 1.43)), "Recording · 1.4 s · lift when you have finished")
        XCTAssertEqual(line(.result(GlassVerdict(text: "Got it.", good: true), isLast: false)), "Got it.")
        XCTAssertTrue(line(.finished).contains("Thank you"))
    }

    func testTheKeysLineOffersNextRedoAndStop() {
        let spec = Takes.take(16)!
        let screen = instructionScreen(take: spec, position: 1, of: 7, phase: .result(GlassVerdict(text: "Got it.", good: true), isLast: false),
                                       knowsDisplay: true, touchscreenName: ilitek, warning: nil)
        XCTAssertEqual(screen.keys, "Enter: next take   ·   R: do it again   ·   S: stop here")
        let last = instructionScreen(take: spec, position: 7, of: 7, phase: .result(GlassVerdict(text: "Got it.", good: true), isLast: true),
                                     knowsDisplay: true, touchscreenName: ilitek, warning: nil)
        XCTAssertEqual(last.keys, "Enter: finish   ·   R: do it again")
    }

    func testNoWindowTalksAboutThePointer() {
        for screen in screens(knowsDisplay: true) + screens(knowsDisplay: false) {
            XCTAssertFalse(screen.allText.lowercased().contains("pointer"), screen.heading)
        }
        XCTAssertFalse(NotThisOneScreen(targetName: "HDMI").allText.lowercased().contains("pointer"))
    }

    func testNotThisOneSaysWhereToTouchInstead() {
        let screen = NotThisOneScreen(targetName: "HDMI")
        XCTAssertEqual(screen.title, "Not this one")
        XCTAssertTrue(screen.detail.contains("green frame"), screen.detail)
        XCTAssertTrue(screen.detail.contains("HDMI"), screen.detail)
    }

    // MARK: Fit and size

    func testEveryTakeInEveryPhaseFitsEveryDisplay() {
        for size in sizes {
            for screen in screens(knowsDisplay: true) + screens(knowsDisplay: false) {
                let layout = InstructionLayout(screen, size: size)
                XCTAssertTrue(layout.fits, "\(screen.heading) / \(screen.statusLine) does not fit \(size)")
                for block in layout.blocks {
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(block.frame), "\(block.role) at \(block.frame) in \(size)")
                }
            }
        }
    }

    func testALayoutThatCannotFitSaysSo() {
        let screen = instructionScreen(take: Takes.take(21)!, position: 1, of: 7, phase: .waiting(secondsLeft: 30, fraction: 1),
                                       knowsDisplay: true, touchscreenName: ilitek, warning: String(repeating: "Too long. ", count: 200))
        XCTAssertFalse(InstructionLayout(screen, size: CGSize(width: 300, height: 120)).fits)
    }

    func testThePromptIsLargeEnoughToReadAtArmsLength() {
        // 40 points is 9.4 mm on HDMI (602 mm across 2,560 points) and 7.3 mm on the 12.3-inch
        // strip (292 mm across 1,600 points): readable from 70 cm.
        for size in touchDisplays {
            var smallest = CGFloat.greatestFiniteMagnitude
            for screen in screens(knowsDisplay: true) {
                smallest = min(smallest, InstructionLayout(screen, size: size).bodyFontSize)
            }
            XCTAssertGreaterThanOrEqual(smallest, 40, "\(size)")
        }
    }

    func testTheCueIsTheLargestTypeOnTheScreen() {
        let screen = instructionScreen(take: Takes.take(20)!, position: 5, of: 7, phase: .waiting(secondsLeft: 30, fraction: 1),
                                       knowsDisplay: true, touchscreenName: ilitek, warning: nil)
        for size in sizes {
            let layout = InstructionLayout(screen, size: size)
            let cue = layout.blocks.first { $0.role == .cue }!
            for block in layout.blocks where block.role != .cue {
                XCTAssertGreaterThanOrEqual(cue.fontSize, block.fontSize, "\(block.role) on \(size)")
            }
        }
    }

    func testTheCountdownBarDrainsAsTimePasses() {
        let spec = Takes.take(16)!
        func bar(_ fraction: Double) -> CGFloat? {
            let screen = instructionScreen(take: spec, position: 1, of: 7, phase: .waiting(secondsLeft: 10, fraction: fraction),
                                           knowsDisplay: true, touchscreenName: ilitek, warning: nil)
            return InstructionLayout(screen, size: CGSize(width: 2560, height: 1440)).bar?.filled.width
        }
        XCTAssertGreaterThan(bar(1)!, bar(0.5)!)
        XCTAssertGreaterThan(bar(0.5)!, bar(0.1)!)
        let recording = instructionScreen(take: spec, position: 1, of: 7, phase: .recording(seconds: 2), knowsDisplay: true,
                                          touchscreenName: ilitek, warning: nil)
        XCTAssertNil(InstructionLayout(recording, size: CGSize(width: 2560, height: 1440)).bar)
    }

    func testOnlyAKnownDisplayIsFramed() {
        let spec = Takes.take(16)!
        let known = instructionScreen(take: spec, position: 1, of: 7, phase: .getReady, knowsDisplay: true, touchscreenName: ilitek, warning: nil)
        let unknown = instructionScreen(take: spec, position: 1, of: 7, phase: .getReady, knowsDisplay: false, touchscreenName: ilitek, warning: nil)
        XCTAssertTrue(known.framed)
        XCTAssertFalse(unknown.framed)
    }

    func testNotThisOneAndTheDisplayNumbersFitEveryDisplay() {
        for size in sizes {
            XCTAssertTrue(NotThisOneLayout(NotThisOneScreen(targetName: "12.3FHD"), size: size).fits, "\(size)")
            XCTAssertTrue(NotThisOneLayout(NotThisOneScreen(targetName: nil), size: size).fits, "\(size)")
            XCTAssertTrue(NumberLayout(number: 4, name: "Built-in Retina Display", size: size).fits, "\(size)")
        }
    }
}
