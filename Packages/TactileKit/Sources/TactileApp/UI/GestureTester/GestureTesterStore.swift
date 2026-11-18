// What the tester's window shows, kept apart by the part that shows it, so that each part is
// worked out again only when its own part changes. The window's observer (`GestureTesterFollower`)
// hands it every snapshot; it sets each of its properties only when that property's value differs.
//
// While a gesture goes on the model publishes the tester up to ten times a second, and again each
// time the fingers on the glass change. Only the feed (`recent`) and the fingers (`fingersDown`)
// change then: the checklist and the practice area read neither, so they are not drawn again, and
// their scroll views are not laid out again while a person scrolls them. A row's count changes when
// a gesture is first seen, and then only that row is drawn again (`GestureTesterRowCount`).

import Foundation
import Observation
import TactileGestures
import TactileScreens

@MainActor
@Observable
final class GestureTesterStore {
    /// The header's words.
    struct Header: Equatable {
        var name = ""
        var displayName: String?
        var multiTouch = false
    }

    /// "What this touchscreen can do": its rows, and what their switches and pickers need.
    struct Checklist: Equatable {
        var touchscreen: TouchscreenID
        var behaviour: BehaviourSnapshot?
        var rows: [GestureTesterRow] = []
    }

    /// What the practice tiles say: nothing in it changes while a gesture goes on.
    struct Practice: Equatable {
        var multiTouch = false
        var oneFinger = OneFingerMode.automatic
        var reportsPalms = false
        var edgeMarginMM = 0.0
    }

    /// The swipes tile: whether swipes are let through, and the last one the feed has.
    struct Swipes: Equatable {
        var performsSwipes = false
        var lastSwipe: String?
    }

    /// The touchscreen whose tester the window is for, and its arrangement: fixed for the window.
    @ObservationIgnored let touchscreen: TouchscreenID
    @ObservationIgnored let layout: GestureTesterLayout
    /// How many times each part has worked out its body, for the tests that hold the parts apart.
    @ObservationIgnored let bodies = GestureTesterBodies()
    @ObservationIgnored private let send: PerformCommand
    /// The feed as followed so far, for the rows that count by fingers.
    @ObservationIgnored private var tally = GestureTally()
    @ObservationIgnored private let counts: [GestureTesterRow.Kind: GestureTesterRowCount]

    /// The tester is open for this touchscreen, and the touchscreen is in the snapshot.
    private(set) var isShown = false
    private(set) var metrics: GestureTesterMetrics
    private(set) var header = Header()
    private(set) var checklist: Checklist
    private(set) var practice = Practice()
    private(set) var swipes = Swipes()
    /// What the feed says Tactile ignored: palms, the edge, a second finger.
    private(set) var palmIgnored = 0
    private(set) var fingersDown = 0
    /// Newest first.
    private(set) var recent: [RecognisedGesture] = []
    /// Clear has something to clear.
    private(set) var canClear = false

    init(touchscreen: TouchscreenID, layout: GestureTesterLayout, perform: @escaping PerformCommand) {
        self.touchscreen = touchscreen
        self.layout = layout
        send = perform
        metrics = GestureTesterMetrics(layout)
        checklist = Checklist(touchscreen: touchscreen)
        counts = Dictionary(uniqueKeysWithValues: GestureTesterRow.Kind.allCases.map { ($0, GestureTesterRowCount()) })
    }

    /// The window's store, showing `snapshot` at once.
    convenience init(
        touchscreen: TouchscreenID, layout: GestureTesterLayout, snapshot: AppSnapshot, perform: @escaping PerformCommand
    ) {
        self.init(touchscreen: touchscreen, layout: layout, perform: perform)
        update(snapshot)
    }

    /// Sends a command to the model.
    func perform(_ command: AppCommand) {
        send(command)
    }

    /// The count shown on `kind`'s row.
    func count(_ kind: GestureTesterRow.Kind) -> GestureTesterRowCount {
        counts[kind] ?? GestureTesterRowCount()
    }

    /// Follows the model's snapshot: the tester it has for this touchscreen, or none.
    func update(_ snapshot: AppSnapshot) {
        guard let tester = snapshot.gestureTester, tester.touchscreen == touchscreen,
            let shown = snapshot.touchscreens.first(where: { $0.id == touchscreen })
        else {
            tally.follow(nil)
            set(\.isShown, false)
            return
        }
        show(tester, touchscreen: shown, in: snapshot)
    }

    /// `tester` for `touchscreen` in `snapshot`, each part set only where it changed.
    func show(_ tester: GestureTesterSnapshot, touchscreen shown: TouchscreenSnapshot, in snapshot: AppSnapshot) {
        let behaviour = shown.behaviour
        let multiTouch = tester.multiTouch && behaviour.multiFingerAvailable
        let type = GestureTesterMetrics.type(for: tester, touchscreen: shown, in: snapshot, layout: layout)
        if metrics.type != type {
            metrics = GestureTesterMetrics(layout, type: type)
        }
        let displayName = snapshot.displays.first { $0.id == tester.displayID }?.name ?? shown.pairedDisplayName
        set(\.header, Header(name: tester.touchscreenName, displayName: displayName, multiTouch: multiTouch))
        let rows = GestureTesterRow.rows(
            for: shown, multiTouch: multiTouch, swipesFollowFingers: snapshot.swipesFollowFingers,
            canFollowSwipes: snapshot.canFollowSwipes)
        set(\.checklist, Checklist(touchscreen: shown.id, behaviour: behaviour, rows: rows))
        set(\.practice, Practice(
            multiTouch: multiTouch, oneFinger: behaviour.oneFinger, reportsPalms: behaviour.reportsPalms,
            edgeMarginMM: behaviour.rejection.edgeMarginMM))
        showFeed(tester)
        for row in rows {
            count(row.kind).set(row.count(seen: tester.seen, tally: tally))
        }
        set(\.isShown, true)
    }

    /// The feed's parts alone: the swipes tile's last swipe, the ignored count, the fingers, the
    /// entries, and whether Clear can be used.
    func showFeed(_ tester: GestureTesterSnapshot) {
        tally.follow(tester)
        let lastSwipe = tester.recent.first { $0.kind == .swipe || $0.kind == .followedSwipe }?.summary
        set(\.swipes, Swipes(performsSwipes: tester.performsSwipes, lastSwipe: lastSwipe))
        set(\.palmIgnored, tester.seen.first { $0.id == .ignored }?.count ?? 0)
        set(\.fingersDown, tester.fingersDown)
        set(\.recent, tester.recent)
        set(\.canClear, !(tester.recent.isEmpty && tester.seen.isEmpty))
    }

    /// Sets a property only when its value differs, so that what reads it is told only then.
    private func set<Value: Equatable>(_ property: ReferenceWritableKeyPath<GestureTesterStore, Value>, _ value: Value) {
        if self[keyPath: property] != value {
            self[keyPath: property] = value
        }
    }
}

/// One row's count, on its own, so that a gesture seen draws only its row again.
@MainActor
@Observable
final class GestureTesterRowCount {
    private(set) var value = 0

    func set(_ count: Int) {
        if value != count { value = count }
    }
}

/// How many times each part of the tester's window has worked out its body: counted, never read by
/// the window itself, for the tests that show a gesture's updates reach only the feed.
@MainActor
final class GestureTesterBodies {
    enum Part: CaseIterable {
        case root, content, header, checklist, row, practice, swipes, palm, feed, feedList, fingers
    }

    private var counts: [Part: Int] = [:]

    func count(_ part: Part) {
        counts[part, default: 0] += 1
    }

    subscript(_ part: Part) -> Int { counts[part] ?? 0 }

    /// Every part's count, for a test's message.
    var all: [Part: Int] { counts }

    func reset() {
        counts = [:]
    }
}
