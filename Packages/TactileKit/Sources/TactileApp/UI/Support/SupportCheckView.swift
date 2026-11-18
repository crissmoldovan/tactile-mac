// The touchscreen check's window content: a header, the four steps down the side with their marks,
// and the step under way: what the device is and Start Check; the touch area with its prompt,
// countdown and Skip; or the verdict, with Done and Send to Tactile's Developer….

import SwiftUI
import TactileDevices
import TactileSupport

struct SupportCheckView: View {
    @Bindable var session: SupportCheckSession

    var body: some View {
        let _ = session.revision
        VStack(alignment: .leading, spacing: 18) {
            header
            if let check = session.check {
                HStack(alignment: .top, spacing: 24) {
                    SupportStepList(check: check, revision: session.revision)
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
        .frame(width: SupportCheckWindow.size.width, height: SupportCheckWindow.size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $session.isShowingSheet) {
            SupportSendSheet(session: session)
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
                Text(Wording.helpMeSupport.replacingOccurrences(of: "…", with: ""))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ check: SupportCheck) -> some View {
        switch check.stage {
        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Wording.identityLines(check.device, check.identity), id: \.self) { line in
                        Text(line)
                    }
                }
                Text(Wording.supportIntro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label(Wording.supportLetGo, systemImage: "hand.raised")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
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
                VStack(spacing: 14) {
                    Image(systemName: fingers == .one ? "hand.point.up.left" : "hand.raised")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text(Wording.touchPrompt(fingers))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Wording.fingersSeen(step?.mostFingers ?? 0))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                ProgressView(value: max(0, min(1, left / SupportCheck.stepSeconds)))
                    .frame(width: 160)
                Text(Wording.secondsLeft(left))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Wording.skip) { session.skip() }
            }
        }
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
            Spacer()
            HStack {
                Spacer()
                Button(Wording.supportDone) { session.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }

    private var finished: some View {
        let verdict = check.verdict
        return VStack(alignment: .leading, spacing: 14) {
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
            Spacer()
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
