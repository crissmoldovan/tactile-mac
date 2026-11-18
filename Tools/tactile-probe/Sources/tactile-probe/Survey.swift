// The guided survey of ONE touchscreen: its takes in order (all, or from a take, or a list), with
// the touchscreen as found, then switched to multi-touch, then held exclusively, as each take needs.
// What to do appears on the glass of the display being surveyed; every other external display
// says "Not this one".

import Foundation
import IOKit.hid

// MARK: - Apps that would read the touchscreens too

struct RunningApp {
    let name: String
    let pid: pid_t
    let path: String
    var text: String { "\(name) (pid \(pid), \(path))" }
}

func conflictingApps() -> [RunningApp] {
    var pids = [pid_t](repeating: 0, count: 16384)
    let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    guard count > 0 else { return [] }
    var found: [RunningApp] = []
    for pid in pids.prefix(min(count, pids.count)) where pid > 0 {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
        let path = String(cString: buffer)
        if let name = conflictingAppName(path: path) { found.append(RunningApp(name: name, pid: pid, path: path)) }
    }
    return found
}

// MARK: - The survey

final class Survey {
    enum Answer { case next, stop }

    /// Every connected touchscreen. All are listened to, so a touch on the wrong one can be named.
    let touchscreens: [ProbeTouchscreen]
    /// The one surveyed.
    let ts: ProbeTouchscreen
    let selection: TakeSelection
    let stepTimeout: Double
    let fileURL: URL
    let recorder: Recorder
    let reader = LineReader()
    let board = Board()
    var plan: BoardPlan
    var file: SurveyFile
    var foundModes: [Int: Int] = [:]
    var currentModes: [Int: Int] = [:]
    var changedModes: Set<Int> = []
    var pastSwitchStep: Set<Int> = []
    /// While a stretch of takes wants the touchscreen held. A failed exclusive open is tried once
    /// per stretch, not before every take.
    var wantHeld = false
    var lastTakeID: String?
    var lastTakeNumber: Int?
    /// The take being recorded, and where in the file its earlier attempt is kept, if it has one.
    var inProgress: (take: ActiveTake, spec: TakeSpec, kept: Int?)?
    /// Whether windows are on the glass in this run: AppKit started, and the target can be drawn on.
    var windowsShown = false
    var released = false

    init(touchscreens: [ProbeTouchscreen], chosen: ProbeTouchscreen, reason: ChoiceReason, list: ListData,
         options: SurveyOptions, outDir: URL) {
        self.touchscreens = touchscreens
        ts = chosen
        selection = options.selection
        stepTimeout = options.stepTimeout
        recorder = Recorder(stepTimeout: options.stepTimeout)
        plan = BoardPlan(target: nil, displays: list.displays)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        fileURL = outDir.appendingPathComponent(surveyFileName(stamp: stamp.string(from: Date()), selection: options.selection))
        file = SurveyFile(
            format: "tactile-probe survey", formatVersion: 1, environment: list.environment,
            settings: SurveySettings(stepTimeoutSeconds: options.stepTimeout, takeLimitSeconds: takeLimitSeconds,
                                     liftQuietSeconds: liftQuietSeconds, quietWithContactsDownSeconds: quietWithContactsDownSeconds,
                                     arguments: options.arguments, takesSelected: options.selection.numbers),
            list: list, conflictingApps: [],
            touchscreens: touchscreens.map {
                let isChosen = $0 === chosen
                return TouchscreenSurvey(number: $0.number, locationID: hexLocation($0.locationID), name: $0.name,
                                         identifiedBy: isChosen ? reason.identifiedBy : IdentifiedBy.notChosen,
                                         status: isChosen ? "not reached" : SectionStatus.notChosen, display: nil,
                                         inputModeFound: nil, inputModeFoundName: nil, actions: [], takes: [])
            },
            restore: [], completed: false, interrupted: false,
            endedBecause: runEnding(.stillRunning, selection: options.selection).endedBecause)
    }

    private var slot: Int { ts.number - 1 }

    // MARK: Saving

    func save() {
        do {
            try encodeSurvey(file).write(to: fileURL, options: .atomic)
        } catch {
            warn("Could not write \(fileURL.path): \(error.localizedDescription)")
        }
    }

    private func record(_ action: ActionRecord, into target: ProbeTouchscreen?) {
        if let target { file.touchscreens[target.number - 1].actions.append(action) } else { file.restore.append(action) }
    }

    // MARK: Listening, exclusive access and Input Mode

    private func listen(_ iface: ProbeInterface) {
        IOHIDDeviceRegisterInputReportWithTimeStampCallback(iface.device, iface.buffer, iface.bufferSize, reportCallback,
                                                            Unmanaged.passUnretained(iface).toOpaque())
        if !iface.scheduled {
            IOHIDDeviceScheduleWithRunLoop(iface.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            iface.scheduled = true
        }
    }

    private func openShared(_ iface: ProbeInterface) -> IOReturn {
        let result = IOHIDDeviceOpen(iface.device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            iface.openState = .shared
            listen(iface)
        }
        return result
    }

    private var isHeld: Bool { ts.interfaces.contains { $0.openState == .exclusive } }

    /// Holds the touchscreen interface and its sibling mouse interface exclusively. An IOHIDDevice
    /// holds one open at a time, so the shared open is closed first and the callback registered again.
    private func openExclusive(take: String) {
        for iface in [ts.touch, ts.mouse].compactMap({ $0 }) where iface.openState != .exclusive {
            if iface.openState == .shared {
                IOHIDDeviceClose(iface.device, IOOptionBits(kIOHIDOptionsTypeNone))
                iface.openState = .closed
            }
            let result = IOHIDDeviceOpen(iface.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            var note: String?
            if result == kIOReturnSuccess {
                iface.openState = .exclusive
                listen(iface)
            } else {
                let back = openShared(iface)
                note = "the exclusive open failed; listening in shared mode again (IOReturn \(hex(back)))"
            }
            record(ActionRecord(kind: "exclusive open", touchscreen: hexLocation(ts.locationID), interface: iface.key, take: take,
                                ioReturn: hex(result), ok: result == kIOReturnSuccess, value: nil, readBack: nil,
                                featureReport: nil, readBackTrusted: nil, note: note), into: ts)
            say(holdingLine(interface: iface.key, ok: result == kIOReturnSuccess, ioReturn: hex(result)))
        }
    }

    private func closeExclusive(_ target: ProbeTouchscreen, take: String?, reopenShared: Bool, log: Bool = true) {
        for iface in target.interfaces where iface.openState == .exclusive {
            let result = IOHIDDeviceClose(iface.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            iface.openState = .closed
            let into: ProbeTouchscreen? = log ? target : nil
            record(ActionRecord(kind: "exclusive close", touchscreen: hexLocation(target.locationID), interface: iface.key, take: take,
                                ioReturn: hex(result), ok: result == kIOReturnSuccess, value: nil, readBack: nil,
                                featureReport: nil, readBackTrusted: nil, note: nil), into: into)
            say("  Released the \(iface.key) interface back to macOS (IOReturn \(hex(result))).")
            if reopenShared {
                let back = openShared(iface)
                record(ActionRecord(kind: "shared reopen", touchscreen: hexLocation(target.locationID), interface: iface.key, take: take,
                                    ioReturn: hex(back), ok: back == kIOReturnSuccess, value: nil, readBack: nil,
                                    featureReport: nil, readBackTrusted: nil, note: nil), into: into)
            }
        }
    }

    /// The whole Device Configuration report as the panel returns it, and whether it is a real answer.
    private func inputModeReport(_ target: ProbeTouchscreen) -> (hex: String?, trusted: Bool?) {
        guard let touch = target.touch,
              let id = touch.descriptor?.fields.first(where: { $0.type == .feature && $0.usage == Usages.inputMode })?.reportID
        else { return (nil, nil) }
        let bytes = withOpenInterface(touch) { readFeatureReport(touch, id: id) }.bytes
        return (bytes.map(hexString), featureReportLooksValid(touch, id: id, bytes: bytes))
    }

    private func readBackText(_ back: Int?, trusted: Bool?) -> String {
        let value = back.map { "\($0) (\(describeMode($0)))" } ?? "nothing"
        if trusted == false {
            return "reads back \(value), but that is IOKit's cached value: the panel's answer is malformed, so its real mode cannot be read"
        }
        return "reads back \(value)"
    }

    private func switchToMultiTouch(take: String) {
        pastSwitchStep.insert(ts.locationID)
        guard let touch = ts.touch, let element = ts.inputModeElement else {
            say("  This touchscreen has no Input Mode setting, so there is nothing to switch.")
            record(ActionRecord(kind: "input mode write skipped", touchscreen: hexLocation(ts.locationID), interface: ts.touch?.key ?? "none",
                                take: take, ioReturn: "none", ok: true, value: nil, readBack: nil, featureReport: nil, readBackTrusted: nil,
                                note: "no Input Mode feature: nothing to switch"), into: ts)
            return
        }
        guard let found = foundModes[ts.locationID] else {
            say("  Could not read this touchscreen's Input Mode, so it is left as it is.")
            record(ActionRecord(kind: "input mode write skipped", touchscreen: hexLocation(ts.locationID), interface: touch.key,
                                take: take, ioReturn: "none", ok: false, value: nil, readBack: nil, featureReport: nil, readBackTrusted: nil,
                                note: "the current Input Mode could not be read, so it was not changed"), into: ts)
            return
        }
        if found == 2 {
            say("  Already in multi-touch mode; nothing to switch.")
            let raw = inputModeReport(ts)
            record(ActionRecord(kind: "input mode write skipped", touchscreen: hexLocation(ts.locationID), interface: touch.key,
                                take: take, ioReturn: "none", ok: true, value: 2, readBack: 2, featureReport: raw.hex,
                                readBackTrusted: raw.trusted, note: "already in multi-touch as found"), into: ts)
            return
        }
        changedModes.insert(ts.locationID)
        let (result, back) = withOpenInterface(touch) { () -> (IOReturn, Int?) in
            let written = writeFeature(touch.device, element, 2)
            return (written, readFeature(touch.device, element).value)
        }
        currentModes[ts.locationID] = back
        let raw = inputModeReport(ts)
        record(ActionRecord(kind: "input mode write", touchscreen: hexLocation(ts.locationID), interface: touch.key, take: take,
                            ioReturn: hex(result), ok: result == kIOReturnSuccess && (raw.trusted == false || back == 2), value: 2, readBack: back,
                            featureReport: raw.hex, readBackTrusted: raw.trusted, note: nil), into: ts)
        say("  Switched to multi-touch: write IOReturn \(hex(result)), \(readBackText(back, trusted: raw.trusted)).")
    }

    private func restoreMode(take: String?, into target: ProbeTouchscreen?) {
        guard changedModes.contains(ts.locationID), let found = foundModes[ts.locationID],
              let touch = ts.touch, let element = ts.inputModeElement else { return }
        let (result, back) = withOpenInterface(touch) { () -> (IOReturn, Int?) in
            let written = writeFeature(touch.device, element, found)
            return (written, readFeature(touch.device, element).value)
        }
        currentModes[ts.locationID] = back
        if result == kIOReturnSuccess, back == found { changedModes.remove(ts.locationID) }
        let raw = inputModeReport(ts)
        record(ActionRecord(kind: "input mode restore", touchscreen: hexLocation(ts.locationID), interface: touch.key, take: take,
                            ioReturn: hex(result), ok: result == kIOReturnSuccess && (raw.trusted == false || back == found), value: found, readBack: back,
                            featureReport: raw.hex, readBackTrusted: raw.trusted, note: nil), into: target)
        say("  Put \(ts.product ?? "the touchscreen") back to \(describeMode(found)): write IOReturn \(hex(result)), \(readBackText(back, trusted: raw.trusted)).")
    }

    /// Puts everything back. Safe to call more than once.
    func releaseAll() {
        guard !released else { return }
        released = true
        activeRecorder = nil
        for t in touchscreens { closeExclusive(t, take: nil, reopenShared: false, log: false) }
        restoreMode(take: nil, into: nil)
        for t in touchscreens {
            for iface in t.interfaces where iface.openState != .closed {
                IOHIDDeviceClose(iface.device, IOOptionBits(iface.openState == .exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone))
                iface.openState = .closed
            }
        }
    }

    /// Brings the touchscreen into the state a take needs: switched to multi-touch once (it is
    /// never switched back mid-run: takes run in order, and only take 1 needs it as found), held
    /// for the takes that need it, released for those that don't.
    private func prepare(for spec: TakeSpec) {
        if spec.state >= .multiTouch, !pastSwitchStep.contains(ts.locationID) {
            say("")
            switchToMultiTouch(take: spec.id)
        }
        if spec.state == .exclusive, !wantHeld {
            say("")
            wantHeld = true
            openExclusive(take: spec.id)
        }
        if spec.state < .exclusive, wantHeld {
            say("")
            wantHeld = false
            closeExclusive(ts, take: lastTakeID, reopenShared: true)
        }
    }

    // MARK: The glass

    private var otherTouchscreenName: String? {
        let others = touchscreens.filter { $0 !== ts }
        return others.count == 1 ? others[0].name : nil
    }

    private func otherName(_ take: ActiveTake) -> String? {
        let names = touchscreens.filter { take.otherOwners.contains($0.locationID) }.map(\.name)
        return names.isEmpty ? otherTouchscreenName : names.joined(separator: " and ")
    }

    private func showOnBoard(_ phase: BoardPhase, spec: TakeSpec, position: Int, count: Int, warning: String? = nil) {
        let screen = instructionScreen(take: spec, position: position, of: count, phase: phase, knowsDisplay: plan.knowsTheDisplay,
                                       touchscreenName: ts.name, warning: warning)
        let windows = boardWindows(plan: plan, instruction: screen)
        board.show(windows.contents, catchingClicks: windows.catchingClicks)
    }

    // MARK: Questions

    private func askNext(isLast: Bool) -> Answer? {
        reader.discardTypedAhead()
        say(isLast ? "  Enter to finish, r to redo it: " : "  Enter for the next take, r to redo it, s to stop here: ", terminator: "")
        guard let line = reader.readLine() else {
            say("")
            return .next
        }
        if !reader.isTerminal { say("") }
        switch line.lowercased() {
        case "r": return nil
        case "s": return isLast ? .next : .stop
        default: return .next
        }
    }

    /// Asks which display the touchscreen is built into, with each external display showing its
    /// number. Only when neither --display nor Tactile's pairing said.
    private func askDisplay() -> DisplayAnswer {
        let displays = file.list.displays
        let choices = displayQuestionChoices(displays)
        guard !choices.isEmpty else { return DisplayAnswer(answer: "", displayID: nil, name: nil, choices: [], source: .question) }
        var numbers: [UInt32: BoardContent] = [:]
        for c in choices { numbers[c.displayID] = .number(c.number, name: c.name ?? "display \(c.displayID)") }
        board.show(numbers, catchingClicks: Set(numbers.keys))
        say("")
        say("Which display is \(ts.name) built into?\(AppKitHost.started ? " Each external display now shows its number." : "")")
        for c in choices {
            guard let d = displays.first(where: { $0.displayID == c.displayID }) else { continue }
            let pixels = d.pixelSize.map { "\($0.width) × \($0.height) pixels" } ?? "unknown resolution"
            say(String(format: "  %d  %@: %@", c.number, d.name ?? "display \(d.displayID)", pixels))
        }
        for _ in 0..<3 {
            reader.discardTypedAhead()
            say("Type its number (the display ID) and press Enter (just Enter if you are not sure): ", terminator: "")
            guard let line = reader.readLine() else { break }
            if !reader.isTerminal { say("") }
            if line.isEmpty { break }
            if let n = Int(line), let c = choices.first(where: { $0.number == n }) {
                say("Noted: \(c.name ?? "display \(c.displayID)").")
                return DisplayAnswer(answer: line, displayID: c.displayID, name: c.name, choices: choices, source: .question)
            }
            say("Please type one of \(choices.map { String($0.number) }.joined(separator: ", ")), or just press Enter.")
        }
        say("Noted: not sure. The instructions will appear on every external display.")
        return DisplayAnswer(answer: "", displayID: nil, name: nil, choices: choices, source: .question)
    }

    // MARK: One take

    /// Puts an attempt into the file: in place of this take's earlier attempt when
    /// `newAttemptReplaces` says so, else not at all. Returns where the take's entry is now, and
    /// whether the new attempt went in.
    private func keep(_ take: Take, earlierAt kept: Int?) -> (index: Int, keptNew: Bool) {
        let earlier = kept.map { file.touchscreens[slot].takes[$0] }
        if let kept, !newAttemptReplaces(earlier: earlier, with: take) { return (kept, false) }
        if let kept {
            file.touchscreens[slot].takes[kept] = take
            return (kept, true)
        }
        file.touchscreens[slot].takes.append(take)
        return (file.touchscreens[slot].takes.count - 1, true)
    }

    /// Runs one take, offering a redo, and stores it. A redo replaces the earlier attempt only
    /// once it has recorded something, so a good take is never lost to a redo that sees no touch
    /// or is stopped.
    private func performTake(_ spec: TakeSpec, position: Int, count: Int) -> Answer {
        var attempt = 0
        var kept: Int?
        while true {
            attempt += 1
            say("")
            say("--- Take \(spec.number) of \(Takes.count) · \(spec.title)\(attempt > 1 ? " (again)" : "") · \(position) of \(count) in this run ---")
            say("  \(spec.prompt)")
            if let note = spec.note { say("  \(note)") }
            showOnBoard(.waiting(secondsLeft: Int(stepTimeout.rounded(.up)), fraction: 1), spec: spec, position: position, count: count)
            recorder.drain()
            reader.discardTypedAhead()
            say(waitingLine(stepTimeout: stepTimeout, target: plan.target, product: ts.product, windowsShown: windowsShown))
            let active = ActiveTake(spec: spec, number: spec.number, attempt: attempt, mode: modeLabel,
                                    inputMode: currentModes[ts.locationID],
                                    exclusiveKeys: ts.interfaces.filter { $0.openState == .exclusive }.map(\.key), candidates: [ts])
            inProgress = (active, spec, kept)
            lastTakeNumber = spec.number
            var warned = false
            let endReason = recorder.run(active) { [self] take in
                let now = Clock.now()
                let phase: BoardPhase
                if let start = take.startNs {
                    phase = .recording(seconds: (Clock.seconds(start, now) * 10).rounded(.down) / 10)
                } else {
                    // The bar moves in steps of 1/200, so the window is redrawn a few times a
                    // second rather than on every tick while reports arrive.
                    let left = max(0, stepTimeout - Clock.seconds(take.promptNs, now))
                    phase = .waiting(secondsLeft: Int(left.rounded(.up)), fraction: (left / stepTimeout * 200).rounded(.up) / 200)
                }
                let warning = wrongScreenWarning(otherReports: take.otherReports, started: take.startNs != nil,
                                                 otherName: otherName(take), knowsDisplay: plan.knowsTheDisplay, product: ts.product)
                if warning != nil, !warned {
                    warned = true
                    say("  That touch came from the other touchscreen\(otherName(take).map { " (\($0))" } ?? ""), not \(ts.product ?? "this one"): touch only \(plan.target?.name ?? ts.product ?? "the right one").")
                }
                showOnBoard(phase, spec: spec, position: position, count: count, warning: warning)
            }
            inProgress = nil
            let other = otherName(active)
            let take = finishTake(active, endReason: endReason, interrupted: false, stepTimeout: stepTimeout, isCorner: spec.isCorner,
                                  otherTouchscreen: other)
            say("  \(take.summary)")
            var verdict = glassVerdict(take, otherTouchscreen: other)
            let placed = keep(take, earlierAt: kept)
            kept = placed.index
            if !placed.keptNew {
                say("  The earlier try of this take, which recorded, stays in the file.")
                verdict = GlassVerdict(text: verdict.text + " The earlier try is kept.", good: false)
            }
            file.touchscreens[slot].status = "in progress"
            save()
            lastTakeID = spec.id
            showOnBoard(.result(verdict, isLast: position == count), spec: spec, position: position, count: count)
            if let answer = askNext(isLast: position == count) { return answer }
        }
    }

    private var modeLabel: String {
        if isHeld { return "exclusive" }
        if pastSwitchStep.contains(ts.locationID), currentModes[ts.locationID] == 2 { return "multi-touch" }
        return "as-found"
    }

    // MARK: Interruption

    func interrupt(signal sig: Int32) {
        var duringTake = false
        if let (active, spec, kept) = inProgress {
            duringTake = true
            inProgress = nil
            recorder.active = nil
            if active.startNs != nil {
                let take = finishTake(active, endReason: nil, interrupted: true, stepTimeout: stepTimeout, isCorner: spec.isCorner,
                                      otherTouchscreen: otherName(active))
                _ = keep(take, earlierAt: kept)
            }
        }
        if file.touchscreens[slot].status == "in progress" { file.touchscreens[slot].status = "interrupted" }
        releaseAll()
        board.closeAll()
        let end = runEnding(.signal(sig, take: lastTakeNumber, duringTake: duringTake), selection: selection)
        file.interrupted = true
        file.completed = end.completed
        file.endedBecause = end.endedBecause
        save()
        say("Saved what was recorded so far to \(fileURL.path)")
    }

    // MARK: The whole run

    func run(display: DisplayChoiceResult, displayArgument: String?) -> Int32 {
        let takes = selection.takes
        say("Tactile probe survey (\(toolName) \(toolVersion))")
        say("Touchscreen: \(ts.name), USB \(usbID(ts.vendorID, ts.productID)) (\(file.touchscreens[slot].identifiedBy)).")
        say("Takes: \(selection.text): " + takes.map { "\($0.number) \($0.title)" }.joined(separator: "; ") + ".")
        say("Saving to: \(fileURL.path)")

        // Which display shows the instructions.
        switch display {
        case .chosen(let d, let source):
            let from = source == .argument ? "from --display" : "Tactile's pairing, from its state file"
            say("Instructions: on \(d.name ?? "display \(d.displayID)") (display \(d.displayID)), \(from).")
            file.touchscreens[slot].display = DisplayAnswer(answer: source == .argument ? (displayArgument ?? "") : "", displayID: d.displayID,
                                                            name: d.name, choices: [], source: source)
        case .notKnown(let why):
            say("Instructions: which display it is on is not known (\(why)).")
            file.touchscreens[slot].display = askDisplay()
        case .badArgument:
            return 64
        }
        let answer = file.touchscreens[slot].display
        let target = file.list.displays.first { $0.displayID == answer?.displayID }
        let drawable = AppKitHost.started
            ? Set(file.list.displays.filter { screen(for: $0.displayID) != nil }.map(\.displayID)) : nil
        plan = BoardPlan(target: target, displays: file.list.displays, drawable: drawable)
        windowsShown = AppKitHost.started && !plan.targetCannotBeDrawnOn
        if !AppKitHost.started {
            say("Nothing is shown on the glass (--no-windows): each take is described here, in the terminal.")
        } else if plan.targetCannotBeDrawnOn {
            for line in noScreenNote(displayName: target?.name ?? "That display") { say(line) }
        } else if plan.knowsTheDisplay {
            say("The display \(plan.target?.name ?? "") shows each take, in large type, inside a green frame. Every other external display says \"Not this one\".")
        } else {
            say("Every external display shows each take. Touch only \(ts.product ?? "the touchscreen being surveyed").")
        }
        save()

        say("")
        for line in surveyIntroduction(stepTimeout: stepTimeout, windows: windowsShown) { say(line) }
        guard let first = takes.first else { return 64 }
        showOnBoard(.getReady, spec: first, position: 1, count: takes.count)
        say("")
        say("Press Enter to start: ", terminator: "")
        _ = reader.readLine()
        if !reader.isTerminal { say("") }

        // Listen on every interface of every touchscreen (the others only to notice a touch on the
        // wrong one), and note the surveyed one's Input Mode as found.
        activeRecorder = recorder
        for t in touchscreens {
            for iface in t.interfaces {
                let result = openShared(iface)
                record(ActionRecord(kind: "shared open", touchscreen: hexLocation(t.locationID), interface: iface.key, take: nil,
                                    ioReturn: hex(result), ok: result == kIOReturnSuccess, value: nil, readBack: nil,
                                    featureReport: nil, readBackTrusted: nil, note: nil), into: t)
                if result != kIOReturnSuccess { say("Note: could not listen to the \(iface.key) interface of \(t.name) (IOReturn \(hex(result))).") }
            }
        }
        if let touch = ts.touch, let element = ts.inputModeElement {
            let read = withOpenInterface(touch) { readFeature(touch.device, element) }
            let raw = inputModeReport(ts)
            file.touchscreens[slot].inputModeFoundRaw = raw.hex
            file.touchscreens[slot].inputModeFoundTrusted = raw.trusted
            if let value = read.value {
                foundModes[ts.locationID] = value
                currentModes[ts.locationID] = value
                file.touchscreens[slot].inputModeFound = value
                file.touchscreens[slot].inputModeFoundName = describeMode(value)
                if raw.trusted == false {
                    say("Note: \(ts.name) cannot report its Input Mode (its answer \(raw.hex ?? "") is malformed). IOKit says")
                    say("\(value) (\(describeMode(value))); the survey will put that value back at the end.")
                }
            }
        }
        save()

        var stopped = false
        for (index, spec) in takes.enumerated() {
            prepare(for: spec)
            if performTake(spec, position: index + 1, count: takes.count) == .stop {
                stopped = true
                break
            }
        }
        closeExclusive(ts, take: lastTakeID, reopenShared: true)
        wantHeld = false
        restoreMode(take: nil, into: ts)
        file.touchscreens[slot].status = stopped ? "skipped by the person" : "done"
        save()

        releaseAll()
        let end = runEnding(stopped ? .stoppedByPerson(afterTake: lastTakeNumber ?? 0) : .finished, selection: selection)
        file.completed = end.completed
        file.endedBecause = end.endedBecause
        save()
        showOnBoard(.finished, spec: takes[0], position: takes.count, count: takes.count)
        pumpEvents(1.5)
        board.closeAll()
        say("")
        say(stopped ? "Stopped. What was recorded is saved in:" : "All done. Thank you. The survey is saved in:")
        say("  \(fileURL.path)")
        return 0
    }
}
