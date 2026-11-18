// The gesture tester's content: a header, then its three parts side by side: what this touchscreen
// can do, a practice area of real controls, and what Tactile saw. Sized by its arrangement
// (`GestureTesterLayout`) and its type (`GestureTesterType`), and never clipped: the rows of what
// this touchscreen can do have heights worked out here, so whether they fit is known
// (`minimumHeight`), and where they don't they scroll, and only then.
//
// Each part reads only its own part of the window's store (`GestureTesterStore`), so a gesture's
// updates reach the feed and the fingers on the glass and nothing else. No body measures text: a
// line's height is worked out once for the window's type (`GestureTesterMetrics`).

import AppKit
import SwiftUI
import TactileGestures
import TactileScreens

/// Sizes for each arrangement, from its type.
struct GestureTesterMetrics: Equatable {
    let layout: GestureTesterLayout
    let type: GestureTesterType
    /// Around the whole window, and between its parts.
    var padding: CGFloat
    var gap: CGFloat
    var canDoWidth: CGFloat
    var feedWidth: CGFloat
    /// Inside the three parts, and inside the practice tiles.
    var panelPadding: CGFloat
    var tilePadding: CGFloat
    /// Above and below a row's lines.
    var rowPadding: CGFloat
    /// The seen badge's size; it is drawn 0.8 of it tall and 1.8 of it wide.
    var badge: CGFloat
    /// The first line of a row that holds a switch or a picker.
    var controlLine: CGFloat
    var tileIcon: CGFloat
    var controlSize: ControlSize
    var switchSize: ControlSize

    init(_ layout: GestureTesterLayout, type: GestureTesterType? = nil) {
        self.layout = layout
        self.type = type ?? GestureTesterType(layout, millimetresPerPoint: nil)
        switch layout {
        case .wide:
            padding = 8
            gap = 8
            canDoWidth = 460
            feedWidth = 280
            panelPadding = 7
            tilePadding = 7
            rowPadding = 1
            badge = 20
            controlLine = 19
            tileIcon = 22
            controlSize = .regular
            switchSize = .mini
        case .regular:
            padding = 24
            gap = 20
            canDoWidth = 620
            feedWidth = 440
            panelPadding = 16
            tilePadding = 16
            rowPadding = 4
            badge = 32
            controlLine = 26
            tileIcon = 44
            controlSize = .extraLarge
            switchSize = .regular
        }
        let type = self.type
        func line(_ size: TypeSize, weight: NSFont.Weight = .regular) -> CGFloat {
            Self.line(Self.size(size, of: type, in: layout), weight: weight)
        }
        bodyLine = line(.body)
        smallLine = line(.small)
        titleLine = line(.title, weight: .medium)
        sectionLine = line(.section, weight: .semibold)
        headingLine = line(.heading, weight: .bold)
    }

    /// The metrics for `tester`'s window in `layout`: the type sized from its display's millimetres
    /// a point, where the touchscreen's diagonal (as set, else as its display reports it) is known.
    static func forTester(
        _ tester: GestureTesterSnapshot, touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot,
        layout: GestureTesterLayout
    ) -> GestureTesterMetrics {
        GestureTesterMetrics(layout, type: type(for: tester, touchscreen: touchscreen, in: snapshot, layout: layout))
    }

    /// The type alone, which is arithmetic: the window's store compares it with the one it has before
    /// it makes its metrics again, which measures the system font.
    static func type(
        for tester: GestureTesterSnapshot, touchscreen: TouchscreenSnapshot, in snapshot: AppSnapshot,
        layout: GestureTesterLayout
    ) -> GestureTesterType {
        let display = snapshot.displays.first { $0.id == tester.displayID }
        let millimetres = GestureTesterType.millimetresPerPoint(
            points: display?.frame.size ?? .zero,
            diagonalInches: touchscreen.diagonalInches ?? touchscreen.reportedDiagonalInches)
        return GestureTesterType(layout, millimetresPerPoint: millimetres)
    }

    // MARK: Type

    /// Each size of text the window draws.
    enum TypeSize {
        case body
        /// State words, the header's explanation, the practice hint.
        case small
        case title, section, heading, tileTitle, text
    }

    /// The size, in points, of `size` text in `layout` at `type`: the one formula for it, which both
    /// the fonts and the lines measured for the rows' heights use, so that whether the rows scroll
    /// is worked out from the text as it is drawn.
    static func size(_ size: TypeSize, of type: GestureTesterType, in layout: GestureTesterLayout) -> CGFloat {
        let isWide = layout == .wide
        switch size {
        case .body: return type.body
        // The body size in the wide arrangement, a point less in the regular one.
        case .small: return isWide ? type.body : type.body - 1
        case .title: return type.title
        case .section: return type.title + (isWide ? 1 : 2)
        case .heading: return type.title + (isWide ? 2 : 9)
        case .tileTitle: return type.title + (isWide ? 0 : 1)
        case .text: return type.body + (isWide ? 1 : 3)
        }
    }

    private var isWide: Bool { layout == .wide }
    var bodySize: CGFloat { Self.size(.body, of: type, in: layout) }
    var smallSize: CGFloat { Self.size(.small, of: type, in: layout) }
    var titleSize: CGFloat { Self.size(.title, of: type, in: layout) }
    var sectionSize: CGFloat { Self.size(.section, of: type, in: layout) }
    var headingSize: CGFloat { Self.size(.heading, of: type, in: layout) }
    var tileTitleSize: CGFloat { Self.size(.tileTitle, of: type, in: layout) }
    var textSize: CGFloat { Self.size(.text, of: type, in: layout) }

    var heading: Font { .system(size: headingSize, weight: .bold) }
    var sectionTitle: Font { .system(size: sectionSize, weight: .semibold) }
    var rowTitle: Font { .system(size: titleSize, weight: .medium) }
    var rowHow: Font { .system(size: bodySize) }
    var small: Font { .system(size: smallSize) }
    var tileTitle: Font { .system(size: tileTitleSize, weight: .semibold) }
    var tileHint: Font { .system(size: bodySize) }

    /// The height of one line of the system font at `size`, as text is laid out.
    static func line(_ size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return (font.ascender - font.descender + font.leading).rounded(.up)
    }

    /// A line of each size, measured once, when the metrics are made.
    let bodyLine: CGFloat
    let smallLine: CGFloat
    let titleLine: CGFloat
    let sectionLine: CGFloat
    let headingLine: CGFloat

    // MARK: Heights

    /// The first line of a row: its title, with its switch, picker or state words beside it.
    func firstLine(_ row: GestureTesterRow) -> CGFloat {
        let beside: CGFloat
        switch row.state {
        case .on, .off, .oneFinger: beside = controlLine
        default: beside = smallLine
        }
        return max(titleLine, beside, badge * 0.8)
    }

    func rowHeight(_ row: GestureTesterRow) -> CGFloat {
        firstLine(row) + CGFloat(row.howLines) * bodyLine + 2 * rowPadding
    }

    /// Between the rows of the regular arrangement, a hairline; none in the wide one.
    var dividerHeight: CGFloat { isWide ? 0 : 1 }
    var panelSpacing: CGFloat { (gap * 0.6).rounded() }

    /// "What this touchscreen can do", every row at its height.
    func canDoHeight(_ rows: [GestureTesterRow]) -> CGFloat {
        2 * panelPadding + sectionLine + panelSpacing + rowsHeight(rows)
    }

    /// The rows alone, with the hairlines between them: whether they fit the part's height says
    /// whether they scroll.
    func rowsHeight(_ rows: [GestureTesterRow]) -> CGFloat {
        rows.map(rowHeight).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * dividerHeight
    }

    /// The header: one line in the wide arrangement; the heading over the explanation in the regular.
    var headerHeight: CGFloat {
        isWide ? max(18, headingLine, smallLine + 2) : max(42, headingLine + 4 + smallLine)
    }

    /// The least height the window's content needs to show every row without scrolling them.
    func minimumHeight(_ rows: [GestureTesterRow]) -> CGFloat {
        2 * padding + headerHeight + gap + canDoHeight(rows)
    }

    /// How wide a row's how-to may be: the row, less the seen badge.
    var howWidth: CGFloat { canDoWidth - 2 * panelPadding - badge * 1.8 - 8 }
}

struct GestureTesterView: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    init(store: GestureTesterStore, metrics: GestureTesterMetrics) {
        self.store = store
        self.metrics = metrics
    }

    /// The window's content for `tester` on `touchscreen`, as `snapshot` has them, at one moment: for
    /// drawing it, as the render tests do. The window itself keeps one store, which follows the
    /// snapshot (`GestureTesterRoot`).
    init(
        snapshot: AppSnapshot, tester: GestureTesterSnapshot, touchscreen: TouchscreenSnapshot,
        layout: GestureTesterLayout, perform: @escaping PerformCommand
    ) {
        let store = GestureTesterStore(touchscreen: touchscreen.id, layout: layout, perform: perform)
        store.show(tester, touchscreen: touchscreen, in: snapshot)
        self.init(store: store, metrics: store.metrics)
    }

    var body: some View {
        let _ = store.bodies.count(.content)
        // The height the window gives its content, which the rows' heights are held against: the
        // reader's own size is what it is offered, whatever is inside it.
        GeometryReader { space in
            VStack(alignment: .leading, spacing: metrics.gap) {
                TesterHeader(store: store, metrics: metrics)
                    .frame(height: metrics.headerHeight)
                HStack(alignment: .top, spacing: metrics.gap) {
                    CanDoPanel(store: store, metrics: metrics, height: space.size.height)
                        .frame(width: metrics.canDoWidth)
                    PracticeArea(store: store, metrics: metrics)
                        .frame(maxWidth: .infinity)
                    FeedPanel(store: store, metrics: metrics)
                        .frame(width: metrics.feedWidth)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - The header

struct TesterHeader: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    var body: some View {
        let _ = store.bodies.count(.header)
        let header = store.header
        let layout = store.layout
        let multiTouch = header.multiTouch
        HStack(alignment: .center, spacing: layout == .wide ? 10 : 16) {
            TouchscreenTile(isActive: true)
                .scaleEffect(layout == .wide ? 0.43 : 1)
                .frame(width: layout == .wide ? 18 : 42, height: layout == .wide ? 18 : 42)
            if layout == .wide {
                // One line: the window's title already says "Gesture Tester".
                Text(Wording.gestureTesterSubheading(name: header.name, displayName: header.displayName))
                    .font(metrics.heading)
                    .lineLimit(1)
                    .fixedSize()
                KindBadge(multiTouch: multiTouch, metrics: metrics)
                Text(Wording.gestureTesterKindExplanation(multiTouch: multiTouch))
                    .font(metrics.small)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Wording.gestureTesterHeading).font(metrics.heading)
                        Text(Wording.gestureTesterSubheading(name: header.name, displayName: header.displayName))
                            .font(.system(size: metrics.titleSize))
                            .foregroundStyle(.secondary)
                        KindBadge(multiTouch: multiTouch, metrics: metrics)
                    }
                    Text("\(Wording.gestureTesterKindExplanation(multiTouch: multiTouch)) \(Wording.gestureTesterDrivesForReal)")
                        .font(metrics.small)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(Wording.gestureTesterEscCloses)
                .font(metrics.small)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

struct KindBadge: View {
    var multiTouch: Bool
    var metrics: GestureTesterMetrics

    var body: some View {
        Text(Wording.gestureTesterKind(multiTouch: multiTouch))
            .font(metrics.small.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .foregroundStyle(multiTouch ? Color.white : Color.primary)
            .background(Capsule().fill(multiTouch ? Color.accentColor : Color.orange.opacity(0.35)))
            .fixedSize()
    }
}

// MARK: - A panel

/// One of the three parts: a rounded card with its title.
struct TesterPanel<Accessory: View, Content: View>: View {
    var title: String
    var metrics: GestureTesterMetrics
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.panelSpacing) {
            HStack(alignment: .center) {
                Text(title).font(metrics.sectionTitle)
                Spacer(minLength: 8)
                accessory
            }
            .frame(minHeight: metrics.sectionLine)
            content
        }
        .padding(metrics.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

// MARK: - What this touchscreen can do

/// Every row at its height, spread to fill the part when there is room; scrolled, and only then,
/// when there isn't. Whether they fit is arithmetic: the least height the window's content needs
/// for every row (`minimumHeight`) against the height it has. Nothing is measured to find out, and
/// the rows are made once. Not `ViewThatFits`: it measures the rows, and makes them again inside a
/// scroll view to measure that, on every pass of the window's layout.
struct CanDoPanel: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics
    /// The height of the window's content.
    var height: CGFloat

    var body: some View {
        let _ = store.bodies.count(.checklist)
        let checklist = store.checklist
        TesterPanel(title: Wording.gestureTesterCanDo, metrics: metrics) {
            EmptyView()
        } content: {
            if metrics.minimumHeight(checklist.rows) <= height {
                CanDoColumn(store: store, checklist: checklist, metrics: metrics)
            } else {
                // The scroller shows, so it is plain that there is more below.
                ScrollView(.vertical) { CanDoColumn(store: store, checklist: checklist, metrics: metrics) }
                    .scrollIndicators(.visible)
            }
        }
    }
}

/// The rows, each at least its worked-out height (`rowHeight`), with the hairlines between them:
/// laid out, as tall as `rowsHeight` says.
struct CanDoColumn: View {
    let store: GestureTesterStore
    var checklist: GestureTesterStore.Checklist
    var metrics: GestureTesterMetrics

    var body: some View {
        let rows = checklist.rows
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                CanDoRow(
                    store: store, row: row, rowCount: store.count(row.kind), touchscreen: checklist.touchscreen,
                    behaviour: checklist.behaviour, metrics: metrics)
                    .frame(minHeight: metrics.rowHeight(row), maxHeight: .infinity)
                if metrics.dividerHeight > 0, row.kind != rows.last?.kind {
                    Divider().opacity(0.5)
                }
            }
        }
    }
}

struct CanDoRow: View {
    let store: GestureTesterStore
    var row: GestureTesterRow
    /// Read here, and only here: a gesture seen draws its own row again, and no other.
    let rowCount: GestureTesterRowCount
    var touchscreen: TouchscreenID
    var behaviour: BehaviourSnapshot?
    var metrics: GestureTesterMetrics

    private var isDimmed: Bool {
        switch row.state {
        case .needsMoreThanOneFinger, .notOnThisMac, .needsSwipes, .off: return true
        case .edgeOnly(let millimetres): return millimetres <= 0
        default: return false
        }
    }

    var body: some View {
        let _ = store.bodies.count(.row)
        let count = rowCount.value
        let title = Wording.gestureTesterRowTitle(row)
        let how = behaviour.map { Wording.gestureTesterRowHow(row, behaviour: $0) } ?? ""
        let first = metrics.firstLine(row)
        HStack(alignment: .top, spacing: 8) {
            SeenBadge(count: count, size: metrics.badge)
                .frame(height: first)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(metrics.rowTitle)
                        .foregroundStyle(isDimmed ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    state(behaviour)
                }
                .frame(height: first)
                if row.howLines > 0 {
                    Text(how)
                        .font(metrics.rowHow)
                        .foregroundStyle(row.cannotHappenHere ? .tertiary : .secondary)
                        .lineLimit(row.howLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(how)
                }
            }
        }
        .padding(.vertical, metrics.rowPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(Wording.gestureTesterSeen(count))
    }

    @ViewBuilder private func state(_ behaviour: BehaviourSnapshot?) -> some View {
        switch row.state {
        case .on, .off:
            Toggle(Wording.gestureTesterRowTitle(row), isOn: Binding(
                get: { row.state == .on },
                set: { [store, row, touchscreen] on in
                    if let behaviour,
                        let command = GestureTesterRow.command(row.kind, on: on, for: touchscreen, behaviour: behaviour)
                    {
                        store.perform(command)
                    }
                }))
                .toggleStyle(.switch)
                .controlSize(metrics.switchSize)
                .labelsHidden()
                .disabled(!row.isEnabled)
        case .oneFinger:
            // The pane's picker (`OneFingerPicker`): its options, the default first, its titles and
            // its commands.
            if let picker = row.oneFingerPicker {
                Picker(Wording.oneFingerLabel, selection: Binding(
                    get: { picker.choice },
                    set: { [store, touchscreen] option in picker.command(option, for: touchscreen).map { store.perform($0) } }
                )) {
                    ForEach(OneFingerPicker.options, id: \.self) { option in
                        Text(picker.title(option)).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(metrics.switchSize == .mini ? .small : .regular)
                .fixedSize()
                .disabled(!row.isEnabled)
            }
        case .always, .needsMoreThanOneFinger, .notOnThisMac, .needsSwipes, .edgeOnly:
            if let words = Wording.gestureTesterState(row.state) {
                Text(words)
                    .font(metrics.small)
                    .foregroundStyle(row.state == .always ? .secondary : .tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// A row's tick and count: a dashed ring until it is seen, then a green tick and how many.
struct SeenBadge: View {
    var count: Int
    var size: CGFloat

    var body: some View {
        Group {
            if count > 0 {
                HStack(spacing: size * 0.08) {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.36, weight: .heavy))
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: size * 0.46, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, size * 0.24)
                .frame(minWidth: size * 0.8, minHeight: size * 0.8)
                .background(Capsule().fill(Color.green))
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(width: size * 0.8, height: size * 0.8)
            }
        }
        .frame(width: size * 1.8, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - What Tactile saw

struct FeedPanel: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    init(store: GestureTesterStore, metrics: GestureTesterMetrics) {
        self.store = store
        self.metrics = metrics
    }

    /// The feed of `tester` alone, at one moment: for drawing it, as the render tests do.
    init(tester: GestureTesterSnapshot, metrics: GestureTesterMetrics, perform: @escaping PerformCommand) {
        let store = GestureTesterStore(touchscreen: tester.touchscreen, layout: metrics.layout, perform: perform)
        store.showFeed(tester)
        self.init(store: store, metrics: metrics)
    }

    var body: some View {
        let _ = store.bodies.count(.feed)
        TesterPanel(title: Wording.gestureTesterSaw, metrics: metrics) {
            Button(Wording.gestureTesterClear) { store.perform(.clearGestureTester) }
                .controlSize(metrics.switchSize == .mini ? .small : .regular)
                .disabled(!store.canClear)
        } content: {
            FingersNow(store: store, metrics: metrics)
            Divider()
            FeedList(store: store, metrics: metrics)
        }
    }
}

/// The entries, newest first: drawn again when they change, and nothing else is. A new entry comes
/// in without an animation.
struct FeedList: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    var body: some View {
        let _ = store.bodies.count(.feedList)
        let recent = store.recent
        if recent.isEmpty {
            Text(Wording.gestureTesterNothingYet)
                .font(metrics.rowHow)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(recent) { gesture in
                        FeedEntry(gesture: gesture, isNewest: gesture.id == recent.first?.id, metrics: metrics)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
    }
}

/// The fingers on the glass now: a dot for each, and the number.
struct FingersNow: View {
    let store: GestureTesterStore
    var metrics: GestureTesterMetrics

    var body: some View {
        let _ = store.bodies.count(.fingers)
        let count = store.fingersDown
        HStack(spacing: 8) {
            Text(Wording.gestureTesterFingersNow)
                .font(metrics.rowHow)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(0..<max(count, 1), id: \.self) { index in
                    Circle()
                        .fill(index < count ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: metrics.badge * 0.42, height: metrics.badge * 0.42)
                }
            }
            Text("\(count)")
                .font(metrics.rowTitle.monospacedDigit())
                .frame(minWidth: 16, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Wording.gestureTesterFingersNow)
        .accessibilityValue("\(count)")
    }
}

struct FeedEntry: View {
    var gesture: RecognisedGesture
    var isNewest: Bool
    var metrics: GestureTesterMetrics

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: GestureSymbol.name(gesture.kind))
                .font(metrics.rowTitle)
                .foregroundStyle(GestureSymbol.isQuiet(gesture.kind) ? Color.secondary : Color.accentColor)
                .frame(width: metrics.badge, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Wording.recognisedGesture(gesture.kind))
                        .font(metrics.rowTitle)
                    if let fingers = Wording.fingers(gesture.fingers) {
                        Text(fingers)
                            .font(metrics.small)
                            .foregroundStyle(.secondary)
                    }
                }
                if !gesture.summary.isEmpty {
                    Text(gesture.summary)
                        .font(metrics.rowHow)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, metrics.rowPadding + 1)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(isNewest ? Color.accentColor.opacity(0.12) : .clear))
        .accessibilityElement(children: .combine)
    }
}

/// The symbol beside each kind in the feed.
enum GestureSymbol {
    static func name(_ kind: RecognisedGesture.Kind) -> String {
        switch kind {
        case .tap: return "hand.tap"
        case .doubleTap, .tripleTap: return "hand.tap.fill"
        case .drag: return "hand.draw"
        case .holdThenDrag: return "hand.point.up.left"
        case .scroll: return "arrow.up.and.down"
        case .flick: return "wind"
        case .pinch: return "arrow.up.left.and.arrow.down.right"
        case .rotate: return "arrow.triangle.2.circlepath"
        case .rightClick: return "contextualmenu.and.cursorarrow"
        case .swipe: return "rectangle.on.rectangle"
        case .followedSwipe: return "rectangle.portrait.on.rectangle.portrait"
        case .ignored: return "hand.raised.slash"
        case .cancelled: return "xmark.circle"
        }
    }

    /// What Tactile didn't act on is drawn quieter.
    static func isQuiet(_ kind: RecognisedGesture.Kind) -> Bool {
        kind == .ignored || kind == .cancelled
    }
}
