// Listening to every HID interface of every touchscreen, and recording "takes": one prompted
// action each, from the first report after the prompt until every contact has lifted.

import CoreGraphics
import Foundation
import IOKit.hid

let takeLimitSeconds = 15.0
let liftQuietSeconds = 0.7
let quietWithContactsDownSeconds = 3.0

// MARK: - Decoding one report

struct DecodedSlot {
    let slot: Int
    let id: Int?
    let tip: Bool
    let carriesData: Bool
    let record: FingerRecord
}

struct DecodedReport {
    let layout: ReportLayout?
    let contactCount: Int?
    let scanTime: Int?
    let slots: [DecodedSlot]
    let pointer: PointerReport?
}

private func round5(_ v: Double?) -> Double? { v.map { ($0 * 100_000).rounded() / 100_000 } }

func decodeReport(_ iface: ProbeInterface, reportID: Int, bytes: [UInt8]) -> DecodedReport {
    guard let d = iface.descriptor, let layout = iface.layouts[reportID] else {
        return DecodedReport(layout: nil, contactCount: nil, scanTime: nil, slots: [], pointer: nil)
    }
    // The buffer starts with the report ID when the interface uses report IDs.
    let data = d.usesReportIDs && bytes.first == UInt8(truncatingIfNeeded: reportID) ? Array(bytes.dropFirst()) : bytes
    func int(_ f: HIDField?) -> Int? { f.flatMap { $0.value(in: data) }.map { Int($0) } }

    let contactCount = int(layout.contactCount)
    var slots: [DecodedSlot] = []
    for (index, slot) in layout.slots.enumerated() {
        let rawX = slot.x.flatMap { $0.value(in: data) }
        let rawY = slot.y.flatMap { $0.value(in: data) }
        let tipValue = int(slot.tip)
        let id = int(slot.contactID)
        let inRange = int(slot.inRange)
        let record = FingerRecord(
            slot: index, id: id, tip: tipValue.map { $0 != 0 },
            x: round5(rawX.flatMap { slot.x?.normalised($0) }), y: round5(rawY.flatMap { slot.y?.normalised($0) }),
            rawX: rawX.map { Int($0) }, rawY: rawY.map { Int($0) }, inRange: inRange.map { $0 != 0 },
            confidence: int(slot.confidence), width: int(slot.width), height: int(slot.height),
            pressure: int(slot.pressure), azimuth: int(slot.azimuth))
        let values = [tipValue, id, rawX.map { Int($0) }, rawY.map { Int($0) }, inRange, record.confidence, record.width,
                      record.height, record.pressure, record.azimuth]
        let carries = values.contains { ($0 ?? 0) != 0 } || index < (contactCount ?? 0)
        slots.append(DecodedSlot(slot: index, id: id, tip: (tipValue ?? 0) != 0, carriesData: carries, record: record))
    }

    var pointer: PointerReport?
    if layout.kind == .pointer || layout.pointerX != nil || !layout.buttons.isEmpty {
        var buttons: Int?
        if !layout.buttons.isEmpty {
            var mask = 0
            for f in layout.buttons where (f.value(in: data) ?? 0) != 0 {
                let bit = Int(f.usage.id) - 1
                if bit >= 0, bit < 62 { mask |= 1 << bit }
            }
            buttons = mask
        }
        let rawX = layout.pointerX.flatMap { $0.value(in: data) }
        let rawY = layout.pointerY.flatMap { $0.value(in: data) }
        let absoluteX = layout.pointerX.map { !$0.relative } ?? false
        let absoluteY = layout.pointerY.map { !$0.relative } ?? false
        pointer = PointerReport(
            buttons: buttons,
            x: absoluteX ? round5(rawX.flatMap { layout.pointerX?.normalised($0) }) : nil,
            y: absoluteY ? round5(rawY.flatMap { layout.pointerY?.normalised($0) }) : nil,
            rawX: absoluteX ? rawX.map { Int($0) } : nil, rawY: absoluteY ? rawY.map { Int($0) } : nil,
            dx: absoluteX ? nil : rawX.map { Int($0) }, dy: absoluteY ? nil : rawY.map { Int($0) },
            wheel: int(layout.wheel), tip: int(layout.tip).map { $0 != 0 }, inRange: int(layout.inRange).map { $0 != 0 })
    }
    return DecodedReport(layout: layout, contactCount: contactCount, scanTime: int(layout.scanTime), slots: slots, pointer: pointer)
}

// MARK: - Following contacts across reports

/// Follows contacts on one touch interface. A "frame" is one scan of the panel; a panel in hybrid
/// mode spreads a frame over several reports, and only the first carries the contact count
/// (the later ones report 0), as Touch Up's reader, TactileCore's HIDInterpreter, handled it before
/// 0.2.0 removed it.
final class ContactTracker {
    let slotCount: Int
    private var expected = 0
    private var received = 0
    private var frameDown: [Int: Int] = [:]
    private var frameUp: Set<Int> = []
    private(set) var down: [Int: Int] = [:]
    var idsSeen = Set<Int>()
    var maxDown = 0
    var maxContactCount: Int?
    var slotChanges = 0
    var liftedWithTipUp = 0
    var liftedWithout = 0
    var hybridObserved = false
    var splitFrames = 0
    var lastReportHadNoContacts: Bool?
    var reports = 0

    init(slotCount: Int) { self.slotCount = slotCount }

    var midFrame: Bool { expected > received && received > 0 }
    var anyDown: Bool { !down.isEmpty || !frameDown.isEmpty || midFrame }

    func process(_ r: DecodedReport) {
        reports += 1
        var validSlots = slotCount
        var continuation = false
        if let cc = r.contactCount {
            maxContactCount = max(maxContactCount ?? 0, cc)
            if cc > 0 {
                if expected > received { finishFrame() }
                expected = cc
                received = 0
                if cc > slotCount { hybridObserved = true }
            } else if midFrame {
                continuation = true
                hybridObserved = true
            } else {
                expected = 0
                received = 0
            }
            validSlots = min(slotCount, max(expected - received, 0))
        }
        let offset = received
        var tips = 0
        for s in r.slots where s.slot < validSlots {
            // Without a Contact Identifier field, the slot is the only identity there is.
            let id = s.id ?? s.slot
            if s.tip {
                tips += 1
                let position = offset + s.slot
                if let previous = down[id], previous != position { slotChanges += 1 }
                frameDown[id] = position
                idsSeen.insert(id)
            } else {
                frameUp.insert(id)
            }
        }
        lastReportHadNoContacts = tips == 0
        if continuation { splitFrames += 1 }
        if r.contactCount != nil {
            received += validSlots
            if received >= expected { finishFrame() }
        } else {
            finishFrame()
        }
    }

    private func finishFrame() {
        for id in down.keys where frameDown[id] == nil {
            if frameUp.contains(id) { liftedWithTipUp += 1 } else { liftedWithout += 1 }
        }
        down = frameDown
        maxDown = max(maxDown, down.count)
        frameDown = [:]
        frameUp = []
        expected = 0
        received = 0
    }
}

final class PointerState {
    var buttons = 0
    var buttonsSeen = 0
    var released = false
    var last: (Int?, Int?)?
    var reports = 0

    /// True when this report shows a touch in progress: a button held, or the position moving.
    func process(_ p: PointerReport) -> Bool {
        reports += 1
        let now = p.buttons ?? 0
        if buttons != 0, now == 0 { released = true }
        buttons = now
        buttonsSeen |= now
        let position = (p.rawX ?? p.dx, p.rawY ?? p.dy)
        var moved = false
        if let last { moved = last.0 != position.0 || last.1 != position.1 }
        if p.dx.map({ $0 != 0 }) ?? false || p.dy.map({ $0 != 0 }) ?? false { moved = true }
        last = position
        return now != 0 || moved
    }
}

// MARK: - A take in progress

final class ActiveTake {
    let spec: TakeSpec
    let number: Int
    let attempt: Int
    var mode: String
    var inputMode: Int?
    let exclusiveKeys: [String]
    let candidates: [ProbeTouchscreen]
    let promptNs: UInt64
    var device: ProbeTouchscreen?
    var startNs: UInt64?
    var lastReportNs: UInt64?
    var lastActiveNs: UInt64?
    var reports: [RecordedReport] = []
    var counts: [String: Int] = [:]
    var firstLast: [String: (first: UInt64, last: UInt64)] = [:]
    var otherReports = 0
    /// The location IDs of the other touchscreens that sent reports during this take.
    var otherOwners = Set<Int>()
    var stale = 0
    var interpretedSeen = false
    var trackers: [String: ContactTracker] = [:]
    var pointers: [String: PointerState] = [:]
    var touchTapPoints: [(Double, Double)] = []
    var mouseTapPoints: [(Double, Double)] = []
    var pointerSamples: [[Double]] = []
    var pointerStart: CGPoint?
    var pointerLast: CGPoint?

    init(spec: TakeSpec, number: Int, attempt: Int, mode: String, inputMode: Int?, exclusiveKeys: [String], candidates: [ProbeTouchscreen]) {
        self.spec = spec
        self.number = number
        self.attempt = attempt
        self.mode = mode
        self.inputMode = inputMode
        self.exclusiveKeys = exclusiveKeys
        self.candidates = candidates
        promptNs = Clock.now()
    }

    var anyDown: Bool {
        trackers.values.contains { $0.anyDown } || pointers.values.contains { $0.buttons != 0 }
    }
}

func currentPointer() -> CGPoint? { CGEvent(source: nil)?.location }

final class Recorder {
    var active: ActiveTake?
    let stepTimeout: Double

    init(stepTimeout: Double) { self.stepTimeout = stepTimeout }

    func handle(_ iface: ProbeInterface, reportID: Int, bytes: [UInt8], timestamp: UInt64) {
        guard let take = active, let owner = iface.owner else { return }
        let now = Clock.now()
        var ts = timestamp == 0 ? now : Clock.ns(fromMach: timestamp)
        if ts > now + 1_000_000_000 { ts = now } // not on the host clock after all
        if ts < take.promptNs { take.stale += 1; return }
        if take.device == nil {
            guard take.candidates.contains(where: { $0 === owner }) else { noteOther(owner, in: take); return }
            take.device = owner
        }
        guard take.device === owner else { noteOther(owner, in: take); return }
        if take.startNs == nil {
            take.startNs = ts
            take.lastActiveNs = ts
        }
        take.lastReportNs = max(take.lastReportNs ?? ts, ts)
        take.counts[iface.key, default: 0] += 1
        let span = take.firstLast[iface.key]
        take.firstLast[iface.key] = (span?.first ?? ts, ts)

        let decoded = decodeReport(iface, reportID: reportID, bytes: bytes)
        var active = false
        switch decoded.layout?.kind {
        case .touch?:
            take.interpretedSeen = true
            let tracker = take.trackers[iface.key] ?? ContactTracker(slotCount: decoded.slots.count)
            take.trackers[iface.key] = tracker
            tracker.process(decoded)
            active = tracker.anyDown
            if let first = decoded.slots.first(where: { $0.tip }), let x = first.record.x, let y = first.record.y {
                take.touchTapPoints.append((x, y))
            }
        case .pointer?:
            take.interpretedSeen = true
            let state = take.pointers[iface.key] ?? PointerState()
            take.pointers[iface.key] = state
            if let p = decoded.pointer {
                active = state.process(p)
                if (p.buttons ?? 0) != 0, let x = p.x, let y = p.y { take.mouseTapPoints.append((x, y)) }
            }
        default:
            // A report this tool cannot interpret keeps the take going only while nothing it
            // can interpret has arrived.
            active = !take.interpretedSeen
        }
        if active { take.lastActiveNs = ts }

        let isTouch = decoded.layout?.kind == .touch
        take.reports.append(RecordedReport(
            t: ((Clock.seconds(take.startNs ?? ts, ts)) * 1_000_000).rounded() / 1_000_000,
            hostTimeNs: ts, interface: iface.key, reportID: reportID, length: bytes.count, bytes: hexString(bytes),
            contactCount: decoded.contactCount, scanTime: decoded.scanTime,
            fingers: isTouch ? decoded.slots.filter(\.carriesData).map(\.record) : nil,
            pointer: decoded.pointer))
    }

    private func noteOther(_ owner: ProbeTouchscreen, in take: ActiveTake) {
        take.otherReports += 1
        take.otherOwners.insert(owner.locationID)
    }

    /// Runs one take: waits up to the step timeout for the first report, then until the fingers
    /// have lifted. Returns why it ended, or nil when no touch was seen. `onTick` is called about
    /// every 50 ms, for the countdown on the glass.
    func run(_ take: ActiveTake, onTick: (ActiveTake) -> Void = { _ in }) -> String? {
        active = take
        take.pointerStart = currentPointer()
        take.pointerLast = take.pointerStart
        if let p = take.pointerStart { take.pointerSamples.append([0, Double(p.x), Double(p.y)]) }
        defer { active = nil }
        while true {
            onTick(take)
            pumpEvents(0.05)
            let now = Clock.now()
            samplePointer(take, now)
            guard let start = take.startNs else {
                if Clock.seconds(take.promptNs, now) >= stepTimeout { return nil }
                continue
            }
            if Clock.seconds(start, now) >= takeLimitSeconds { return "15 s limit" }
            let down = take.anyDown
            if !down, Clock.seconds(take.lastActiveNs ?? start, now) >= liftQuietSeconds { return "lifted" }
            if down, Clock.seconds(take.lastReportNs ?? start, now) >= quietWithContactsDownSeconds { return "went quiet with contacts down" }
        }
    }

    private func samplePointer(_ take: ActiveTake, _ now: UInt64) {
        guard let p = currentPointer() else { return }
        if let last = take.pointerLast, abs(last.x - p.x) < 0.01, abs(last.y - p.y) < 0.01 { return }
        take.pointerLast = p
        take.pointerSamples.append([(Clock.seconds(take.promptNs, now) * 1000).rounded() / 1000, Double(p.x), Double(p.y)])
    }

    /// Lets queued reports arrive and throws them away, so a take never starts on old input.
    func drain(_ seconds: Double = 0.2) {
        let saved = active
        active = nil
        pumpEvents(seconds)
        active = saved
    }
}

// MARK: - Turning a finished take into the record and a plain summary

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

func finishTake(_ take: ActiveTake, endReason: String?, interrupted: Bool, stepTimeout: Double, isCorner: Bool,
                otherTouchscreen: String?) -> Take {
    let endNs = Clock.now()
    let pointerEnd = currentPointer() ?? take.pointerLast
    var pointer: PointerRecord?
    if let start = take.pointerStart {
        let points = take.pointerSamples.map { CGPoint(x: $0[1], y: $0[2]) } + (pointerEnd.map { [$0] } ?? [])
        let distances = points.map { hypot($0.x - start.x, $0.y - start.y) }
        let maxDistance = Double(distances.max() ?? 0)
        let endDisplay = pointerEnd.flatMap(displayContaining)
        pointer = PointerRecord(
            from: Point(x: Double(start.x), y: Double(start.y)),
            to: pointerEnd.map { Point(x: Double($0.x), y: Double($0.y)) },
            moved: maxDistance > 0.5, maxDistance: (maxDistance * 10).rounded() / 10,
            endDisplayID: endDisplay, endDisplayName: endDisplay.flatMap(displayName), samples: take.pointerSamples)
    }

    let started = take.startNs != nil
    let trackers = take.trackers.values
    let pointers = take.pointers.values
    var facts: TakeFacts?
    if started {
        var rates: [String: Double] = [:]
        for (key, span) in take.firstLast {
            let n = take.counts[key] ?? 0
            let seconds = Clock.seconds(span.first, span.last)
            if n >= 2, seconds > 0 { rates[key] = (Double(n - 1) / seconds * 10).rounded() / 10 }
        }
        let touchSeen = trackers.contains { $0.reports > 0 }
        let tipUp = trackers.map(\.liftedWithTipUp).reduce(0, +)
        let without = trackers.map(\.liftedWithout).reduce(0, +)
        let stillDown = trackers.map { $0.down.count }.reduce(0, +)
        var finalTipUp: String?
        if tipUp + without + stillDown > 0 {
            if without == 0 && stillDown == 0 { finalTipUp = "every contact" }
            else if tipUp == 0 { finalTipUp = "none" }
            else { finalTipUp = "some" }
        }
        let lastTouchKey = take.reports.last(where: { take.trackers[$0.interface] != nil })?.interface
        facts = TakeFacts(
            interfacesReporting: take.counts.keys.sorted(),
            reportRateHz: rates,
            contactIDsSeen: trackers.reduce(Set<Int>()) { $0.union($1.idsSeen) }.sorted(),
            maxContactsDown: trackers.map(\.maxDown).max() ?? 0,
            maxContactCountField: trackers.compactMap(\.maxContactCount).max(),
            fingersChangeSlots: touchSeen ? trackers.contains { $0.slotChanges > 0 } : nil,
            slotChanges: trackers.map(\.slotChanges).reduce(0, +),
            liftedWithTipUpReport: tipUp, liftedWithoutTipUpReport: without, stillDownAtEnd: stillDown,
            finalTipUp: finalTipUp,
            lastTouchReportHadNoContacts: lastTouchKey.flatMap { take.trackers[$0]?.lastReportHadNoContacts },
            hybridObserved: trackers.contains { $0.hybridObserved },
            touchFramesSplitAcrossReports: trackers.map(\.splitFrames).reduce(0, +),
            mouseButtonsSeen: pointers.isEmpty ? nil : pointers.reduce(0) { $0 | $1.buttonsSeen },
            mouseButtonReleased: pointers.isEmpty ? nil : pointers.contains { $0.released })
    }

    var tap: TapMedian?
    if isCorner {
        let touch = median(take.touchTapPoints.map(\.0)).flatMap { x in median(take.touchTapPoints.map(\.1)).map { NormPoint(x: x, y: $0) } }
        let mouse = median(take.mouseTapPoints.map(\.0)).flatMap { x in median(take.mouseTapPoints.map(\.1)).map { NormPoint(x: x, y: $0) } }
        tap = TapMedian(touch: touch, touchSamples: take.touchTapPoints.count, mouse: mouse, mouseSamples: take.mouseTapPoints.count)
    }

    let result = started ? (interrupted ? "interrupted" : "recorded") : (interrupted ? "interrupted" : "no touch seen")
    var record = Take(
        id: take.spec.id, number: take.number, title: take.spec.title, prompt: take.spec.prompt, mode: take.mode,
        inputMode: take.inputMode, exclusiveInterfaces: take.exclusiveKeys, attempt: take.attempt,
        result: result, endReason: interrupted ? "interrupted" : endReason, summary: "",
        promptedAtNs: take.promptNs, startedAtNs: take.startNs, endedAtNs: started ? endNs : nil,
        waitedSeconds: take.startNs.map { (Clock.seconds(take.promptNs, $0) * 1000).rounded() / 1000 },
        durationSeconds: take.startNs.map { (max(0, Clock.seconds($0, endNs)) * 1000).rounded() / 1000 },
        reportSpanSeconds: take.startNs.flatMap { start in take.lastReportNs.map { (max(0, Clock.seconds(start, $0)) * 1000).rounded() / 1000 } },
        reportCounts: take.counts, otherTouchscreenReports: take.otherReports, staleReportsDiscarded: take.stale,
        pointer: pointer, facts: facts, tap: tap, reports: take.reports)
    record.summary = summarize(record, stepTimeout: stepTimeout, isCorner: isCorner, otherTouchscreen: otherTouchscreen)
    return record
}

// MARK: - The C callback IOKit calls for every input report

let reportCallback: IOHIDReportWithTimeStampCallback = { context, result, _, _, reportID, report, length, timestamp in
    guard let context, result == kIOReturnSuccess, length > 0 else { return }
    let iface = Unmanaged<ProbeInterface>.fromOpaque(context).takeUnretainedValue()
    let count = min(Int(length), iface.bufferSize)
    let bytes = Array(UnsafeBufferPointer(start: report, count: count))
    activeRecorder?.handle(iface, reportID: Int(reportID), bytes: bytes, timestamp: timestamp)
}

var activeRecorder: Recorder?
