// tactile-probe: lists the USB touchscreens on this Mac, and surveys one of them.
//
//   tactile-probe list [--json <path>]
//       Displays and touchscreens, as text. Read-only, and shows no window. --json also writes
//       the same facts as JSON.
//
//   tactile-probe survey [--touchscreen <vendor:product>] [--display <ID or name>]
//                        [--from <take> | --only <take,take,…>] [--out <dir>] [--step-timeout <seconds>] [--no-windows]
//       A guided survey of ONE touchscreen, for a person touching it. Each take's instruction
//       appears on the glass of the display it is on. Writes tactile-survey-YYYYMMDD-HHMMSS.json,
//       with the takes added when not all of them (…-takes16to22.json), into --out (default: the
//       current directory).
//
//   tactile-probe takes                 The takes and their numbers.
//   tactile-probe preview --out <dir>   Pictures of the windows on the glass, as PNG files.
//
// The tool never posts input events and never quits other apps. Its only changes, both inside
// `survey` and both on the surveyed touchscreen, are the Input Mode feature write and exclusive
// opens; on every way out it puts the Input Mode back to the value it found and closes every
// exclusive open. See README.md for the options and the JSON schema.

import Foundation

func fail(_ message: String, code: Int32 = 64) -> Never {
    warn(message)
    exit(code)
}

func runList(jsonPath: String?) -> Int32 {
    let list = buildList(discoverTouchscreens())
    printList(list)
    if let path = jsonPath {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try writeJSON(list, to: url)
            say("")
            say("Wrote \(url.path)")
        } catch {
            fail("Could not write \(url.path): \(error.localizedDescription)", code: 1)
        }
    }
    return 0
}

func runTakes() -> Int32 {
    let states: [TakeState: String] = [.asFound: "as found", .multiTouch: "multi-touch", .exclusive: "held"]
    say("The takes, in the order a survey runs them. Pick some with --from <number> or --only <number,number,…>.")
    for spec in Takes.all {
        say(String(format: "  %2d  %@  (%@; %@)", spec.number, spec.title, spec.id, states[spec.state] ?? ""))
    }
    return 0
}

func runPreview(outDir: String) -> Int32 {
    let dir = URL(fileURLWithPath: (outDir as NSString).expandingTildeInPath)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        fail("Could not create \(dir.path): \(error.localizedDescription)", code: 1)
    }
    let name = "ILITEK-TP by ILITEK"
    let run = TakeSelection.from(16).takes
    func screen(_ number: Int, _ phase: BoardPhase, knows: Bool = true, warning: String? = nil) -> BoardContent {
        let spec = Takes.take(number)!
        let position = (run.firstIndex(of: spec) ?? 0) + 1
        return .instruction(instructionScreen(take: spec, position: position, of: run.count, phase: phase, knowsDisplay: knows,
                                              touchscreenName: name, warning: warning))
    }
    let pictures: [(String, BoardContent, CGSize)] = [
        ("hdmi-ready", screen(16, .getReady), CGSize(width: 2560, height: 1440)),
        ("hdmi-take17-waiting", screen(17, .waiting(secondsLeft: 21, fraction: 0.7)), CGSize(width: 2560, height: 1440)),
        ("hdmi-take22-recording", screen(22, .recording(seconds: 1.4)), CGSize(width: 2560, height: 1440)),
        ("hdmi-take18-wrong-screen", screen(18, .waiting(secondsLeft: 12, fraction: 0.4),
                                            warning: "That was the OTHER touchscreen (TouchScreen by wch.cn). Touch THIS screen."),
         CGSize(width: 2560, height: 1440)),
        ("hdmi-take21-result", screen(21, .result(GlassVerdict(text: "Got it: 2 fingers, lifted cleanly.", good: true), isLast: false)),
         CGSize(width: 2560, height: 1440)),
        ("strip-take21-waiting", screen(21, .waiting(secondsLeft: 30, fraction: 1)), CGSize(width: 1600, height: 600)),
        ("strip-take19-result-none", screen(19, .result(GlassVerdict(text: "No touch seen.", good: false), isLast: false)),
         CGSize(width: 1600, height: 600)),
        ("strip-unknown-display", screen(16, .waiting(secondsLeft: 30, fraction: 1), knows: false), CGSize(width: 1600, height: 600)),
        ("lg-not-this-one", .notThisOne(NotThisOneScreen(targetName: "HDMI")), CGSize(width: 3008, height: 1692)),
        ("strip-not-this-one", .notThisOne(NotThisOneScreen(targetName: "HDMI")), CGSize(width: 1600, height: 600)),
        ("display-number", .number(4, name: "Display"), CGSize(width: 2048, height: 1280)),
    ]
    for (file, content, size) in pictures {
        let url = dir.appendingPathComponent("tactile-probe-\(file).png")
        do {
            try renderBoardPNG(content, size: size, to: url)
            say("Wrote \(url.path)")
        } catch {
            fail("Could not write \(url.path): \(error)", code: 1)
        }
    }
    return 0
}

func runSurvey(_ options: SurveyOptions) -> Int32 {
    // Before anything else, and before any device is opened.
    say(surveyOpeningLine)
    let apps = conflictingApps()
    if !apps.isEmpty {
        for app in apps { say("\(app.name) is running: \(app.text).") }
        say("Quit it, then run this survey again. Nothing was changed.")
        return 3
    }

    let outDir = URL(fileURLWithPath: ((options.outDir ?? FileManager.default.currentDirectoryPath) as NSString).expandingTildeInPath)
    do {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    } catch {
        fail("Could not create \(outDir.path): \(error.localizedDescription)", code: 1)
    }

    let touchscreens = discoverTouchscreens()
    let candidates = touchscreens.map {
        TouchscreenCandidate(number: $0.number, usbID: usbID($0.vendorID, $0.productID), locationID: hexLocation($0.locationID), name: $0.name)
    }
    func listing(_ list: [TouchscreenCandidate]) -> String {
        list.map { "  --touchscreen \($0.usbID)   \($0.name) (location \($0.locationID))" }.joined(separator: "\n")
    }
    let chosen: ProbeTouchscreen
    let reason: ChoiceReason
    switch chooseTouchscreen(named: options.touchscreen, among: candidates) {
    case .chosen(let candidate, let why):
        chosen = touchscreens.first { $0.number == candidate.number }!
        reason = why
    case .noneConnected:
        fail("No touchscreen found. Is one plugged in over USB?", code: 2)
    case .nameOne(let list):
        say("\(list.count) touchscreens are connected. This survey records one at a time: name it with --touchscreen.")
        say(listing(list))
        return 64
    case .notConnected(let id, let list):
        say("No touchscreen with USB ID \(id) is connected. The touchscreens connected now:")
        say(listing(list))
        return 2
    case .cannotTellApart(let list):
        say("\(list.count) connected touchscreens have USB ID \(list[0].usbID), and this tool can't tell them apart:")
        say(listing(list))
        say("Unplug the ones not being surveyed, and run it again.")
        return 64
    }

    let list = buildList(touchscreens)
    let candidate = candidates[chosen.number - 1]
    let display = chooseDisplay(argument: options.display, stateFile: defaultStateFileURL, touchscreen: candidate, displays: list.displays)
    if case .badArgument(let message) = display {
        say(message)
        return 64
    }

    if options.showsWindows { AppKitHost.start() }
    let survey = Survey(touchscreens: touchscreens, chosen: chosen, reason: reason, list: list, options: options, outDir: outDir)
    let safety = Safety.shared
    safety.cleanup = { survey.releaseAll() }
    safety.onSignal = { sig in survey.interrupt(signal: sig) }
    safety.install()
    let code = survey.run(display: display, displayArgument: options.display)
    safety.runCleanup()
    return code
}

func runCommandLine(_ args: [String]) -> Int32 {
    let command: ProbeCommand
    do {
        command = try parseCommandLine(args)
    } catch let error as CommandLineError {
        fail("\(error.message)\n\n\(usageText)")
    } catch {
        fail("\(error)\n\n\(usageText)")
    }
    switch command {
    case .list(let path): return runList(jsonPath: path)
    case .survey(let options): return runSurvey(options)
    case .takes: return runTakes()
    case .preview(let dir): return runPreview(outDir: dir)
    case .version:
        say("\(toolName) \(toolVersion)")
        return 0
    case .help:
        say(usageText)
        return 0
    }
}

exit(runCommandLine(Array(CommandLine.arguments.dropFirst())))
