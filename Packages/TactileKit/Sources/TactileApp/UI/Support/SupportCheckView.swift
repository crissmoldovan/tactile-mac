// The touchscreen check's window content: a header, the four steps down the side with their marks,
// and the step under way: what the device is and Start Check; the touch area with its prompt,
// countdown and Skip; or the verdict, with Done and Send to Tactile's Developer….
//
// It fills the window, whatever size the window took on its display. The header stays at the top
// and each step's row of buttons at the bottom; on a short display the steps and the step's words
// scroll between them.

import SwiftUI
import TactileDevices
import TactileSupport

struct SupportCheckView: View {
    @Bindable var session: SupportCheckSession

    var body: some View {
        let _ = session.revision
        // As large as the window's content, whatever size the window took on its display
        // (`SupportCheckWindowFrame`); the sheet is fitted to it.
        GeometryReader { window in
            let sheet = SupportSendSheet(session: session, room: window.size)
            VStack(alignment: .leading, spacing: 18) {
                header
                    .supportPart(.title)
                if let check = session.check {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView(.vertical) {
                            SupportStepList(check: check, revision: session.revision)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 220)
                        Divider()
                        stepContent(check)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    Label(Wording.supportCantFind, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: window.size.width, height: window.size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $session.isShowingSheet) {
                sheet
            }
            .preference(key: SupportSheetRoom.self, value: sheet.room)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TouchscreenTile(isActive: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Wording.checkThisTouchscreen.replacingOccurrences(of: "…", with: ""))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ check: SupportCheck) -> some View {
        switch check.stage {
        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Wording.identityLines(check.device, check.identity), id: \.self) { line in
                                Text(line)
                            }
                        }
                        Text(Wording.supportIntro)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if session.macOSMayActToo {
                            Label(Wording.supportShared, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Label(Wording.supportLetGo, systemImage: "hand.raised")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                let availability = session.startAvailability
                HStack(alignment: .firstTextBaseline) {
                    if let reason = availability == .available ? session.startRefusal : Wording.supportUnavailable(availability) {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(Wording.startCheck) { session.start() }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                        .disabled(availability != .available)
                }
                .supportPart(.buttons)
            }
        case .taking:
            VStack(spacing: 12) {
                ProgressView()
                Text(Wording.readingTouchscreen)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .touching(let fingers):
            SupportTouchArea(session: session, check: check, fingers: fingers, revision: session.revision)
        case .finished:
            SupportVerdictView(session: session, check: check, revision: session.revision)
        }
    }
}

/// The four steps, each with its plain sentence and its mark.
struct SupportStepList: View {
    let check: SupportCheck
    /// The session's revision: a new one draws it again, as the check, a class, changes inside.
    var revision: Int

    var body: some View {
        let marks = SupportStepMarks(stage: check.stage, steps: check.steps, interrupted: check.wasInterrupted).marks
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SupportStepMarkView(mark: marks[index])
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(Wording.supportStepTitles[index])")
                            .fontWeight(marks[index] == .current ? .semibold : .regular)
                        Text(Wording.supportStepSentence(index, kind: check.device.kind,
                                                         hasTouchInterface: check.device.touchInterface != nil))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 1, let line = Wording.switchesLine(check.switches, kind: check.device.kind) {
                            Text(line)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct SupportStepMarkView: View {
    var mark: SupportStepMark

    var body: some View {
        Group {
            switch mark {
            case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
            case .current: Image(systemName: "circle.inset.filled").foregroundStyle(Color.accentColor)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Step 3 under way: where to touch, what was seen, the time left, and Skip.
struct SupportTouchArea: View {
    let session: SupportCheckSession
    let check: SupportCheck
    let fingers: SupportFingers
    var revision: Int

    var body: some View {
        let step = check.steps.last
        let left = SupportCheck.stepSeconds - (session.now - (step?.startedAt ?? session.now))
        VStack(alignment: .leading, spacing: 12) {
            Text(Wording.touchStepOf(fingers))
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                // Without the hand where there isn't room for it; on a display shorter still, the
                // words are cut at the area's edges, and Skip stays below.
                ViewThatFits(in: .vertical) {
                    prompt(step, hand: true)
                    prompt(step, hand: false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            HStack {
                ProgressView(value: max(0, min(1, left / SupportCheck.stepSeconds)))
                    .frame(width: 160)
                Text(Wording.secondsLeft(left))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Wording.skip) { session.skip() }
            }
            .supportPart(.buttons)
        }
    }

    private func prompt(_ step: SupportTouchStep?, hand: Bool) -> some View {
        VStack(spacing: 14) {
            if hand {
                Image(systemName: fingers == .one ? "hand.point.up.left" : "hand.raised")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            Text(Wording.touchPrompt(fingers))
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(Wording.fingersSeen(step?.mostFingers ?? 0))
                .foregroundStyle(.secondary)
            if session.macOSMayActToo {
                Text(Wording.supportShared)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
    }
}

/// Step 4: the verdict and its sentence; Done, and Send to Tactile's Developer… (a small link when it
/// works fully).
struct SupportVerdictView: View {
    let session: SupportCheckSession
    let check: SupportCheck
    var revision: Int

    var body: some View {
        if let interruption = check.interruption {
            interrupted(interruption)
        } else {
            finished
        }
    }

    /// A check that didn't run its course: no verdict, nothing to send.
    private func interrupted(_ interruption: SupportCheck.Interruption) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.arrow.circlepath")
                            .font(.system(size: 34))
                            .foregroundStyle(.orange)
                        Text(Wording.interruptedTitle)
                            .font(.title.weight(.semibold))
                    }
                    Text(Wording.supportInterruption(interruption))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Wording.tryAgain)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(Wording.supportDone) { session.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .supportPart(.buttons)
        }
    }

    private var finished: some View {
        let verdict = check.verdict
        return VStack(alignment: .leading, spacing: 14) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(verdict))
                            .font(.system(size: 34))
                            .foregroundStyle(colour(verdict))
                        Text(Wording.verdictTitle(verdict))
                            .font(.title.weight(.semibold))
                    }
                    Text(Wording.verdictSentence(check.verdictReason))
                        .fixedSize(horizontal: false, vertical: true)
                    if verdict == .worksFully {
                        Text(Wording.worksFullyThanks)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if verdict == .worksFully {
                    Button(Wording.sendAnyway) { session.showSheet() }
                        .buttonStyle(.link)
                }
                Spacer()
                Button(Wording.supportDone) { session.close() }
                if verdict != .worksFully {
                    Button(Wording.sendToDeveloper) { session.showSheet() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .supportPart(.buttons)
        }
    }

    private func symbol(_ verdict: SupportVerdict) -> String {
        switch verdict {
        case .worksFully: return "checkmark.seal.fill"
        case .worksWithOneFinger: return "hand.point.up.left.fill"
        case .doesNotWork: return "xmark.octagon.fill"
        }
    }

    private func colour(_ verdict: SupportVerdict) -> Color {
        switch verdict {
        case .worksFully: return .green
        case .worksWithOneFinger: return .orange
        case .doesNotWork: return .red
        }
    }
}
