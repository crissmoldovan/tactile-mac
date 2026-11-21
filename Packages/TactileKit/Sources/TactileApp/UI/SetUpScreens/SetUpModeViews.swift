// What set-up mode's overview draws (see `SetUpModePlan.swift`): on the chosen display, a large
// "Now touch this screen" on the bright backdrop and a card with Back below it; on every other
// candidate display, its card in the middle, over a dimmed backdrop; and the session card, on the
// built-in display or beside the first candidate's card, with its way to the touchscreen check.
// Cards are the only part that acts on a click; the backdrop swallows the rest
// (`SetUpScreen.backdropTakesMouse`).

import SwiftUI
import TactileScreens

// MARK: - The chosen display's backdrop

/// On the bright backdrop of the display chosen, above the middle: the touch glyph, "Now touch
/// this screen", which display it is, and how to touch it.
struct SetUpModeTouchHere: View {
    var card: SetUpModeCard
    var metrics: SetUpMetrics

    var body: some View {
        VStack(spacing: metrics.title * 0.28) {
            TouchGlyphView(color: .controlAccentColor)
                .frame(width: metrics.glyphSize, height: metrics.glyphSize)
                .accessibilityHidden(true)
            Text(Wording.setUpModeTouchHere)
                .font(.system(size: metrics.title, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            VStack(spacing: metrics.body * 0.35) {
                Text(Wording.displayLabel(name: card.name, detail: card.detail))
                    .font(.system(size: metrics.body, weight: .medium))
                Text(Wording.setUpModeTouchHint)
                    .font(.system(size: metrics.body))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - The cards

/// One overview screen's cards: the display's own, the session card, or both side by side.
struct SetUpModeControls: View {
    var overview: SetUpModeScreen
    /// Beside Back on the chosen display (`SetUpScreen.mouseHint`).
    var mouseHint: String
    var scale: CGFloat
    var perform: PerformCommand
    /// The session card's Check This Touchscreen… and Check….
    var check: CheckTouchscreen = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 20 * scale) {
            if let card = overview.card {
                if card.moment == .touchHere {
                    SetUpModeBackCard(
                        touchHere: overview.saysTouchHereInACard ? card : nil, mouseHint: mouseHint, scale: scale,
                        perform: perform)
                } else {
                    SetUpModeCardView(card: card, scale: scale, perform: perform)
                }
            }
            if let session = overview.session {
                SetUpModeSessionView(session: session, scale: scale, perform: perform, check: check)
            }
        }
    }
}

/// A button of the overview, prominent when it is the thing to do.
private struct SetUpModeButtonView: View {
    var button: SetUpModeButton
    var isProminent: Bool
    var scale: CGFloat
    var perform: PerformCommand

    var body: some View {
        let label = SetUpButtonLabel(title: button.title, scale: scale)
        if isProminent {
            Button { perform(button.command) } label: { label }
                .buttonStyle(.borderedProminent)
        } else {
            Button { perform(button.command) } label: { label }
        }
    }
}

/// The chosen display's card, below its message: Back, and how to leave. Beside the session card
/// (`SetUpModeScreen.saysTouchHereInACard`), it carries the message itself, above Back.
struct SetUpModeBackCard: View {
    /// The chosen display's card, when the message goes in this card; nil: it is on the backdrop.
    var touchHere: SetUpModeCard?
    var mouseHint: String
    var scale: CGFloat
    var perform: PerformCommand

    var body: some View {
        SetUpCard(scale: scale) {
            VStack(spacing: 10 * scale) {
                if let card = touchHere {
                    VStack(spacing: 8 * scale) {
                        TouchGlyphView(color: .controlAccentColor)
                            .frame(width: 52 * scale, height: 52 * scale)
                            .accessibilityHidden(true)
                        Text(Wording.setUpModeTouchHere)
                            .font(.system(size: 30 * scale, weight: .bold))
                        Text(Wording.displayLabel(name: card.name, detail: card.detail))
                            .font(.system(size: 15 * scale, weight: .medium))
                        Text(Wording.setUpModeTouchHint)
                            .font(.system(size: 15 * scale))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 380 * scale)
                    .padding(.bottom, 6 * scale)
                }
                HStack(spacing: 14 * scale) {
                    SetUpModeButtonView(button: .back, isProminent: false, scale: scale, perform: perform)
                        .setUpControlSize(scale)
                    Text(Wording.setUpPressEscToLeave)
                        .foregroundStyle(.secondary)
                }
                SetUpMouseHint(text: mouseHint, scale: scale)
            }
        }
    }
}

/// A candidate display's card: its name and detail, what it has, where the mode is, and its
/// buttons. The one just set up in this session is marked.
struct SetUpModeCardView: View {
    var card: SetUpModeCard
    var scale: CGFloat
    var perform: PerformCommand

    private var isWaitingElsewhere: Bool {
        if case .waitingElsewhere = card.moment { return true }
        return false
    }

    var body: some View {
        SetUpCard(scale: scale) {
            VStack(alignment: .leading, spacing: 14 * scale) {
                HStack(alignment: .center, spacing: 14 * scale) {
                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                        .fill(isWaitingElsewhere ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(Color.accentColor.gradient))
                        .frame(width: 46 * scale, height: 46 * scale)
                        .overlay(Image(systemName: "display")
                            .font(.system(size: 22 * scale, weight: .medium))
                            .foregroundStyle(.white))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        Text(card.name)
                            .font(.system(size: 24 * scale, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !card.detail.isEmpty {
                            Text(card.detail)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                stateLine
                if case .waitingElsewhere(let displayName) = card.moment {
                    Label(Wording.setUpModeWaiting(displayName: displayName), systemImage: "hourglass")
                        .font(.system(size: 14 * scale))
                        .foregroundStyle(.secondary)
                }
                if let touched = card.touchedFirst {
                    SetUpModeTouchedLine(text: Wording.setUpModeTouchedFirst(name: touched), size: 15 * scale)
                }
                HStack(spacing: 10 * scale) {
                    Spacer(minLength: 0)
                    ForEach(card.buttons, id: \.self) { button in
                        SetUpModeButtonView(
                            button: button, isProminent: button == card.prominentButton, scale: scale, perform: perform)
                    }
                }
                .setUpControlSize(scale)
            }
            .frame(width: 420 * scale, alignment: .leading)
        }
        .overlay {
            if card.isJustSetUp {
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .strokeBorder(Color.green, lineWidth: 3 * scale)
            }
        }
        .opacity(card.opacity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var stateLine: some View {
        switch card.state {
        case .free:
            Text(card.stateLine)
                .font(.system(size: 16 * scale, weight: .medium))
        case .setUp(_, _, let isJustSetUp, _):
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(card.stateLine)
                    .font(.system(size: 16 * scale, weight: isJustSetUp ? .bold : .medium))
                    .foregroundStyle(Color.green)
                    .fixedSize(horizontal: false, vertical: true)
                if isJustSetUp {
                    Text(Wording.setUpModeJustDone)
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(Capsule().fill(Color.green))
                }
            }
        }
    }
}

/// The session card: what set-up mode is for and how it goes, one line per touchscreen, the latest
/// notice, Back after a touch first, the way to the touchscreen check, and Finish. The check is Check
/// This Touchscreen… beside "Touch not working right?" with one touchscreen, and Check… on each line
/// with several (`SetUpModeSession.checkOffer`): buttons, for the mouse, since touch may not work.
struct SetUpModeSessionView: View {
    var session: SetUpModeSession
    var scale: CGFloat
    var perform: PerformCommand
    /// Leaves set-up mode, then opens the check (`SetUpSupportCheck`).
    var check: CheckTouchscreen = { _ in }

    /// Whether `id` can be checked once set-up mode has let go of it, and no earlier check of it is
    /// still letting go.
    private func availability(_ id: TouchscreenID) -> SupportCheckAvailability {
        (session.checks[id] ?? .notConnected).whileFinishing(SupportChecksFinishing.shared.isFinishing(id))
    }

    var body: some View {
        SetUpCard(scale: scale) {
            VStack(alignment: .leading, spacing: 14 * scale) {
                HStack(spacing: 12 * scale) {
                    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(width: 40 * scale, height: 40 * scale)
                        .overlay(TouchGlyphView(color: .white).frame(width: 26 * scale, height: 26 * scale))
                        .accessibilityHidden(true)
                    Text(Wording.setUpModeTitle)
                        .font(.system(size: 22 * scale, weight: .bold))
                }
                Text(Wording.setUpModeIntro)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10 * scale) {
                    ForEach(session.lines) { line in
                        SetUpModeLineView(
                            line: line, scale: scale,
                            check: session.checkOffer == .eachLine ? availability(line.id) : nil,
                            onCheck: { check(line.id) })
                    }
                }
                if let notice = session.notice {
                    HStack(alignment: .firstTextBaseline, spacing: 7 * scale) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(Wording.setUpModeNotice(notice))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let touched = session.touchedFirst {
                    HStack(spacing: 10 * scale) {
                        SetUpModeTouchedLine(text: Wording.setUpModeYouTouched(name: touched), size: 13 * scale)
                        Spacer(minLength: 10)
                        SetUpModeButtonView(button: .back, isProminent: false, scale: scale, perform: perform)
                            .setUpControlSize(scale)
                    }
                }
                checkRow
                Divider()
                HStack(spacing: 10 * scale) {
                    Text(Wording.setUpModeEscLeaves)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    SetUpModeButtonView(button: .finish, isProminent: false, scale: scale, perform: perform)
                }
                .setUpControlSize(scale)
            }
            .frame(width: 400 * scale, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    /// "Touch not working right?": with one touchscreen, Check This Touchscreen… beside it
    /// (`SetUpCheckRow`); with several, where their Check… is.
    @ViewBuilder private var checkRow: some View {
        switch session.checkOffer {
        case .one(let id)?:
            SetUpCheckRow(touchscreen: id, availability: session.checks[id] ?? .notConnected, scale: scale, check: check)
        case .eachLine?:
            Text(Wording.setUpModeCheckEachLine)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }
}

/// "You touched …": in the primary colour, to read on the dark cards, with the accent in its icon.
private struct SetUpModeTouchedLine: View {
    var text: String
    var size: CGFloat

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(Color.accentColor)
        }
        .font(.system(size: size, weight: .semibold))
    }
}

/// A touchscreen on the session card: its name and state, and why it can't be set up; with several
/// touchscreens, Check… beside its state, and why that can't be used when it can't.
private struct SetUpModeLineView: View {
    var line: SetUpTouchscreenLine
    var scale: CGFloat
    /// Whether Check… can be used; nil: not shown.
    var check: SupportCheckAvailability?
    var onCheck: @MainActor () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9 * scale) {
            icon
                .font(.system(size: 14 * scale))
            VStack(alignment: .leading, spacing: 2 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    Text(line.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    // Which display it is on reads in full; a long name gives way first.
                    Text(Wording.setUpModeLine(line.state))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let check {
                        Button { onCheck() } label: { SetUpButtonLabel(title: Wording.checkButton, scale: scale) }
                            .disabled(check != .available)
                            .controlSize(scale > 1.2 ? .large : .regular)
                    }
                }
                if line.state == .cannotBeSetUp, let reason = line.reason {
                    Text(reason)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let check, check != .available {
                    Text(Wording.supportUnavailable(check))
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: check == nil ? .combine : .contain)
    }

    @ViewBuilder private var icon: some View {
        switch line.state {
        case .setUp: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .notSetUp: Image(systemName: "circle.dashed").foregroundStyle(.orange)
        case .cannotBeSetUp: Image(systemName: "nosign").foregroundStyle(.secondary)
        }
    }
}
