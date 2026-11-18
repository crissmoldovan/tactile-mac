// The tester's practice area: real controls, which react to the events Tactile posts for the
// touchscreen, as any app's would.
//
// - Taps: a button (`NSButton` under SwiftUI) that counts its presses, and a pad that shows the
//   click count of the last press it received (`NSEvent.clickCount`): it only shows, and says so.
// - Text: an `NSTextView`, selectable: a double click selects a word, a triple click a paragraph,
//   a drag selects; what is selected is shown beneath.
// - Cards: SwiftUI's `DragGesture`, which follows the mouse-dragged events of a press, drag, release.
// - Scrolling: two `ScrollView`s (each an `NSScrollView`), driven by scroll-wheel events with their
//   phases and momentum.
// - The photo: an `NSView` over it takes `magnify(with:)` and `rotate(with:)`, which AppKit sends
//   for the trackpad's magnify and rotate gesture events, the kind Tactile posts, "to the view under
//   the touch in the key window". SwiftUI's `MagnifyGesture` and `RotateGesture` are documented for
//   macOS 14 without saying which input drives them on a Mac, so they aren't relied on here.
// - Right-click: SwiftUI's `contextMenu`, which opens on a right mouse down.
// - A slider, a checkbox and a pop-up menu: SwiftUI's, each an AppKit control underneath.
// - Swipes: a pad that explains them, with Let swipes through. It counts nothing itself.
// - Accidental touches: what this touchscreen can recognise, drawn and said. Where it doesn't report
//   the size of a touch, a whole hand laid flat at once (the contact filter's five fingers or more);
//   where it does, a resting palm; on a touchscreen that gives one finger (where a resting palm is a
//   finger), a touch starting within the edge margin. Beneath the drawing, live: how many fingers are
//   down short of a whole hand, what Tactile ignored, or that the rejection is off.
//
// On a touchscreen that gives one finger, the tiles that need more say so, as the rows do.
//
// The area reads nothing from the window's store that changes while a gesture goes on
// (`GestureTesterStore.practice`): what the feed changes reaches only the swipes tile's last swipe
// and the palm tile's line beneath its drawing, each read in its own view. That line follows the
// fingers on the glass and the count of what was ignored, which change when a finger lands or lifts,
// never with each frame. So scrolling the list, dragging a card or turning the photo is never
// interrupted by the area being drawn and laid out again.

import AppKit
import SwiftUI
import TactileGestures

struct PracticeArea: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    private var practice: GestureTesterStore.Practice { store.practice }
    private var oneFinger: OneFingerMode { practice.oneFinger }
    private var multiTouch: Bool { practice.multiTouch }

    var body: some View {
        let _ = store.bodies.count(.practice)
        TesterPanel(title: Wording.gestureTesterPractice, metrics: metrics) {
            Text(Wording.gestureTesterPracticeHint(oneFinger: oneFinger))
                .font(metrics.small)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } content: {
            switch store.layout {
            case .wide:
                VStack(spacing: metrics.gap) {
                    WeightedRow(weights: [2.8, 6, 3.4, 3.6], spacing: metrics.gap) {
                        tapTile
                        textTile
                        cardsTile
                        photoTile
                    }
                    WeightedRow(weights: [4.2, 3, 3.2, 4.6, 3.2], spacing: metrics.gap) {
                        scrollTile
                        rightClickTile
                        controlsTile
                        swipesTile
                        palmTile
                    }
                }
            case .regular:
                VStack(spacing: metrics.gap) {
                    WeightedRow(weights: [1, 1.3, 1], spacing: metrics.gap) {
                        tapTile
                        textTile
                        cardsTile
                    }
                    WeightedRow(weights: [1, 1.3, 1], spacing: metrics.gap) {
                        scrollTile
                        photoTile
                        rightClickTile
                    }
                    WeightedRow(weights: [1, 1.3, 1], spacing: metrics.gap) {
                        controlsTile
                        swipesTile
                        palmTile
                    }
                }
            }
        }
    }

    private var tapTile: some View {
        PracticeTile(title: Wording.practiceTapTitle, metrics: metrics) { TapPractice(metrics: metrics) }
    }

    private var textTile: some View {
        PracticeTile(title: Wording.practiceTextTitle, hint: Wording.practiceTextHint(oneFinger: oneFinger), metrics: metrics) {
            TextPractice(metrics: metrics)
        }
    }

    private var cardsTile: some View {
        PracticeTile(
            title: Wording.practiceCardsTitle,
            hint: oneFinger == .alwaysScroll ? Wording.practiceCardsHintHold : Wording.practiceCardsHint, metrics: metrics
        ) {
            CardsPractice(metrics: metrics)
        }
    }

    private var photoTile: some View {
        PracticeTile(title: Wording.practicePhotoTitle, hint: Wording.practicePhotoHint(multiTouch: multiTouch), metrics: metrics) {
            PhotoPractice(metrics: metrics)
        }
    }

    private var scrollTile: some View {
        PracticeTile(title: Wording.practiceScrollTitle, hint: Wording.practiceScrollHint, metrics: metrics) {
            ScrollPractice(metrics: metrics)
        }
    }

    private var rightClickTile: some View {
        PracticeTile(
            title: Wording.practiceRightClickTitle, hint: Wording.practiceRightClickHint(multiTouch: multiTouch),
            metrics: metrics
        ) {
            RightClickPractice(metrics: metrics)
        }
    }

    private var controlsTile: some View {
        PracticeTile(title: Wording.practiceControlsTitle, hint: Wording.practiceControlsHint, metrics: metrics) {
            ControlsPractice(metrics: metrics)
        }
    }

    private var swipesTile: some View {
        PracticeTile(title: Wording.practiceSwipesTitle, hint: Wording.practiceSwipesHint, metrics: metrics) {
            SwipesPractice(store: store, multiTouch: multiTouch, metrics: metrics)
        }
    }

    private var palmTile: some View {
        let kind = PalmTileKind(multiTouch: multiTouch, reportsPalms: practice.reportsPalms)
        return PracticeTile(
            title: Wording.practicePalmTitle(kind),
            hint: Wording.practicePalmHint(kind, edgeMarginMM: practice.edgeMarginMM),
            metrics: metrics
        ) {
            PalmPractice(store: store, kind: kind, edgeMarginMM: practice.edgeMarginMM, metrics: metrics)
        }
    }
}

/// Places its views side by side across the width it is offered, each as wide as its share of the
/// weights, all as tall as the row. Its size is the size offered: it never asks its views theirs.
struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat

    /// Each view's weight and their total, worked out when its views change, not on every pass.
    struct Shares {
        var weights: [CGFloat]
        var total: CGFloat
    }

    func makeCache(subviews: Subviews) -> Shares {
        let weights = subviews.indices.map { $0 < self.weights.count ? max(self.weights[$0], 0.01) : 1 }
        return Shares(weights: weights, total: weights.reduce(0, +))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Shares) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 600, height: 200))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Shares) {
        guard !subviews.isEmpty else { return }
        let available = max(0, bounds.width - spacing * CGFloat(subviews.count - 1))
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = (available * cache.weights[index] / cache.total).rounded(.down)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// One practice tile: its title, what to do, and its control.
struct PracticeTile<Content: View>: View {
    var title: String
    var hint: String? = nil
    var metrics: GestureTesterMetrics
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.tilePadding * 0.5) {
            Text(title).font(metrics.tileTitle)
            if let hint {
                Text(hint)
                    .font(metrics.tileHint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(metrics.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// A quiet line beneath a control: what it saw.
struct PracticeReadout: View {
    var text: String
    var metrics: GestureTesterMetrics

    var body: some View {
        Text(text)
            .font(metrics.tileHint.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

// MARK: - Taps

struct TapPractice: View {
    var metrics: GestureTesterMetrics
    @State private var taps = 0
    @State private var clickCount = 0
    @State private var presses = 0

    var body: some View {
        VStack(spacing: metrics.tilePadding * 0.6) {
            // The tap target: larger than a plain button, so a fingertip finds it.
            Button {
                taps += 1
            } label: {
                Text(Wording.practiceTapButton)
                    .font(metrics.tileTitle)
                    .padding(.horizontal, metrics.tilePadding)
                    .padding(.vertical, metrics.tilePadding * 0.35)
            }
            .controlSize(metrics.controlSize)
            .buttonStyle(.borderedProminent)
            PracticeReadout(text: Wording.practiceTapped(taps), metrics: metrics)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(presses % 2 == 0 ? 0.1 : 0.18))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                VStack(spacing: 2) {
                    Text(Wording.practiceClickCount(clickCount))
                        .font(metrics.tileTitle)
                    Text(Wording.practiceClickPad)
                        .font(metrics.tileHint)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                EventCatcher(onPress: { count in
                    clickCount = count
                    presses += 1
                })
            }
        }
    }
}

// MARK: - Text

struct TextPractice: View {
    var metrics: GestureTesterMetrics
    @State private var selection = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PracticeTextView(text: Wording.practiceText, fontSize: metrics.textSize, selection: $selection)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            PracticeReadout(text: Wording.practiceSelection(selection), metrics: metrics)
        }
    }
}

/// A selectable, read-only `NSTextView` in its scroll view: the selection is reported as it changes.
struct PracticeTextView: NSViewRepresentable {
    var text: String
    var fontSize: CGFloat
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        if let textView = scroll.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 6)
            textView.font = .systemFont(ofSize: fontSize)
            textView.textColor = .labelColor
            textView.string = text
            textView.delegate = context.coordinator
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.selection = $selection
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var selection: Binding<String>

        init(selection: Binding<String>) {
            self.selection = selection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let text = textView.string as NSString
            selection.wrappedValue = range.location == NSNotFound || NSMaxRange(range) > text.length
                ? "" : text.substring(with: range)
        }
    }
}

// MARK: - Cards

/// The card being dragged moves by an offset, drawn where it is and laid out nowhere: its place in
/// the tile (`position`) changes only when it is let go.
struct CardsPractice: View {
    var metrics: GestureTesterMetrics
    /// Where each card has been moved to, from where it started.
    @State private var moved: [CGSize] = Array(repeating: .zero, count: 3)
    @State private var dragging: (index: Int, by: CGSize)?

    private static let starts: [CGPoint] = [CGPoint(x: 0.24, y: 0.32), CGPoint(x: 0.52, y: 0.66), CGPoint(x: 0.78, y: 0.34)]
    private static let colours: [Color] = [.orange, .teal, .pink]
    private static let letters = ["A", "B", "C"]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let card = CGSize(width: min(110, max(54, size.width * 0.26)), height: min(76, max(38, size.height * 0.3)))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Self.colours[index].gradient)
                        .overlay(Text(Self.letters[index]).font(metrics.tileTitle).foregroundStyle(.white))
                        .shadow(color: .black.opacity(dragging?.index == index ? 0.35 : 0.15), radius: dragging?.index == index ? 6 : 2, y: 1)
                        .frame(width: card.width, height: card.height)
                        .position(rest(index, in: size))
                        .offset(dragOffset(index, in: size, card: card))
                        .zIndex(dragging?.index == index ? 1 : 0)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in dragging = (index, value.translation) }
                                .onEnded { value in
                                    moved[index] = clamped(index, adding: value.translation, in: size, card: card)
                                    dragging = nil
                                })
                }
            }
        }
    }

    /// Where the card rests: where it started, and where it has been moved to.
    private func rest(_ index: Int, in size: CGSize) -> CGPoint {
        let start = Self.starts[index]
        return CGPoint(x: start.x * size.width + moved[index].width, y: start.y * size.height + moved[index].height)
    }

    /// How far the card being dragged is from where it rests, kept inside the tile; zero for the others.
    private func dragOffset(_ index: Int, in size: CGSize, card: CGSize) -> CGSize {
        guard let dragging, dragging.index == index else { return .zero }
        let offset = clamped(index, adding: dragging.by, in: size, card: card)
        return CGSize(width: offset.width - moved[index].width, height: offset.height - moved[index].height)
    }

    /// The card's offset with `translation` added, kept inside the tile.
    private func clamped(_ index: Int, adding translation: CGSize, in size: CGSize, card: CGSize) -> CGSize {
        let start = Self.starts[index]
        let x = start.x * size.width + moved[index].width + translation.width
        let y = start.y * size.height + moved[index].height + translation.height
        let clampedX = min(max(x, card.width / 2), max(card.width / 2, size.width - card.width / 2))
        let clampedY = min(max(y, card.height / 2), max(card.height / 2, size.height - card.height / 2))
        return CGSize(width: clampedX - start.x * size.width, height: clampedY - start.y * size.height)
    }
}

// MARK: - Scrolling

struct ScrollPractice: View {
    var metrics: GestureTesterMetrics

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(1...80, id: \.self) { number in
                        HStack {
                            Circle()
                                .fill(Color(hue: Double(number % 12) / 12, saturation: 0.45, brightness: 0.9))
                                .frame(width: metrics.badge * 0.6, height: metrics.badge * 0.6)
                            Text(Wording.practiceListRow(number))
                                .font(metrics.tileHint)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(number % 2 == 0 ? Color.secondary.opacity(0.06) : .clear)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(1...40, id: \.self) { number in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hue: Double(number % 10) / 10, saturation: 0.5, brightness: 0.85).gradient)
                            .overlay(Text("\(number)").font(metrics.tileTitle).foregroundStyle(.white))
                            .frame(width: metrics.badge * 2, height: metrics.badge * 1.6)
                    }
                }
                .padding(4)
            }
            .frame(height: metrics.badge * 1.6 + 8 + 10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

// MARK: - The photo

struct PhotoPractice: View {
    var metrics: GestureTesterMetrics
    @State private var scale = 1.0
    /// Degrees turned, anticlockwise as `NSEvent.rotation` has it.
    @State private var degrees = 0.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                PracticePhoto()
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(-degrees))
                EventCatcher(
                    onPress: { count in
                        if count >= 2 {
                            scale = 1
                            degrees = 0
                        }
                    },
                    onMagnify: { magnification in
                        scale = min(6, max(0.25, scale * (1 + magnification)))
                    },
                    onRotate: { turned in degrees += turned })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            PracticeReadout(text: Wording.practicePhotoState(scale: scale, degrees: degrees), metrics: metrics)
        }
    }
}

/// A landscape, drawn: sky, sun, two ranges of hills and a lake.
struct PracticePhoto: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.36, green: 0.6, blue: 0.92), Color(red: 0.98, green: 0.8, blue: 0.62)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.7)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.66, y: h * 0.14, width: w * 0.15, height: w * 0.15)),
                         with: .color(Color(red: 1, green: 0.88, blue: 0.4)))
            var far = Path()
            far.move(to: CGPoint(x: 0, y: h * 0.62))
            far.addLine(to: CGPoint(x: w * 0.22, y: h * 0.36))
            far.addLine(to: CGPoint(x: w * 0.4, y: h * 0.55))
            far.addLine(to: CGPoint(x: w * 0.6, y: h * 0.3))
            far.addLine(to: CGPoint(x: w, y: h * 0.6))
            far.addLine(to: CGPoint(x: w, y: h))
            far.addLine(to: CGPoint(x: 0, y: h))
            far.closeSubpath()
            context.fill(far, with: .color(Color(red: 0.42, green: 0.5, blue: 0.66)))
            var near = Path()
            near.move(to: CGPoint(x: 0, y: h * 0.74))
            near.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.66), control: CGPoint(x: w * 0.28, y: h * 0.56))
            near.addQuadCurve(to: CGPoint(x: w, y: h * 0.72), control: CGPoint(x: w * 0.8, y: h * 0.62))
            near.addLine(to: CGPoint(x: w, y: h))
            near.addLine(to: CGPoint(x: 0, y: h))
            near.closeSubpath()
            context.fill(near, with: .color(Color(red: 0.3, green: 0.58, blue: 0.36)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.8, width: w * 0.5, height: h * 0.12)),
                         with: .color(Color(red: 0.4, green: 0.66, blue: 0.9).opacity(0.9)))
        }
        .accessibilityLabel(Wording.practicePhotoTitle)
    }
}

// MARK: - Right-click

struct RightClickPractice: View {
    var metrics: GestureTesterMetrics
    @State private var chosen: String?

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.purple.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "contextualmenu.and.cursorarrow")
                            .font(.system(size: metrics.tileIcon * 0.8))
                            .foregroundStyle(.purple)
                        Text(Wording.practiceRightClickTarget)
                            .font(metrics.tileHint.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .padding(4))
                .contentShape(Rectangle())
                .contextMenu {
                    ForEach(Wording.practiceMenuItems, id: \.self) { item in
                        Button(item) { chosen = item }
                    }
                }
            PracticeReadout(text: Wording.practiceMenuChosen(chosen), metrics: metrics)
        }
    }
}

// MARK: - Controls

struct ControlsPractice: View {
    var metrics: GestureTesterMetrics
    @State private var value = 40.0
    @State private var isChecked = false
    @State private var fruit = Wording.practiceFruits[0]

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.tilePadding * 0.6) {
            HStack(spacing: 6) {
                Slider(value: $value, in: 0...100)
                    .accessibilityLabel(Wording.practiceSlider)
                Text("\(Int(value.rounded()))")
                    .font(metrics.tileHint.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            Toggle(Wording.practiceCheckbox, isOn: $isChecked)
                .toggleStyle(.checkbox)
            Picker(Wording.practicePopUp, selection: $fruit) {
                ForEach(Wording.practiceFruits, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .controlSize(metrics.controlSize)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Swipes

struct SwipesPractice: View {
    let store: GestureTesterStore
    var multiTouch: Bool
    var metrics: GestureTesterMetrics

    var body: some View {
        let _ = store.bodies.count(.swipes)
        let swipes = store.swipes
        VStack(alignment: .leading, spacing: metrics.tilePadding * 0.5) {
            if multiTouch {
                Toggle(isOn: Binding(
                    get: { swipes.performsSwipes },
                    set: { [store] in store.perform(.setGestureTesterPerformsSwipes($0)) }
                )) {
                    Text(Wording.practiceLetSwipesThrough).fixedSize()
                }
                    .toggleStyle(.switch)
                    .controlSize(metrics.switchSize == .mini ? .small : .regular)
                    .font(metrics.tileHint.weight(.medium))
                Text(Wording.practiceSwipesState(performsSwipes: swipes.performsSwipes))
                    .font(metrics.tileHint)
                    .foregroundStyle(swipes.performsSwipes ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let last = swipes.lastSwipe {
                    PracticeReadout(text: Wording.practiceLastSwipe(last), metrics: metrics)
                }
            } else {
                Text(Wording.gestureTesterState(.needsMoreThanOneFinger) ?? "")
                    .font(metrics.tileHint.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(["arrow.left", "arrow.right", "arrow.up", "arrow.down"], id: \.self) { arrow in
                    Image(systemName: arrow)
                        .font(.system(size: metrics.tileIcon * 0.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(multiTouch ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Palm

/// The palm tile's area: what this touchscreen can recognise, drawn, and the line beneath it. The
/// area itself reads nothing that changes while a gesture goes on.
struct PalmPractice: View {
    let store: GestureTesterStore
    var kind: PalmTileKind
    var edgeMarginMM: Double
    var metrics: GestureTesterMetrics

    var body: some View {
        let _ = store.bodies.count(.palm)
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                PalmTileDrawing(kind: kind)
                    .padding(metrics.tilePadding * 0.5)
            }
            PalmFeedbackLine(store: store, kind: kind, edgeMarginMM: edgeMarginMM, metrics: metrics)
        }
    }
}

/// Beneath the palm tile's drawing, live (`PalmTileFeedback`): drawn again when a finger lands or
/// lifts (for a whole hand), when something is ignored, and when palm rejection is switched; never
/// with the feed's entries. The newest ignored entry is read only when the count of them rises.
struct PalmFeedbackLine: View {
    let store: GestureTesterStore
    var kind: PalmTileKind
    var edgeMarginMM: Double
    var metrics: GestureTesterMetrics

    @State private var reading = PalmTileReading()
    @Environment(\.palmFeedbackBodies) private var bodies

    var body: some View {
        let _ = bodies?.counted()
        let inputs = PalmTileReading.Inputs(
            fingers: kind == .wholeHand ? store.fingersDown : 0, ignored: store.palmIgnored)
        let palmIsOn = kind == .edge || (store.checklist.behaviour?.rejection.palm ?? true)
        let feedback = PalmTileFeedback(
            kind, palmIsOn: palmIsOn, edgeMarginMM: edgeMarginMM, fingersDown: inputs.fingers, reading: reading)
        Text(feedback.text)
            .font(metrics.tileHint.weight(.medium))
            .foregroundStyle(Self.colour(feedback.tone))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .onChange(of: inputs, initial: true) { old, new in
                // Read outside the body: the entries change with every frame, and this reads them
                // only when the count of ignored ones rose.
                let newest = { [store] in PalmTileReading.newestIgnored(in: store.recent) }
                if old == new {
                    reading = PalmTileReading(new, newest: newest())
                } else {
                    reading.follow(from: old, to: new, newest: newest)
                }
            }
    }

    private static func colour(_ tone: PalmTileFeedback.Tone) -> Color {
        switch tone {
        case .rule: return .secondary
        case .notYet: return .primary
        case .ignored: return .green
        case .off: return .orange
        }
    }
}

/// Counts the times the palm tile's line works out its body, for the test that holds it to the
/// fingers' pace. Nil in the app, where nothing is counted.
@MainActor
final class PalmFeedbackBodies {
    private(set) var count = 0

    func counted() {
        count += 1
    }

    func reset() {
        count = 0
    }
}

private struct PalmFeedbackBodiesKey: EnvironmentKey {
    static let defaultValue: PalmFeedbackBodies? = nil
}

extension EnvironmentValues {
    var palmFeedbackBodies: PalmFeedbackBodies? {
        get { self[PalmFeedbackBodiesKey.self] }
        set { self[PalmFeedbackBodiesKey.self] = newValue }
    }
}

/// The palm tile's picture, an outline that scales with the tile: a hand, fingers spread, for a
/// whole hand or a palm (the palm shaded); for the edge, a screen with its edge band shaded and a
/// fingertip in it.
struct PalmTileDrawing: View {
    var kind: PalmTileKind

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .wholeHand, .palm:
                Self.drawHand(context, in: size, palmShaded: kind == .palm)
            case .edge:
                Self.drawEdge(context, in: size)
            }
        }
        .accessibilityHidden(true)
    }

    private static var outline: Color { Color(nsColor: .secondaryLabelColor) }

    private static func lineWidth(_ size: CGSize) -> CGFloat {
        max(1.5, min(size.width, size.height) * 0.014)
    }

    // MARK: The hand

    /// A finger: a capsule standing on `base`, `length` long, leaning `degrees` (to the right when
    /// positive), in a square of 1.
    private static func finger(base: CGPoint, length: CGFloat, degrees: CGFloat, width: CGFloat = 0.15) -> Path {
        let capsule = Path(
            roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length + width / 2),
            cornerRadius: width / 2)
        let place = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: degrees * .pi / 180)
        return capsule.applying(place)
    }

    /// The hand's parts, in a square of 1: the palm, four fingers spread, and the thumb.
    private static let palm = Path(
        roundedRect: CGRect(x: 0.22, y: 0.46, width: 0.58, height: 0.5), cornerRadius: 0.17)
    /// The fingers' bases overlap a little, so the outline runs from one finger to the next with no
    /// stretch of the palm's edge between them.
    private static let digits: [Path] = [
        finger(base: CGPoint(x: 0.31, y: 0.54), length: 0.42, degrees: -14),
        finger(base: CGPoint(x: 0.45, y: 0.52), length: 0.48, degrees: -4),
        finger(base: CGPoint(x: 0.59, y: 0.53), length: 0.44, degrees: 7),
        finger(base: CGPoint(x: 0.72, y: 0.58), length: 0.34, degrees: 18),
        finger(base: CGPoint(x: 0.31, y: 0.80), length: 0.31, degrees: -58),
    ]

    private static func drawHand(_ context: GraphicsContext, in size: CGSize, palmShaded: Bool) {
        var hand = Path()
        hand.addPath(palm)
        for digit in digits {
            hand.addPath(digit)
        }
        // Scaled to fit inside its outline's width, centred, its proportions kept.
        let line = lineWidth(size)
        let room = CGSize(width: max(1, size.width - line * 3), height: max(1, size.height - line * 3))
        let bounds = hand.boundingRect
        let scale = min(room.width / bounds.width, room.height / bounds.height)
        let fit = CGAffineTransform(
            translationX: (size.width - bounds.width * scale) / 2, y: (size.height - bounds.height * scale) / 2
        )
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.minX, y: -bounds.minY)
        let parts = ([palm] + digits).map { $0.applying(fit) }
        let whole = hand.applying(fit)

        context.fill(whole, with: .color(Color.accentColor.opacity(0.1)))
        if palmShaded {
            context.fill(palm.applying(fit), with: .color(Color.accentColor.opacity(0.22)))
        }
        // The outline of the parts together: each part stroked twice as wide, then everything inside
        // the hand cleared, which leaves the outer half of each stroke and none of the joins.
        context.drawLayer { layer in
            for part in parts {
                layer.stroke(part, with: .color(outline), lineWidth: line * 2)
            }
            layer.blendMode = .destinationOut
            layer.fill(whole, with: .color(.black))
        }
    }

    // MARK: The edge

    private static func drawEdge(_ context: GraphicsContext, in size: CGSize) {
        // The strip's shape, 1600 × 600, fitted with room for the fingertip over its left edge.
        let aspect: CGFloat = 8 / 3
        let line = lineWidth(size)
        let margin = min(size.width, size.height) * 0.08 + line
        let width = max(1, min(size.width - margin * 2, (size.height - margin * 2) * aspect))
        let screen = CGRect(
            x: (size.width - width) / 2, y: (size.height - width / aspect) / 2, width: width, height: width / aspect)
        let band = screen.height * 0.16
        let inner = screen.insetBy(dx: band, dy: band)

        var edge = Path(roundedRect: screen, cornerRadius: band * 0.6)
        edge.addPath(Path(inner))
        context.fill(edge, with: .color(Color.orange.opacity(0.28)), style: FillStyle(eoFill: true))
        context.stroke(Path(inner), with: .color(outline.opacity(0.6)), style: StrokeStyle(lineWidth: line * 0.7, dash: [4, 3]))
        context.stroke(Path(roundedRect: screen, cornerRadius: band * 0.6), with: .color(outline), lineWidth: line)

        let tip = CGRect(x: screen.minX + band * 0.5 - band * 0.75, y: screen.midY - band * 0.75,
                         width: band * 1.5, height: band * 1.5)
        context.fill(Path(ellipseIn: tip), with: .color(Color.accentColor.opacity(0.35)))
        context.stroke(Path(ellipseIn: tip), with: .color(Color.accentColor), lineWidth: line)
    }
}

// MARK: - The events, from AppKit

/// A transparent view that takes the events SwiftUI has no gesture for on a Mac: a press with its
/// click count, and the trackpad's magnify and rotate events.
struct EventCatcher: NSViewRepresentable {
    var onPress: (@MainActor (Int) -> Void)? = nil
    var onMagnify: (@MainActor (Double) -> Void)? = nil
    var onRotate: (@MainActor (Double) -> Void)? = nil

    func makeNSView(context: Context) -> EventCatcherView {
        let view = EventCatcherView()
        update(view)
        return view
    }

    func updateNSView(_ view: EventCatcherView, context: Context) {
        update(view)
    }

    private func update(_ view: EventCatcherView) {
        view.onPress = onPress
        view.onMagnify = onMagnify
        view.onRotate = onRotate
    }
}

final class EventCatcherView: NSView {
    var onPress: (@MainActor (Int) -> Void)?
    var onMagnify: (@MainActor (Double) -> Void)?
    var onRotate: (@MainActor (Double) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let onPress else { return super.mouseDown(with: event) }
        onPress(event.clickCount)
    }

    override func magnify(with event: NSEvent) {
        guard let onMagnify else { return super.magnify(with: event) }
        onMagnify(Double(event.magnification))
    }

    override func rotate(with event: NSEvent) {
        guard let onRotate else { return super.rotate(with: event) }
        onRotate(Double(event.rotation))
    }
}
