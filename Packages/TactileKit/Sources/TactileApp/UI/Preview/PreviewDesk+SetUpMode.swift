// Set-up mode on the preview desk: every stage the interface draws (choosing, waiting for a touch,
// touched first, a flow running, a notice, a touchscreen just set up, leaving), driven by the same
// commands the real model takes, and by what only a hand or a cable does (a touch, a display or a
// touchscreen unplugged), given as a `Happening`. A small stand-in for the model's `SetUpSession`,
// with only what the screens need: a touch here is an answer, decided at its lift; there are no
// reaction times, no quiet start and no fingers already resting, which are the model's to keep.

import Foundation
import TactileGestures
import TactileScreens

extension PreviewDesk {

    /// Set-up mode, while it is on.
    struct SetUpModeRun: Equatable, Sendable {
        var stage: SetUpModeSnapshot.Stage = .choosing
        /// The last touchscreen Done in this session.
        var justSetUp: TouchscreenID?
        /// The latest thing to tell, until the next stage change.
        var notice: SetUpModeNotice?
        /// When the last command or touch came, for the two minutes without one that end the mode.
        var lastInput: TimeInterval
        /// The touchscreens connected and not set up when the mode began: offered no more once it
        /// is left by Finish, Esc or its two minutes.
        var notSetUpWhenItBegan: [TouchscreenID]
    }

    /// What a test or a preview does by hand, beyond the commands.
    enum Happening: Equatable, Sendable {
        /// A touch on this touchscreen, lifted: in the overview an answer; in a flow of that
        /// touchscreen, the next tap.
        case touch(TouchscreenID)
        case touchscreenConnected(TouchscreenID, Bool)
        case displayConnected(UInt32, Bool)
    }

    // MARK: - Which touchscreens and displays

    /// Whether set-up mode could set it up: connected, with a record, its touches readable, and not
    /// also handled by macOS. Whether a display is free plays no part.
    func canBeSetUpByTouch(_ panel: Panel) -> Bool {
        panel.isConnected && panel.hasRecord && !panel.notes.contains(.touchesCannotBeRead)
            && !(panel.notes.contains(.oneFingerOnly) && panel.notes.contains(.macOSMayAlsoRespond))
    }

    /// Why set-up mode can't begin now, as the model asks: Tactile on, Accessibility granted, a
    /// display connected, no set-up running, a connected touchscreen that can be set up, and a
    /// candidate display. Nil when it can.
    var setUpModeRefusal: SetUpModeRefusal? {
        if !isOn { return .tactileOff }
        if !hasAccessibility { return .accessibilityMissing }
        if !screens.contains(where: \.isConnected) { return .noDisplay }
        if setUpRun != nil || modeRun != nil { return .running }
        if !panels.contains(where: canBeSetUpByTouch) { return .noTouchscreenCanBeSetUp }
        if !screens.contains(where: { $0.isConnected && !$0.isBuiltIn }) { return .noDisplayToChoose }
        return nil
    }

    var setUpModeCouldBegin: Bool { setUpModeRefusal == nil }

    /// The one-finger mode a touchscreen gets by default: Always scroll where only one finger comes
    /// through, Automatic elsewhere.
    func defaultOneFinger(_ panel: Panel) -> OneFingerMode {
        panel.notes.contains(.oneFingerOnly) ? .alwaysScroll : .automatic
    }

    // MARK: - Beginning and leaving

    mutating func beginSetUpMode(at now: TimeInterval) {
        guard setUpModeCouldBegin else { return }
        modeRun = SetUpModeRun(
            lastInput: now,
            notSetUpWhenItBegan: panels.filter { $0.isConnected && $0.pairedUUID == nil }.map(\.id))
    }

    /// Cancel, Finish or Esc: in set-up mode, leaves it, storing nothing more; outside it, ends the
    /// flow.
    mutating func cancelSetUp() {
        if modeRun != nil {
            leaveSetUpMode(markingOffered: true)
        } else {
            endSetUp()
        }
    }

    /// Tactile turned off, and the like: everything ends, and nothing is marked offered.
    mutating func interruptSetUp() {
        setUpRun = nil
        modeRun = nil
    }

    private mutating func leaveSetUpMode(markingOffered: Bool) {
        guard let mode = modeRun else { return }
        setUpRun = nil
        modeRun = nil
        guard markingOffered else { return }
        for id in mode.notSetUpWhenItBegan {
            update(id) { $0.wasOfferedSetUp = true }
        }
    }

    /// The two minutes without a command or a touch, in any stage, end the mode as Esc would.
    mutating func tickSetUpMode(at now: TimeInterval) {
        guard let mode = modeRun else { return }
        let last = max(mode.lastInput, setUpRun?.lastInput ?? mode.lastInput)
        if now - last >= Self.endsWithoutInput {
            leaveSetUpMode(markingOffered: true)
        }
    }

    // MARK: - The commands

    mutating func applySetUpMode(_ command: AppCommand, at now: TimeInterval) {
        if command == .beginSetUpMode {
            beginSetUpMode(at: now)
            return
        }
        guard var mode = modeRun else { return }
        mode.lastInput = now
        switch command {
        case .setUpChoose(let display):
            guard screens.contains(where: { $0.id == display && $0.isConnected && !$0.isBuiltIn }) else { return }
            switch mode.stage {
            case .choosing, .waitingForTouch:
                mode.stage = .waitingForTouch(display: display)
                mode.notice = nil
                modeRun = mode
            case .touchedFirst(let touchscreen, _):
                modeRun = mode
                startFlow(touchscreen, on: display, at: now)
            case .running:
                return
            }
        case .setUpBack:
            switch mode.stage {
            case .waitingForTouch, .touchedFirst:
                mode.stage = .choosing
                mode.notice = nil
                modeRun = mode
            case .running:
                modeRun = mode
                if let run = setUpRun {
                    setUpRun = nil
                    flowEnded(run, stored: false)
                }
            case .choosing:
                return
            }
        default:
            return
        }
    }

    /// A flow begins: in set-up mode, the overview gives way to it.
    mutating func flowBegan() {
        modeRun?.stage = .running
        modeRun?.notice = nil
    }

    /// A flow ended, Done (`stored`) or not: in set-up mode, back to the overview, with the
    /// touchscreen just set up (by a full set-up or a calibration) or the notice that says why not.
    mutating func flowEnded(_ run: SetUpRun, stored: Bool, notice: SetUpModeNotice? = nil) {
        guard var mode = modeRun else { return }
        mode.stage = .choosing
        mode.notice = notice
        if stored, run.purpose != .test {
            mode.justSetUp = run.touchscreen
        }
        modeRun = mode
    }

    private mutating func startFlow(_ id: TouchscreenID, on display: UInt32, at now: TimeInterval) {
        guard let panel = panels.first(where: { $0.id == id }), canBeSetUpByTouch(panel),
            screens.contains(where: { $0.id == display && $0.isConnected && !$0.isBuiltIn })
        else { return }
        setUpRun = SetUpRun(
            touchscreen: id, purpose: .full,
            step: .corners(display: display, target: Calibration.targets[0], index: 0, problem: nil),
            display: display, diagonal: panel.diagonalInches, lastInput: now)
        flowBegan()
    }

    // MARK: - What a hand or a cable does

    mutating func happen(_ happening: Happening, at now: TimeInterval) {
        switch happening {
        case .touch(let id):
            touch(id, at: now)
        case .touchscreenConnected(let id, let connected):
            guard let index = panels.firstIndex(where: { $0.id == id }) else { return }
            panels[index].isConnected = connected
            guard !connected else { return }
            let gone = SetUpModeNotice.touchscreenGone(name: panels[index].name)
            if let run = setUpRun, run.touchscreen == id {
                setUpRun = nil
                flowEnded(run, stored: false, notice: gone)
            }
            if case .touchedFirst(id, _)? = modeRun?.stage {
                modeRun?.stage = .choosing
                modeRun?.notice = gone
            }
        case .displayConnected(let display, let connected):
            guard let index = screens.firstIndex(where: { $0.id == display }) else { return }
            screens[index].isConnected = connected
            guard !connected else { return }
            let gone = SetUpModeNotice.displayGone(name: displayName(uuid: screens[index].uuid))
            if let run = setUpRun, run.display == display {
                setUpRun = nil
                flowEnded(run, stored: false, notice: gone)
            }
            if case .waitingForTouch(display)? = modeRun?.stage {
                modeRun?.stage = .choosing
                modeRun?.notice = gone
            }
        }
    }

    /// A touch on `id`, lifted. Outside the overview, the next tap of a flow of that touchscreen.
    private mutating func touch(_ id: TouchscreenID, at now: TimeInterval) {
        guard var mode = modeRun, mode.stage != .running else {
            if setUpRun?.touchscreen == id {
                touchSetUp(at: now)
            }
            return
        }
        guard let panel = panels.first(where: { $0.id == id && $0.isConnected }) else { return }
        // Only a touch that can move the mode on is input, as in the model: not one from a
        // touchscreen that can't be set up.
        guard canBeSetUpByTouch(panel) else {
            mode.notice = .cannotBeSetUp(touchscreen: id, name: panel.name)
            modeRun = mode
            return
        }
        mode.lastInput = now
        if case .waitingForTouch(let display) = mode.stage {
            modeRun = mode
            startFlow(id, on: display, at: now)
        } else {
            mode.stage = .touchedFirst(touchscreen: id, name: panel.name)
            mode.notice = nil
            modeRun = mode
        }
    }

    // MARK: - The snapshot

    /// Set-up mode as the screens draw it: a card per candidate display, in the snapshot's order;
    /// a line per connected touchscreen.
    func setUpModeSnapshot(displays: [DisplaySnapshot]) -> SetUpModeSnapshot? {
        guard let mode = modeRun else { return nil }
        let connected = panels.filter(\.isConnected)
        let cards = displays.filter { !$0.isBuiltIn }.map { display in
            let paired = connected.first { $0.pairedUUID == display.uuid }
            return SetUpDisplayCard(
                id: display.id, name: display.name, detail: display.detail, touchscreen: paired?.id,
                touchscreenName: paired?.name)
        }
        let lines = connected.map { panel -> SetUpTouchscreenLine in
            if !canBeSetUpByTouch(panel) {
                return SetUpTouchscreenLine(id: panel.id, name: panel.name, state: .cannotBeSetUp, reason: whyNot(panel))
            }
            guard let uuid = panel.pairedUUID else {
                return SetUpTouchscreenLine(id: panel.id, name: panel.name, state: .notSetUp, reason: nil)
            }
            let name = displays.first { $0.uuid == uuid }?.name ?? displayName(uuid: uuid)
            return SetUpTouchscreenLine(id: panel.id, name: panel.name, state: .setUp(displayName: name), reason: nil)
        }
        return SetUpModeSnapshot(
            stage: mode.stage, displays: cards, touchscreens: lines, justSetUp: mode.justSetUp, notice: mode.notice)
    }

    /// Why a connected touchscreen can't be set up, as the pane words it.
    private func whyNot(_ panel: Panel) -> String? {
        if !panel.hasRecord { return Wording.note(.cannotBeToldApart) }
        if panel.notes.contains(.touchesCannotBeRead) { return Wording.setUpUnavailable(.touchesCannotBeRead) }
        if panel.notes.contains(.oneFingerOnly), panel.notes.contains(.macOSMayAlsoRespond) {
            return Wording.setUpUnavailable(.macOSAlsoHandlesIt)
        }
        return nil
    }

    /// The touchscreens the first-run window names: connected, able to be set up, not set up and not
    /// offered before, while Accessibility is granted, Tactile is on and no set-up runs.
    func offers() -> [TouchscreenID] {
        guard isOn, hasAccessibility, setUpRun == nil, modeRun == nil else { return [] }
        return panels
            .filter { canBeSetUpByTouch($0) && $0.pairedUUID == nil && !$0.wasOfferedSetUp }
            .map(\.id)
    }
}
