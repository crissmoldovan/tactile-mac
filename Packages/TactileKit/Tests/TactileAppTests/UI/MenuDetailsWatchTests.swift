import AppKit
import SwiftUI
import TactileScreens
import XCTest

@testable import TactileApp

/// What a key or a click does to a touchscreen's details while they are up beside the menu: one click
/// on another touchscreen's row moves them there, with nothing closed first; a click on their own row
/// keeps them up; Esc closes them and goes no further; a click elsewhere in the menu closes them and goes
/// on; anything else is left alone. And the watch reads from an event only what its kind has: asking a
/// click for a key code raises, and AppKit then drops the click.
@MainActor
final class MenuDetailsWatchTests: XCTestCase {

    private let ilitek = UIFixtures.ilitek
    private let strip = UIFixtures.strip

    private let menu = 18984
    private let details = 18990
    private let settings = 18700

    /// The menu's two touchscreen rows, one beneath the other, in the menu window's coordinates
    /// (y grows upwards): the ILITEK's above, the strip's below, touching.
    private var rows: [MenuDetailsWatch.Row] {
        [
            MenuDetailsWatch.Row(id: ilitek, frame: CGRect(x: 6, y: 300, width: 336, height: 24)),
            MenuDetailsWatch.Row(id: strip, frame: CGRect(x: 6, y: 276, width: 336, height: 24)),
        ]
    }

    private func click(_ point: CGPoint, in window: Int? = nil, shown: TouchscreenID?) -> MenuDetailsWatch.Response {
        MenuDetailsWatch.response(
            to: .mouseDown(at: point, window: window ?? menu), menu: menu, details: details, rows: rows, shown: shown)
    }

    private func key(_ code: UInt16, in window: Int? = nil, shown: TouchscreenID?) -> MenuDetailsWatch.Response {
        MenuDetailsWatch.response(
            to: .key(code: code, window: window ?? menu), menu: menu, details: details, rows: rows, shown: shown)
    }

    // MARK: - A click on a row

    /// A click on another touchscreen's row is left to that row: nothing closes as the button goes
    /// down, and the row's own action moves the details to it in one step.
    func testOneClickOnAnotherRowMovesTheDetailsThere() {
        var presenter = MenuDetailsPresenter()
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek))

        let onTheStrip = CGPoint(x: 120, y: 288)
        XCTAssertEqual(click(onTheStrip, shown: ilitek), .row(strip), "nothing closes before the row's action")
        XCTAssertEqual(presenter.chosen(strip), .show(strip), "the row moves them, in one step")
        XCTAssertEqual(presenter.shown, strip)

        // And back, on the very edge of the ILITEK's row.
        XCTAssertEqual(click(CGPoint(x: 6, y: 300), shown: strip), .row(ilitek))
        XCTAssertEqual(presenter.chosen(ilitek), .show(ilitek))
    }

    /// A click on the row whose details are up is left to the row too, and the row keeps them up: a
    /// touch, which moves the pointer onto the row and clicks it at once, must not open them on the
    /// way and close them with the click.
    func testAClickOnTheirOwnRowKeepsTheDetailsUp() {
        var presenter = MenuDetailsPresenter()
        _ = presenter.chosen(strip)
        XCTAssertEqual(click(CGPoint(x: 330, y: 299), shown: strip), .row(strip))
        XCTAssertEqual(presenter.chosen(strip), .show(strip))
        XCTAssertEqual(presenter.shown, strip)
    }

    /// With no details up, a row is still the row's: its action opens them.
    func testAClickOnARowWithNoDetailsUpIsTheRows() {
        XCTAssertEqual(click(CGPoint(x: 120, y: 310), shown: nil), .row(ilitek))
    }

    // MARK: - A click elsewhere

    /// Anywhere else in the menu (the Tactile switch, a separator, Settings…, the panel's margin)
    /// closes the details, and the click goes on to what it was for.
    func testAClickElsewhereInTheMenuClosesTheDetailsAndGoesOn() {
        for point in [
            CGPoint(x: 300, y: 380),  // the Tactile switch, above the rows
            CGPoint(x: 120, y: 240),  // Set Up Touchscreens…, below them
            CGPoint(x: 3, y: 288),    // the margin beside the strip's row
            CGPoint(x: 120, y: 324),  // just above the ILITEK's row
        ] {
            XCTAssertEqual(click(point, shown: ilitek), .close, "\(point)")
        }
    }

    /// With no details up, there is nothing to close.
    func testAClickElsewhereWithNoDetailsUpDoesNothing() {
        XCTAssertEqual(click(CGPoint(x: 120, y: 240), shown: nil), .none)
    }

    /// A click in the details (a switch, the pop-up), in a pop-up menu opened from them, or in another
    /// window is left alone, wherever it falls in that window.
    func testAClickOutsideTheMenuIsLeftAlone() {
        let underARow = CGPoint(x: 120, y: 288)
        XCTAssertEqual(click(underARow, in: details, shown: ilitek), .none)
        XCTAssertEqual(click(underARow, in: settings, shown: ilitek), .none)
        XCTAssertEqual(click(CGPoint(x: 120, y: 240), in: details, shown: ilitek), .none)
    }

    // MARK: - Keys

    /// Esc in the menu or the details closes them and goes no further: a second Esc, with nothing
    /// shown, goes on and closes the menu. Other keys, and Esc elsewhere, are left alone.
    func testEscClosesTheDetailsAndGoesNoFurther() {
        let escape = MenuDetailsWatch.escape
        XCTAssertEqual(key(escape, shown: ilitek), .closeAndStop)
        XCTAssertEqual(key(escape, in: details, shown: ilitek), .closeAndStop)
        XCTAssertEqual(key(escape, shown: nil), .none, "the second Esc closes the menu")
        XCTAssertEqual(key(escape, in: settings, shown: ilitek), .none)
        XCTAssertEqual(key(36, shown: ilitek), .none, "Return is the row's")
        XCTAssertEqual(key(0, shown: ilitek), .none)
    }

    func testAnyOtherEventIsLeftAlone() {
        XCTAssertEqual(
            MenuDetailsWatch.response(to: .other, menu: menu, details: details, rows: rows, shown: ilitek), .none)
    }

    // MARK: - Reading the event

    /// A click is read for its place and window, and never asked for a key code: a mouse event has
    /// none, and asking raises "Invalid message sent to event", after which AppKit drops the click.
    /// (Each click in the menu was lost that way while the details were up: the log of the installed
    /// build shows it, from `-[NSEvent keyCode]` in this watch.) The events are made, not posted.
    func testTheWatchReadsOnlyWhatAnEventHas() throws {
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            let click = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: CGPoint(x: 32.5, y: 114), modifierFlags: [], timestamp: 0,
                windowNumber: menu, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            XCTAssertEqual(MenuDetailsWatch.Event(click), .mouseDown(at: CGPoint(x: 32.5, y: 114), window: menu))
        }

        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: menu, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
            keyCode: MenuDetailsWatch.escape))
        XCTAssertEqual(MenuDetailsWatch.Event(escape), .key(code: MenuDetailsWatch.escape, window: menu))

        let up = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: menu,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        XCTAssertEqual(MenuDetailsWatch.Event(up), .other)
    }

    // MARK: - The rows' frames

    /// The rows are found where they are drawn, each by its touchscreen, with its frame in the
    /// window's coordinates; a hidden one, or a view that isn't a row, is not a row. No window: the
    /// views stand alone, so their frames are in the top view's coordinates.
    func testTheRowsAreFoundWhereTheyAreDrawn() {
        let top = NSView(frame: CGRect(x: 0, y: 0, width: 348, height: 400))
        let list = NSView(frame: CGRect(x: 0, y: 200, width: 348, height: 150))
        top.addSubview(list)
        let first = RowAnchorView(frame: CGRect(x: 6, y: 100, width: 336, height: 24))
        first.id = ilitek
        let second = RowAnchorView(frame: CGRect(x: 6, y: 76, width: 336, height: 24))
        second.id = strip
        let hidden = RowAnchorView(frame: CGRect(x: 6, y: 52, width: 336, height: 24))
        hidden.id = UIFixtures.oldPanel
        hidden.isHidden = true
        let unnamed = RowAnchorView(frame: CGRect(x: 6, y: 28, width: 336, height: 24))
        for view in [first, second, hidden, unnamed] {
            list.addSubview(view)
        }
        top.addSubview(NSView(frame: CGRect(x: 0, y: 0, width: 348, height: 30)))

        XCTAssertEqual(RowAnchorView.rows(in: top), [
            MenuDetailsWatch.Row(id: ilitek, frame: CGRect(x: 6, y: 300, width: 336, height: 24)),
            MenuDetailsWatch.Row(id: strip, frame: CGRect(x: 6, y: 276, width: 336, height: 24)),
        ])
    }

    /// The panel as drawn: one row for each touchscreen, each known by its touchscreen, in the menu's
    /// order, one beneath the other, none overlapping; a click in the middle of each is that row's,
    /// and one between the rows and Set Up Touchscreens… closes the details. Drawn in a hosting view
    /// with no window, as the render tests are.
    func testThePanelDrawsARowForEachTouchscreen() throws {
        _ = NSApplication.shared
        let content = MenuBarContent(UIFixtures.desk)
        let host = NSHostingView(rootView: MenuBarPanel(
            content: content, perform: { _ in }, openSettings: {}, close: {}, quit: {}, detailsShown: ilitek))
        host.frame = NSRect(x: 0, y: 0, width: MenuBarPanel.width, height: 700)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        let drawn = RowAnchorView.rows(in: host)
        XCTAssertEqual(drawn.map(\.id), content.touchscreens.map(\.id))
        XCTAssertGreaterThanOrEqual(content.touchscreens.count, 2)
        for row in drawn {
            XCTAssertGreaterThanOrEqual(row.frame.height, 24, "\(row.id)")
            XCTAssertEqual(row.frame.width, MenuBarPanel.width - 12, accuracy: 0.5, "\(row.id)")
            XCTAssertEqual(
                MenuDetailsWatch.response(
                    to: .mouseDown(at: CGPoint(x: row.frame.midX, y: row.frame.midY), window: menu),
                    menu: menu, details: details, rows: drawn, shown: ilitek),
                .row(row.id))
        }
        // Downwards, in whichever way the coordinates run with no window.
        let down: CGFloat = drawn[1].frame.midY > drawn[0].frame.midY ? 1 : -1
        for (upper, lower) in zip(drawn, drawn.dropFirst()) {
            XCTAssertFalse(upper.frame.intersects(lower.frame), "\(upper.id), \(lower.id)")
            XCTAssertEqual(
                (lower.frame.midY - upper.frame.midY) * down, (upper.frame.height + lower.frame.height) / 2,
                accuracy: 0.5, "one right beneath the other")
        }
        let last = try XCTUnwrap(drawn.last)
        let belowTheLast = CGPoint(x: last.frame.midX, y: last.frame.midY + down * (last.frame.height / 2 + 6))
        XCTAssertEqual(
            MenuDetailsWatch.response(
                to: .mouseDown(at: belowTheLast, window: menu), menu: menu, details: details, rows: drawn,
                shown: ilitek),
            .close, "below the last row: the separator before Set Up Touchscreens…")
    }
}
