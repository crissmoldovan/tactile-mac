import AppKit
import SwiftUI
import TactileScreens
import XCTest

@testable import TactileApp

/// A touchscreen's details open as a native submenu does, as the pointer goes: resting on a row opens
/// them, or moves them there; leaving their row changes nothing at once, so the pointer can get to
/// them; another item in the menu closes them once the pointer has stayed there a moment; the details
/// themselves, their own row and empty screen keep them up; a click shows them and never closes them.
/// The clock is the test's; nothing is drawn in a window, and no event is posted.
@MainActor
final class MenuDetailsHoverTests: XCTestCase {

    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip

    private let openDelay = MenuDetailsHover.openDelay
    private let grace = MenuDetailsHover.grace

    // MARK: - Opening

    /// The pointer resting on a row opens its details after a short delay, the delay a native menu
    /// waits before opening a submenu.
    func testThePointerRestingOnARowOpensItsDetailsAfterAShortDelay() {
        XCTAssert((0.1...0.15).contains(openDelay), "\(openDelay)")
        XCTAssert((0.3...0.5).contains(grace), "\(grace)")

        var menu = HoverMenu()
        menu.move(to: HoverMenu.onSettings)
        menu.move(to: HoverMenu.onIlitek)
        XCTAssertEqual(menu.hover.nextLook, menu.now + openDelay, "looks again when the delay is over")
        menu.wait(openDelay - 0.01)
        XCTAssertNil(menu.shown, "not before the delay")
        menu.wait(0.02)
        XCTAssertEqual(menu.shown, ilitek)
        XCTAssertEqual(menu.log, [.show(ilitek)])
        XCTAssertNil(menu.hover.nextLook, "nothing more to wait for")
    }

    /// Passing over a row on the way somewhere else opens nothing.
    func testPassingOverARowOpensNothing() {
        var menu = HoverMenu()
        menu.move(to: HoverMenu.onIlitek)
        menu.wait(openDelay / 2)
        menu.move(to: HoverMenu.onSettings)
        menu.wait(1)
        menu.move(to: HoverMenu.onStrip)
        menu.wait(openDelay / 2)
        menu.move(to: HoverMenu.emptyScreen)
        menu.wait(1)
        XCTAssertNil(menu.shown)
        XCTAssertEqual(menu.log, [])
    }

    /// Moving about on the row doesn't put the details off: the delay runs from coming onto it.
    func testMovingAboutOnTheRowDoesNotPutTheDetailsOff() {
        var menu = HoverMenu()
        menu.move(to: HoverMenu.onIlitek)
        menu.wait(openDelay / 3)
        menu.move(to: CGPoint(x: 1100, y: 1290))
        menu.wait(openDelay / 3)
        menu.move(to: CGPoint(x: 1050, y: 1282))
        menu.wait(openDelay / 3 + 0.005)
        XCTAssertEqual(menu.shown, ilitek)
    }

    // MARK: - Moving to another row

    /// From the row whose details are up straight down onto the next: the details move there after
    /// the same short delay, as they would open.
    func testMovingDownOntoAnotherRowMovesTheDetailsThereAfterTheShortDelay() throws {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.glide(to: HoverMenu.onStrip, in: 0.1)
        let arrived = try XCTUnwrap(menu.arrival(at: .row(strip)))
        menu.wait(until: arrived + openDelay - 0.005)
        XCTAssertEqual(menu.shown, ilitek, "not before the delay")
        menu.wait(0.01)
        XCTAssertEqual(menu.shown, strip)
        XCTAssertEqual(menu.log, [.show(ilitek), .show(strip)], "moved, with nothing closed first")
    }

    /// A slow, steady move from the row toward its details, across the next row and the menu below
    /// it, longer on each than the delay and the grace: the details stay where they are all the way,
    /// as a native submenu does for a pointer heading into it.
    func testHeadingForTheDetailsAcrossAnotherRowKeepsThem() throws {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.glide(to: HoverMenu.inIlitekDetails, in: 2) { menu in
            XCTAssertEqual(menu.shown, ilitek, "at \(menu.point)")
        }
        let onStrip = try XCTUnwrap(menu.arrival(at: .row(strip)))
        let below = try XCTUnwrap(menu.arrival(at: .menu))
        XCTAssertGreaterThan(below - onStrip, grace, "on the strip's row longer than the grace")
        XCTAssertNotNil(menu.arrival(at: .details), "got there")
        menu.wait(2)
        XCTAssertEqual(menu.shown, ilitek)
        XCTAssertEqual(menu.log, [.show(ilitek)])
    }

    /// Heading for the details and stopping on the next row on the way: once the pointer has not
    /// headed there for the grace, the details move to the row it rests on.
    func testStoppingOnAnotherRowOnTheWayMovesTheDetailsThereOnceTheGraceIsOver() {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.glide(to: CGPoint(x: 1250, y: 1262), in: 0.2)
        XCTAssertEqual(menu.place, .row(strip))
        XCTAssertEqual(menu.hover.nextLook ?? 0, menu.now + grace, accuracy: 0.001, "put off while it headed there")
        menu.wait(grace - 0.01)
        XCTAssertEqual(menu.shown, ilitek, "well past the short delay, not yet past the grace")
        menu.wait(0.02)
        XCTAssertEqual(menu.shown, strip)
    }

    /// A hand's wobble is not a direction: a twitch toward the details on the way down to the next
    /// row doesn't count as heading for them, and the details move after the short delay.
    func testATwitchOnTheWayDownIsNotTakenForHeadingToTheDetails() throws {
        var menu = HoverMenu()
        menu.open(ilitek, at: CGPoint(x: 1170, y: 1279))
        for point in [
            CGPoint(x: 1170, y: 1278), CGPoint(x: 1171, y: 1278),  // the twitch: one point toward the details
            CGPoint(x: 1171, y: 1277), CGPoint(x: 1171, y: 1276), CGPoint(x: 1171, y: 1275),
            CGPoint(x: 1171, y: 1274),
        ] {
            menu.wait(1.0 / 120)
            menu.move(to: point)
        }
        let arrived = try XCTUnwrap(menu.arrival(at: .row(strip)))
        menu.wait(until: arrived + openDelay + 0.005)
        XCTAssertEqual(menu.shown, strip)
    }

    /// Back on their own row before the delay is over: the details stay, and nothing else happens.
    func testBackOnTheirOwnRowTheDetailsStay() {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.move(to: HoverMenu.onStrip)
        menu.wait(openDelay / 2)
        menu.move(to: HoverMenu.onIlitek)
        menu.wait(2)
        XCTAssertEqual(menu.shown, ilitek)
        XCTAssertEqual(menu.log, [.show(ilitek)])
    }

    // MARK: - Getting to the details

    /// Out of the row, across the menu's margin and the gap between the windows, into the details:
    /// they stay up, however long the pointer then stays in them.
    func testReachingTheDetailsKeepsThemUp() {
        var menu = HoverMenu()
        menu.open(ilitek)
        for point in [HoverMenu.inMargin, HoverMenu.inGap, HoverMenu.inIlitekDetails] {
            menu.wait(0.05)
            menu.move(to: point)
        }
        XCTAssertNil(menu.hover.nextLook)
        menu.wait(5)
        XCTAssertEqual(menu.shown, ilitek)

        // Straight from the menu into them, the gap jumped in one move: the close waiting goes.
        menu.move(to: HoverMenu.inMargin)
        XCTAssertNotNil(menu.hover.nextLook)
        menu.wait(grace / 2)
        menu.move(to: HoverMenu.inIlitekDetails)
        XCTAssertNil(menu.hover.nextLook)
        menu.wait(5)
        XCTAssertEqual(menu.log, [.show(ilitek)])
    }

    // MARK: - Leaving them

    /// From their row, or from the details, onto another item in the menu (Settings…): the details
    /// close once the pointer has stayed off them for the grace.
    func testAnotherItemInTheMenuClosesTheDetailsOnceTheGraceIsOver() {
        for from in [HoverMenu.onIlitek, HoverMenu.inIlitekDetails] {
            var menu = HoverMenu()
            menu.open(ilitek)
            menu.move(to: from)
            menu.wait(0.5)
            menu.move(to: HoverMenu.onSettings)
            menu.wait(grace - 0.01)
            XCTAssertEqual(menu.shown, ilitek, "from \(from): not before the grace")
            menu.wait(0.02)
            XCTAssertNil(menu.shown, "from \(from)")
            XCTAssertEqual(menu.log, [.show(ilitek), .close])
        }
    }

    /// From the details back into the menu onto another row: the details move there after the short
    /// delay, as from a row.
    func testFromTheDetailsOntoAnotherRowTheDetailsMoveAfterTheShortDelay() throws {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.move(to: HoverMenu.inIlitekDetails)
        menu.wait(1)
        for point in [HoverMenu.inGap, HoverMenu.inMargin, HoverMenu.onStrip] {
            menu.wait(0.01)
            menu.move(to: point)
        }
        let arrived = try XCTUnwrap(menu.arrival(at: .row(strip)))
        menu.wait(until: arrived + openDelay - 0.005)
        XCTAssertEqual(menu.shown, ilitek)
        menu.wait(0.01)
        XCTAssertEqual(menu.shown, strip)
        XCTAssertEqual(menu.log, [.show(ilitek), .show(strip)])
    }

    /// Out of the menu and the details onto empty screen: the details stay up, as a native submenu
    /// does, even from another item whose close was waiting.
    func testEmptyScreenKeepsTheDetailsUp() {
        for path in [
            [HoverMenu.inIlitekDetails, HoverMenu.emptyScreen],
            [HoverMenu.onSettings, HoverMenu.leftOfTheMenu],
            [HoverMenu.onStrip, HoverMenu.leftOfTheMenu],
        ] {
            var menu = HoverMenu()
            menu.open(ilitek)
            for point in path {
                menu.wait(0.05)
                menu.move(to: point)
            }
            XCTAssertNil(menu.hover.nextLook, "\(path)")
            menu.wait(5)
            XCTAssertEqual(menu.shown, ilitek, "\(path)")
        }
    }

    // MARK: - Clicks, Esc and the rest

    /// A touch moves the pointer onto a row and clicks it at once: the click shows the details, and
    /// the delay that began as the pointer came onto the row does nothing more. A click on the row
    /// whose details are up keeps them up; it never closes them.
    func testAClickShowsTheDetailsAndNeverClosesThem() {
        var menu = HoverMenu()
        menu.move(to: HoverMenu.onStrip)
        menu.click(strip)
        XCTAssertEqual(menu.shown, strip)
        menu.wait(2)
        XCTAssertEqual(menu.log, [.show(strip)], "the delay's end found them up already")

        // Resting on it, then clicking it: they stay up.
        menu.move(to: HoverMenu.onIlitek)
        menu.wait(openDelay + 0.01)
        menu.click(ilitek)
        menu.click(ilitek)
        XCTAssertEqual(menu.shown, ilitek)
        menu.wait(2)
        XCTAssertFalse(menu.log.contains(.close), "\(menu.log)")
    }

    /// Choosing a row (a click, a tap, Return) shows its details: opens them, moves them there, or
    /// keeps them up when they are its.
    func testChoosingARowAlwaysShowsItsDetails() {
        var presenter = MenuDetailsPresenter()
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek))
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek), "again: kept up")
        XCTAssertEqual(presenter.shown, ilitek)
        XCTAssertEqual(presenter.chosen(strip), .show(strip))
        XCTAssertEqual(presenter.shown, strip)
    }

    /// Esc, a click elsewhere in the menu or the menu closing closes the details, and what was
    /// waiting goes with them; the pointer still on the row doesn't bring them back until it comes
    /// onto a row again.
    func testClosingDropsWhatWasWaiting() {
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.move(to: HoverMenu.onStrip)
        menu.close()
        XCTAssertNil(menu.hover.nextLook)
        menu.wait(2)
        XCTAssertNil(menu.shown)

        menu.move(to: CGPoint(x: 1100, y: 1262))
        menu.wait(2)
        XCTAssertNil(menu.shown, "still on the same row")
        menu.move(to: HoverMenu.onIlitek)
        menu.wait(openDelay + 0.01)
        XCTAssertEqual(menu.shown, ilitek, "onto a row again")
    }

    /// A decision whose time has come when the pointer moves again, before the timer has fired, is
    /// taken first, and the move is then judged with it taken.
    func testADecisionAlreadyDueIsTakenFirst() {
        var hover = MenuDetailsHover()
        let start: TimeInterval = 50
        XCTAssertNil(hover.pointer(.row(strip), at: HoverMenu.onStrip, time: start, shown: nil, details: nil))
        let late = start + openDelay + 0.05
        XCTAssertEqual(
            hover.pointer(.menu, at: HoverMenu.onSettings, time: late, shown: nil, details: nil), .show(strip),
            "the pointer rested on the strip's row for the delay")
        XCTAssertEqual(hover.nextLook ?? 0, late + grace, accuracy: 0.0001, "and has now left it for another item")
        XCTAssertEqual(hover.pending?.action, .close)

        // As the window runs it: a close already due, then the pointer onto another row; the close is
        // taken, and that row's details open after the delay all the same.
        var menu = HoverMenu()
        menu.open(ilitek)
        menu.move(to: HoverMenu.onSettings)
        menu.now += grace + 0.05
        menu.move(to: HoverMenu.onStrip)
        XCTAssertNil(menu.shown)
        menu.wait(openDelay + 0.01)
        XCTAssertEqual(menu.shown, strip)
        XCTAssertEqual(menu.log, [.show(ilitek), .close, .show(strip)])
    }

    // MARK: - Where the pointer is, and which way it goes

    /// The details are over everything; then a row; then the rest of the menu; then nothing of ours.
    func testWhereThePointerIs() {
        let details = HoverMenu.detailsFrame(for: ilitek)
        func place(_ point: CGPoint, details: CGRect? = details) -> MenuDetailsHover.Place {
            MenuDetailsHover.place(of: point, details: details, rows: HoverMenu.rows, menu: HoverMenu.menuFrame)
        }
        XCTAssertEqual(place(HoverMenu.onIlitek), .row(ilitek))
        XCTAssertEqual(place(HoverMenu.onStrip), .row(strip))
        XCTAssertEqual(place(HoverMenu.onSettings), .menu)
        XCTAssertEqual(place(HoverMenu.inMargin), .menu)
        XCTAssertEqual(place(HoverMenu.inGap), .away)
        XCTAssertEqual(place(HoverMenu.inIlitekDetails), .details)
        XCTAssertEqual(place(HoverMenu.inIlitekDetails, details: nil), .away, "no details up")
        XCTAssertEqual(place(HoverMenu.emptyScreen), .away)
        // Details pushed over the menu by the screen's edge are on top of it.
        let overlapping = CGRect(x: 1100, y: 1046, width: 300, height: 260)
        XCTAssertEqual(place(HoverMenu.onIlitek, details: overlapping), .details)
    }

    /// A move heads for the details when it goes into the triangle from where it began to the ends
    /// of their edge facing it, on whichever side of the menu they are.
    func testAMoveHeadsForTheDetailsInsideTheTriangleToTheirNearEdge() {
        let right = CGRect(x: 1340, y: 1046, width: 300, height: 260)
        let start = CGPoint(x: 1170, y: 1288)
        func heads(_ end: CGPoint, from start: CGPoint = start, to details: CGRect = right) -> Bool {
            MenuDetailsHover.isHeading(from: start, to: end, toward: details)
        }
        XCTAssertTrue(heads(CGPoint(x: 1180, y: 1286)), "right, a little down")
        XCTAssertTrue(heads(CGPoint(x: 1180, y: 1288.5)), "right, a little up: their top is above")
        XCTAssertTrue(heads(CGPoint(x: 1200, y: 1250)), "down and right, toward their lower part")
        XCTAssertFalse(heads(CGPoint(x: 1160, y: 1288)), "away from them")
        XCTAssertFalse(heads(CGPoint(x: 1170, y: 1278)), "straight down")
        XCTAssertFalse(heads(CGPoint(x: 1172, y: 1270)), "mostly down")
        XCTAssertFalse(heads(CGPoint(x: 1180, y: 1300)), "up past their top")
        XCTAssertFalse(heads(start), "no move")
        // Close to their edge, the triangle is wide: a steep move toward their lower part still heads there.
        XCTAssertTrue(heads(CGPoint(x: 1331, y: 1278), from: CGPoint(x: 1330, y: 1288)))

        // On the left of the menu.
        let left = CGRect(x: 696, y: 1046, width: 300, height: 260)
        XCTAssertTrue(heads(CGPoint(x: 1090, y: 1286), from: CGPoint(x: 1100, y: 1288), to: left))
        XCTAssertFalse(heads(CGPoint(x: 1110, y: 1286), from: CGPoint(x: 1100, y: 1288), to: left))
        // Level with them across: neither edge faces the pointer.
        XCTAssertFalse(heads(CGPoint(x: 1410, y: 1330), from: CGPoint(x: 1400, y: 1340), to: right))
    }

    // MARK: - Following the pointer

    /// Each row, the whole menu and the details' window follow the pointer coming onto them and
    /// leaving them, whichever window is key, their areas kept to what is visible of them; the menu
    /// follows its moves too, for which way it goes. The menu's area never takes a click.
    func testTheRowsTheMenuAndTheDetailsFollowThePointer() throws {
        let tracked: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let row = RowAnchorView(frame: CGRect(x: 0, y: 0, width: 324, height: 24))
        let menu = MenuPointerView(frame: CGRect(x: 0, y: 0, width: 336, height: 400))
        let details = DetailsBackgroundView(frame: CGRect(x: 0, y: 0, width: 300, height: 260))
        for (name, view, options) in [
            ("row", row as NSView, tracked), ("menu", menu, tracked.union(.mouseMoved)), ("details", details, tracked),
        ] {
            XCTAssertEqual(view.trackingAreas.count, 1, name)
            let area = try XCTUnwrap(view.trackingAreas.first, name)
            XCTAssertEqual(area.options, options, name)
            XCTAssert(area.owner === view, name)
        }
        XCTAssertNil(menu.hitTest(CGPoint(x: 100, y: 100)), "the menu's area is behind its content, and takes no click")
    }

    /// The panel as drawn: its whole width followed; each row able to show its own details beside it,
    /// as a click on it does, through the panel's own `choose`. Drawn in a hosting view with no window.
    func testEachRowShowsItsOwnDetailsAsAClickOnItDoes() throws {
        _ = NSApplication.shared
        let content = MenuBarContent(UIFixtures.desk)
        var chosen: [(TouchscreenID, NSView?)] = []
        let host = NSHostingView(rootView: MenuBarPanel(
            content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {},
            choose: { id, anchor in chosen.append((id, anchor)) }))
        host.frame = NSRect(x: 0, y: 0, width: MenuBarPanel.width, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        let areas = views(MenuPointerView.self, in: host)
        XCTAssertEqual(areas.count, 1)
        let area = try XCTUnwrap(areas.first)
        XCTAssertEqual(area.frame.width, MenuBarPanel.width, accuracy: 0.5, "the whole panel, its margins too")

        let anchors = views(RowAnchorView.self, in: host)
        XCTAssertEqual(anchors.compactMap(\.id), content.touchscreens.map(\.id))
        for anchor in anchors {
            anchor.choose?(anchor)
        }
        XCTAssertEqual(chosen.map(\.0), content.touchscreens.map(\.id))
        for ((_, view), anchor) in zip(chosen, anchors) {
            XCTAssert(view === anchor, "beside its own row")
        }
    }

    /// A row lights under the pointer, and while its details are up; not under the pointer while
    /// another row's details are up, so that one row is lit at a time, the one whose details are up,
    /// as a submenu's item stays lit while the pointer heads for it.
    func testARowLightsUnderThePointerUnlessAnotherRowsDetailsAreUp() {
        XCTAssertFalse(PanelTouchscreenRow.isLit(ilitek, hovered: false, detailsShown: nil))
        XCTAssertTrue(PanelTouchscreenRow.isLit(ilitek, hovered: true, detailsShown: nil))
        XCTAssertTrue(PanelTouchscreenRow.isLit(ilitek, hovered: false, detailsShown: ilitek))
        XCTAssertTrue(PanelTouchscreenRow.isLit(ilitek, hovered: true, detailsShown: ilitek))
        XCTAssertFalse(PanelTouchscreenRow.isLit(strip, hovered: true, detailsShown: ilitek))
        XCTAssertFalse(PanelTouchscreenRow.isLit(strip, hovered: false, detailsShown: ilitek))
    }

    private func views<View: NSView>(_ type: View.Type, in top: NSView) -> [View] {
        var found: [View] = []
        var stack = [top]
        while let view = stack.popLast() {
            if let match = view as? View {
                found.append(match)
            }
            stack.append(contentsOf: view.subviews.reversed())
        }
        return found
    }
}

/// The menu as `TouchscreenDetailsWindow` drives it, on the test's clock: where the pointer is goes
/// to the hover rule, what it decides goes to the presenter as the window would take it, and the
/// timer fires when the rule asks to look again. On a screen whose y grows upwards: the menu, the
/// ILITEK's row with the strip's right beneath it, Settings… further down, and the details on the
/// menu's right, their top level with their row's, hanging down past the strip's.
private struct HoverMenu {
    static let menuFrame = CGRect(x: 1000, y: 900, width: 336, height: 500)
    static let rows = [
        MenuDetailsWatch.Row(id: UIFixtures.ilitek, frame: CGRect(x: 1006, y: 1276, width: 324, height: 24)),
        MenuDetailsWatch.Row(id: UIFixtures.strip, frame: CGRect(x: 1006, y: 1252, width: 324, height: 24)),
    ]

    static let onIlitek = CGPoint(x: 1170, y: 1288)
    static let onStrip = CGPoint(x: 1170, y: 1264)
    static let onSettings = CGPoint(x: 1170, y: 960)
    /// The menu's margin, right of the strip's row.
    static let inMargin = CGPoint(x: 1333, y: 1264)
    /// Between the menu and the details.
    static let inGap = CGPoint(x: 1338, y: 1264)
    static let inIlitekDetails = CGPoint(x: 1450, y: 1200)
    static let emptyScreen = CGPoint(x: 1800, y: 1200)
    static let leftOfTheMenu = CGPoint(x: 900, y: 1100)

    /// Beside the menu, their top 6 points above their row's.
    static func detailsFrame(for id: TouchscreenID) -> CGRect {
        let row = rows.first { $0.id == id }!.frame
        return CGRect(x: 1340, y: row.maxY + 6 - 260, width: 300, height: 260)
    }

    var presenter = MenuDetailsPresenter()
    var hover = MenuDetailsHover()
    var now: TimeInterval = 1000
    var point = CGPoint(x: 1170, y: 1420)
    /// What was done to the details, in order.
    var log: [MenuDetailsPresenter.Action] = []
    /// Each place the pointer came to, and when.
    var arrivals: [(MenuDetailsHover.Place, TimeInterval)] = []

    var shown: TouchscreenID? { presenter.shown }
    var details: CGRect? { shown.map(Self.detailsFrame(for:)) }
    var place: MenuDetailsHover.Place { hover.place }

    /// When the pointer last came to `place`.
    func arrival(at place: MenuDetailsHover.Place) -> TimeInterval? {
        arrivals.last { $0.0 == place }?.1
    }

    /// The pointer onto `point`, as a mouse move or the edge of a tracking area reports it.
    mutating func move(to point: CGPoint) {
        self.point = point
        let place = MenuDetailsHover.place(of: point, details: details, rows: Self.rows, menu: Self.menuFrame)
        if place != hover.place {
            arrivals.append((place, now))
        }
        take(hover.pointer(place, at: point, time: now, shown: shown, details: details))
    }

    /// The pointer glides to `end` in `seconds`, a move every 1/120 s, the time running between them.
    mutating func glide(to end: CGPoint, in seconds: TimeInterval, each: (HoverMenu) -> Void = { _ in }) {
        let start = point
        let count = max(1, Int((seconds * 120).rounded()))
        for index in 1...count {
            wait(seconds / Double(count))
            let along = CGFloat(index) / CGFloat(count)
            move(to: CGPoint(x: start.x + (end.x - start.x) * along, y: start.y + (end.y - start.y) * along))
            each(self)
        }
    }

    mutating func wait(_ seconds: TimeInterval) {
        wait(until: now + seconds)
    }

    /// The time runs on to `end`; the timer fires whenever the rule asked to look again.
    mutating func wait(until end: TimeInterval) {
        while let next = hover.nextLook, next <= end {
            now = max(now, next)
            take(hover.tick(at: now, shown: shown))
        }
        now = max(now, end)
    }

    /// The details up for `id`, the pointer resting on its row.
    mutating func open(_ id: TouchscreenID, at point: CGPoint? = nil) {
        move(to: Self.onSettings)
        move(to: point ?? (id == UIFixtures.ilitek ? Self.onIlitek : Self.onStrip))
        wait(MenuDetailsHover.openDelay + 0.01)
        precondition(shown == id && log == [.show(id)])
    }

    /// A click on the row, a tap, or Return: as the window takes it. What the rule has waiting stays;
    /// it is judged against the details shown when its time comes.
    mutating func click(_ id: TouchscreenID) {
        log.append(presenter.chosen(id))
    }

    /// Esc, a click elsewhere in the menu, the menu closing: what the rule has waiting goes.
    mutating func close() {
        presenter.closed()
        hover.cancel()
        log.append(.close)
    }

    /// What the rule decided, as the window does it: a row's details shown as a click on it shows
    /// them; closed, with what the rule decided next left waiting.
    private mutating func take(_ action: MenuDetailsPresenter.Action?) {
        switch action {
        case .show(let id)?:
            click(id)
        case .close?:
            presenter.closed()
            log.append(.close)
        case nil:
            break
        }
    }
}
