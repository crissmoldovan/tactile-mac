// What a set-up screen draws. Each display gets two windows (see `SetUpOverlay`): the backdrop,
// the whole display, which acts on no click (an opaque one swallows clicks, the others let them
// through); and, where the screen has buttons, a small card of buttons above it, the only part that
// acts on one. The touchscreen's own touches go to the set-up and are never clicks, so the buttons
// say they answer the mouse or the keyboard. Set-up mode's overview draws its own cards
// (`SetUpModeViews.swift`) into the same two windows.

import SwiftUI
import TactileScreens

/// Sizes that scale with the display, so the screen being touched reads from where the person
/// stands, on a 12″ strip and on a 27″ display alike.
struct SetUpMetrics: Equatable {
    var displaySize: CGSize

    /// The chosen display's message: very large, and never wider than the display.
    var title: CGFloat {
        min(max(min(displaySize.width * 0.035, displaySize.height * 0.1), 32), 96)
    }
    var lead: CGFloat { max(20, title * 0.5) }
    var body: CGFloat { max(15, title * 0.3) }
    var progress: CGFloat { max(13, title * 0.2) }
    var targetRadius: CGFloat { min(max(min(displaySize.width, displaySize.height) * 0.04, 22), 44) }
    /// The touch glyph above the chosen display's message.
    var glyphSize: CGFloat { title * 1.3 }
    /// How much larger than usual the buttons' cards are drawn: 1 on the strip, up to 1.5 on a
    /// large display, read from further away.
    var cardScale: CGFloat { min(max(title / 64, 1), 1.5) }
}

extension SetUpScreenRole {
    /// The appearance a screen's backdrop is drawn in, whatever the Mac's: the display chosen in
    /// set-up mode is bright, so it stands out across the desk; corners and size are dark, as
    /// mockup 8 draws them; a dimmed display's line is light on dark. Nil: the Mac's own (the check,
    /// over the person's own windows).
    var backdropScheme: ColorScheme? {
        switch self {
        case .overview(let overview): return overview.card?.moment == .touchHere ? .light : .dark
        case .corners, .size, .elsewhere: return .dark
        case .check: return nil
        }
    }

    /// The appearance of its cards: light on the chosen display and on the dark corners and size,
    /// so the card stands out; dark on a dimmed display, and on the overview's other displays, so
    /// they don't glare; the Mac's own in the check.
    var cardScheme: ColorScheme? {
        switch self {
        case .overview(let overview): return overview.card?.moment == .touchHere ? .light : .dark
        case .corners, .size: return .light
        case .elsewhere: return .dark
        case .check: return nil
        }
    }
}

extension SetUpScreen {
    /// How the screens say Esc ends it: in set-up mode it leaves the whole mode.
    var escLine: String {
        if inSetUpMode { return Wording.setUpPressEscToLeave }
        if case .overview = role { return Wording.setUpPressEscToLeave }
        return Wording.setUpPressEsc
    }
}

extension View {
    /// `scheme`, when there is one.
    @ViewBuilder func setUpColorScheme(_ scheme: ColorScheme?) -> some View {
        if let scheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

// MARK: - The backdrop

/// The whole display: what the screen shows, except its buttons. It acts on no click: the overview,
/// corners and size screens swallow them, the others let them through (see
/// `SetUpScreen.backdropTakesMouse`).
struct SetUpBackdrop: View {
    var screen: SetUpScreen
    var displaySize: CGSize

    private var metrics: SetUpMetrics { SetUpMetrics(displaySize: displaySize) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            if screen.role.isTouched, let progress = screen.progress {
                // At the top, in the middle: clear of the corner targets.
                SetUpProgressLine(name: screen.touchscreenName, progress: progress, size: metrics.progress,
                                  onClear: isClear)
                    .padding(.top, max(20, metrics.progress * 1.6))
                    .frame(width: displaySize.width, alignment: .top)
            }
            if case .corners(let target, _, _) = screen.role {
                SetUpTarget(radius: metrics.targetRadius)
                    .position(x: target.x * displaySize.width, y: target.y * displaySize.height)
            }
            if screen.messageAtEdge {
                edgeLine
                    .frame(width: displaySize.width, height: displaySize.height, alignment: .bottom)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        message
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: displaySize.width * 0.84)
                    }
                    .frame(height: max(0, displaySize.height / 2 - 12))
                    if !screen.hasControls {
                        Text(screen.escLine)
                            .font(.system(size: metrics.body * 0.8))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.top, SetUpScreens.controlsGap + 12)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: displaySize.width, height: displaySize.height)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .ignoresSafeArea()
        .setUpColorScheme(screen.role.backdropScheme)
        .accessibilityElement(children: .contain)
    }

    /// The line on another touchscreen's display: small, at the bottom edge, on a backing of its
    /// own, out of the way of what the person is doing there.
    private var edgeLine: some View {
        HStack(spacing: metrics.progress * 0.6) {
            Text(edgeText).fontWeight(.medium)
            Text("·").foregroundStyle(.white.opacity(0.5))
            Text(screen.escLine).foregroundStyle(.white.opacity(0.75))
        }
        .font(.system(size: metrics.progress))
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.progress)
        .padding(.vertical, metrics.progress * 0.5)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .padding(.bottom, max(16, metrics.progress * 1.2))
    }

    private var edgeText: String {
        let name = screen.touchscreenName
        switch screen.role {
        case .overview: return Wording.setUpModeElsewhere
        case .elsewhere(let displayName): return Wording.setUpElsewhere(name: name, displayName: displayName)
        default: return Wording.setUpSettingUp(name: name)
        }
    }

    private var isClear: Bool {
        if case .check = screen.role { return true }
        return false
    }

    @ViewBuilder private var background: some View {
        switch screen.role {
        case .overview(let overview) where overview.card?.moment == .touchHere:
            Color(white: 0.97)
                .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: max(8, metrics.title * 0.14)))
        case .corners, .size:
            Color(white: 0.09)
        case .check:
            Color.clear
        case .overview, .elsewhere:
            Color.black.opacity(screen.dimming)
        }
    }

    @ViewBuilder private var message: some View {
        let name = screen.touchscreenName
        switch screen.role {
        case .overview(let overview):
            if let card = overview.card, card.moment == .touchHere, !overview.saysTouchHereInACard {
                SetUpModeTouchHere(card: card, metrics: metrics)
            } else if !overview.hasCards {
                Text(Wording.setUpModeElsewhere)
                    .font(.system(size: metrics.body, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .elsewhere(let displayName):
            Text(Wording.setUpElsewhere(name: name, displayName: displayName))
                .font(.system(size: metrics.lead * 0.8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .corners(_, let index, let problem):
            VStack(spacing: metrics.body * 0.7) {
                Text(Wording.setUpCornersInstruction)
                    .font(.system(size: metrics.lead, weight: .semibold))
                SetUpCornersProgress(index: index, size: metrics.body)
                if let problem {
                    Label(Wording.setUpProblem(problem), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: metrics.body, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.top, metrics.body * 0.3)
                } else if screen.restartedCorners {
                    Label(Wording.setUpCornersRestarted, systemImage: "arrow.counterclockwise")
                        .font(.system(size: metrics.body))
                        .foregroundStyle(.secondary)
                        .padding(.top, metrics.body * 0.3)
                }
            }
        case .size, .check:
            EmptyView()
        }
    }
}

/// "ILITEK-TP · Pair › Corners › Size › Check", the step it is at in bold; "ILITEK-TP · Test" for
/// a test.
struct SetUpProgressLine: View {
    var name: String
    var progress: SetUpProgress
    var size: CGFloat
    /// Over the person's own windows (the check): on a backing of its own, to read on anything.
    var onClear: Bool

    var body: some View {
        HStack(spacing: size * 0.45) {
            Text(name).fontWeight(.semibold)
            Text("·").foregroundStyle(.tertiary)
            if progress.steps.isEmpty {
                Text(Wording.setUpTest).fontWeight(.semibold)
            }
            ForEach(Array(progress.steps.enumerated()), id: \.offset) { position, step in
                if position > 0 {
                    Text("›").foregroundStyle(.tertiary)
                }
                Text(Wording.setUpStepName(step))
                    .fontWeight(step == progress.current ? .semibold : .regular)
                    .foregroundStyle(step == progress.current ? .primary : .secondary)
            }
        }
        .font(.system(size: size))
        .padding(.horizontal, onClear ? size * 0.8 : 0)
        .padding(.vertical, onClear ? size * 0.45 : 0)
        .background {
            if onClear {
                Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The corners target: a ring with a cross through it and a dot at its centre, in the accent colour.
struct SetUpTarget: View {
    var radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: max(2.5, radius * 0.08))
            Path { path in
                path.move(to: CGPoint(x: radius, y: -radius * 0.45))
                path.addLine(to: CGPoint(x: radius, y: radius * 2.45))
                path.move(to: CGPoint(x: -radius * 0.45, y: radius))
                path.addLine(to: CGPoint(x: radius * 2.45, y: radius))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: max(1.5, radius * 0.05), lineCap: .round))
            Circle()
                .fill(Color.accentColor)
                .frame(width: max(6, radius * 0.24), height: max(6, radius * 0.24))
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityHidden(true)
    }
}

/// Four dots, the done ones filled and the current one ringed, and "2 of 4".
struct SetUpCornersProgress: View {
    var index: Int
    var size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.4) {
            ForEach(0..<SetUpScreens.targetCount, id: \.self) { position in
                Circle()
                    .strokeBorder(position == index ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                    .background(Circle().fill(position < index ? Color.primary : .clear))
                    .frame(width: size * 0.55, height: size * 0.55)
            }
            Text(Wording.setUpCornersProgress(index: index))
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .padding(.leading, size * 0.3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Wording.setUpCornersProgress(index: index))
    }
}

// MARK: - The buttons

/// A screen's buttons: the only part of it that takes the mouse.
struct SetUpControls: View {
    var screen: SetUpScreen
    var displaySize: CGSize
    var perform: PerformCommand

    var body: some View {
        let scale = SetUpMetrics(displaySize: displaySize).cardScale
        Group {
            switch screen.role {
            case .overview(let overview):
                SetUpModeControls(overview: overview, mouseHint: screen.mouseHint, scale: scale, perform: perform)
            case .size(let choices):
                SetUpSizeCard(choices: choices, inSetUpMode: screen.inSetUpMode, scale: scale, perform: perform)
            case .check(let canRedo):
                SetUpCheckCard(canRedo: canRedo, inSetUpMode: screen.inSetUpMode, scale: scale, perform: perform)
            case .corners, .elsewhere:
                SetUpCancelCard(isTouched: screen.role.isTouched, inSetUpMode: screen.inSetUpMode,
                                mouseHint: screen.mouseHint, scale: scale, perform: perform)
            }
        }
        .fixedSize()
        .setUpColorScheme(screen.role.cardScheme)
    }
}

extension View {
    /// The cards' buttons: large, and larger again on a large display, so they keep up with the
    /// type beside them.
    func setUpControlSize(_ scale: CGFloat) -> some View {
        controlSize(scale > 1.2 ? .extraLarge : .large)
    }
}

/// The card the buttons sit on.
struct SetUpCard<Content: View>: View {
    var scale: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 13 * scale))
            .padding(18 * scale)
            .background(
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// "Use the mouse or the keyboard for these buttons." (in set-up mode, beside Back alone, "Use the
/// mouse for this button."; see `SetUpScreen.mouseHint`), with a pointer beside it.
struct SetUpMouseHint: View {
    var text = Wording.setUpMouseHint
    var scale: CGFloat

    var body: some View {
        Label(text, systemImage: "cursorarrow")
            .font(.system(size: 12 * scale))
            .foregroundStyle(.secondary)
    }
}

/// Cancel; in set-up mode, Back, which ends this touchscreen's flow and returns to the overview.
/// Esc is not Back's: it leaves the whole mode, through the overlay's key monitors.
private struct SetUpCancelButton: View {
    var inSetUpMode: Bool
    var scale: CGFloat
    var perform: PerformCommand

    var body: some View {
        if inSetUpMode {
            Button { perform(.setUpBack) } label: { SetUpButtonLabel(title: Wording.setUpModeBack, scale: scale) }
        } else {
            Button { perform(.cancelSetUp) } label: { SetUpButtonLabel(title: Wording.cancel, scale: scale) }
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// A card button's title, in type that scales with the display: a bordered button sets its own
/// font, which the card's would not reach.
struct SetUpButtonLabel: View {
    var title: String
    var scale: CGFloat

    var body: some View {
        Text(title).font(.system(size: 13 * scale))
    }
}

/// Cancel (Back, in set-up mode), and how else to end it.
struct SetUpCancelCard: View {
    var isTouched: Bool
    var inSetUpMode = false
    var mouseHint = Wording.setUpMouseHint
    var scale: CGFloat
    var perform: PerformCommand

    var body: some View {
        SetUpCard(scale: scale) {
            VStack(spacing: 10 * scale) {
                HStack(spacing: 14 * scale) {
                    SetUpCancelButton(inSetUpMode: inSetUpMode, scale: scale, perform: perform)
                        .setUpControlSize(scale)
                    Text(inSetUpMode ? Wording.setUpPressEscToLeave : Wording.setUpPressEsc)
                        .foregroundStyle(.secondary)
                }
                if isTouched {
                    SetUpMouseHint(text: mouseHint, scale: scale)
                }
            }
        }
    }
}

/// The size card: the question, the sizes reported, another size typed in, and Continue.
struct SetUpSizeCard: View {
    var choices: SetUpSizeChoices
    var inSetUpMode = false
    var scale: CGFloat
    var perform: PerformCommand

    @State private var choice: SetUpSizeChoices.Choice
    @State private var text: String
    @FocusState private var isTyping: Bool

    init(choices: SetUpSizeChoices, inSetUpMode: Bool = false, scale: CGFloat, perform: @escaping PerformCommand) {
        self.choices = choices
        self.inSetUpMode = inSetUpMode
        self.scale = scale
        self.perform = perform
        _choice = State(initialValue: choices.initialChoice)
        _text = State(initialValue: choices.initialText)
    }

    var body: some View {
        let command = choices.command(choice, text: text)
        SetUpCard(scale: scale) {
            VStack(alignment: .leading, spacing: 14 * scale) {
                Text(Wording.setUpSizeQuestion(displayReports: choices.displayReports,
                                               touchscreenReports: choices.touchscreenReports))
                    .font(.system(size: 22 * scale, weight: .semibold))
                VStack(spacing: 8 * scale) {
                    ForEach(choices.choices, id: \.self) { option in
                        row(option)
                    }
                }
                Text(Wording.setUpSizeHint)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10 * scale) {
                    Text(inSetUpMode ? Wording.setUpPressEscToLeave : Wording.setUpPressEsc)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 20)
                    SetUpCancelButton(inSetUpMode: inSetUpMode, scale: scale, perform: perform)
                    Button(action: submit) { SetUpButtonLabel(title: Wording.setUpContinue, scale: scale) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(command == nil)
                }
                .setUpControlSize(scale)
                SetUpMouseHint(scale: scale)
            }
            .frame(width: 460 * scale, alignment: .leading)
        }
        .onAppear {
            // The field takes the keyboard: typing a size chooses Another size, and Return
            // continues with the choice made, the size reported unless one is typed.
            Task { @MainActor in isTyping = true }
        }
    }

    /// Continue: the choice made. A size that can't be taken beeps, and the field keeps what was
    /// typed. (Should Return reach both the field and the default button, the second command comes
    /// after the step has moved on, and the model ignores it.)
    private func submit() {
        guard let command = choices.command(choice, text: text) else {
            NSSound.beep()
            isTyping = choice == .another
            return
        }
        perform(command)
    }

    @ViewBuilder private func row(_ option: SetUpSizeChoices.Choice) -> some View {
        let isChosen = option == choice
        HStack(spacing: 10 * scale) {
            Button {
                choice = option
                isTyping = option == .another
            } label: {
                HStack(spacing: 10 * scale) {
                    Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isChosen ? Color.accentColor : .secondary)
                        .font(.system(size: 17 * scale))
                    switch option {
                    case .displayReport:
                        reported(choices.displayReports, option)
                    case .touchscreenReport:
                        reported(choices.touchscreenReports, option)
                    case .another:
                        Text(Wording.setUpSizeChoice(.another))
                            .font(.system(size: 17 * scale))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if option == .another {
                TextField(Wording.diagonal, text: $text, prompt: Text(Wording.diagonalPrompt))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17 * scale))
                    .frame(width: 96 * scale)
                    .focused($isTyping)
                    .onSubmit(submit)
                    .onChange(of: text) {
                        if !text.isEmpty { choice = .another }
                    }
                Text(Wording.inchesUnit)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 9 * scale)
        .background(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .strokeBorder(isChosen ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isChosen ? 2 : 1))
    }

    private func reported(_ inches: Double?, _ option: SetUpSizeChoices.Choice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
            Text(inches.map(Wording.inches) ?? "")
                .font(.system(size: 17 * scale, weight: .semibold))
            Text(Wording.setUpSizeChoice(option))
                .foregroundStyle(.secondary)
        }
    }
}

/// The check's card: where to touch, and Cancel (Back, in set-up mode), Redo and Done.
struct SetUpCheckCard: View {
    var canRedo: Bool
    var inSetUpMode = false
    var scale: CGFloat
    var perform: PerformCommand

    var body: some View {
        SetUpCard(scale: scale) {
            VStack(spacing: 12 * scale) {
                Text(Wording.setUpCheckInstruction)
                    .font(.system(size: 20 * scale, weight: .semibold))
                HStack(spacing: 10 * scale) {
                    SetUpCancelButton(inSetUpMode: inSetUpMode, scale: scale, perform: perform)
                    if canRedo {
                        Button { perform(.setUpRedo) } label: { SetUpButtonLabel(title: Wording.setUpRedo, scale: scale) }
                    }
                    Button { perform(.setUpDone) } label: { SetUpButtonLabel(title: Wording.setUpDone, scale: scale) }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .setUpControlSize(scale)
                HStack(spacing: 14 * scale) {
                    Text(inSetUpMode ? Wording.setUpPressEscToLeave : Wording.setUpPressEsc)
                        .foregroundStyle(.secondary)
                    SetUpMouseHint(scale: scale)
                }
                .font(.system(size: 12 * scale))
            }
        }
    }
}
