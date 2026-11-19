import Foundation
@testable import TactileApp
import TactileDevices
import TactileScreens
import XCTest

private typealias Desk = DeskFixture

/// The model lets go of a touchscreen while it is checked, so the check can take it exactly as
/// Tactile does, and takes it back when the check ends. Nothing here opens a device.
@MainActor
final class SupportCheckModelTests: XCTestCase {

    private func deskHarness() throws -> ModelHarness {
        let harness = try ModelHarness(settings: Desk.settings, fileBytes: nil, writesStateFile: false)
        addTeardownBlock { @MainActor in harness.cleanUp() }
        harness.source.plugIn(Desk.ilitek())
        harness.source.plugIn(Desk.stripScreen())
        harness.model.start()
        return harness
    }

    func testTheTouchscreenCheckedIsLetGoAndTakenBack() throws {
        let harness = try deskHarness()
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        let saves = harness.model.saves
        let before = harness.touchscreen(Desk.ilitekID)

        let claim = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: claim))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released, "let go before the check takes it")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken, "the other touchscreen carries on")
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)

        harness.model.perform(.endSupportCheck(claim: claim))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "taken back")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.model.saves, saves, "nothing about a check is saved")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID), before,
                       "exactly as it was: driving, its input mode, its touches' origin and its exclusive access")
    }

    func testACheckDoesntBeginWhileASetUpRuns() throws {
        let harness = try deskHarness()
        harness.model.perform(.beginSetUpMode)
        XCTAssertNotNil(harness.model.snapshot.setUpMode)
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: UUID()))
        XCTAssertNotEqual(harness.source.state(of: Desk.ilitekHandle), .released, "refused: set-up mode has it")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .settingUp)
    }

    func testEndingACheckThatIsntRunningChangesNothing() throws {
        let harness = try deskHarness()
        let before = harness.model.snapshot
        harness.model.perform(.endSupportCheck(claim: UUID()))
        XCTAssertEqual(harness.model.snapshot, before)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
    }

    /// Each check holds a claim of its own: the touchscreen stays let go while any claim is held,
    /// and is taken back, exactly as it was, when the last one goes.
    func testEachCheckHoldsItsOwnClaim() throws {
        let harness = try deskHarness()
        let before = harness.touchscreen(Desk.ilitekID)
        let first = UUID(), second = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: first))
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: second))
        harness.model.perform(.endSupportCheck(claim: second))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released, "the first check still holds it")
        harness.model.perform(.endSupportCheck(claim: first))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken, "the last claim gone: taken back")
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID), before, "as it was, its input mode included")
    }

    /// The review's sequence: check A lets go late, after check B has begun. A's late hand-back can't
    /// clear B's claim, and B's can't clear A's: the touchscreen is taken back only once both are done.
    func testAStaleHandBackCantClearANewerClaim() throws {
        let harness = try deskHarness()
        let before = harness.touchscreen(Desk.ilitekID)
        let a = UUID(), b = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: a))
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: b))
        harness.model.perform(.endSupportCheck(claim: b))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released, "A still holds it")
        harness.model.perform(.endSupportCheck(claim: a))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID), before, "both done: taken back as it was")
        harness.model.perform(.endSupportCheck(claim: a))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID), before, "a hand-back given twice changes nothing")

        let c = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: c))
        harness.model.perform(.endSupportCheck(claim: a))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .released, "an old claim's hand-back leaves a newer check alone")
        harness.model.perform(.endSupportCheck(claim: c))
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID), before)
    }

    // MARK: - A device that stopped answering

    /// A check that gave up on a read that never returned hands back its claim saying the device
    /// stopped answering.
    private func stopAnswering(_ harness: ModelHarness) {
        let claim = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: claim))
        harness.model.perform(.endSupportCheck(claim: claim, deviceStoppedAnswering: true))
    }

    /// The times the model asked the source to take `handle`.
    private func takes(_ harness: ModelHarness, _ handle: DeviceHandle) -> Int {
        harness.log.entries.filter { $0 == "source.setState \(handle) taken" }.count
    }

    /// The claim goes, and the touchscreen is left released, saying so, with nothing asked of it: a
    /// device that hasn't answered for 30 s can't safely be taken on the main thread. The other
    /// touchscreen carries on.
    func testATouchscreenThatStoppedAnsweringIsLeftReleasedAndSaysSo() throws {
        let harness = try deskHarness()
        let takenBefore = takes(harness, Desk.ilitekHandle)
        stopAnswering(harness)
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        XCTAssertEqual(takes(harness, Desk.ilitekHandle), takenBefore, "not taken again")
        XCTAssertEqual(harness.model.inputs.supportChecks, [:], "its claim is given back")
        let ilitek = try XCTUnwrap(harness.touchscreen(Desk.ilitekID))
        XCTAssertEqual(ilitek.mode, .released)
        XCTAssertEqual(ilitek.status, .stoppedAnswering)
        XCTAssertFalse(ilitek.canBeSetUp, "no set-up takes it either")
        XCTAssertEqual(Wording.statusLine(for: ilitek), "Stopped answering. Unplug it and plug it back in.")
        XCTAssertEqual(Resolver.resolve(harness.model.inputs).touchscreens.first { $0.handle == Desk.ilitekHandle }?.rule,
                       .stoppedAnswering)
        XCTAssertEqual(harness.source.state(of: Desk.stripHandle), .taken, "the other touchscreen carries on")
        XCTAssertEqual(harness.touchscreen(Desk.stripID)?.mode, .driving)
    }

    /// Nothing takes it back behind its status: not another touchscreen's change, going or coming,
    /// nor the displays, the session, its own switch, set-up mode, or another check's hand-back.
    func testNothingTakesBackATouchscreenThatStoppedAnswering() throws {
        let harness = try deskHarness()
        stopAnswering(harness)
        let takenBefore = takes(harness, Desk.ilitekHandle)

        harness.source.change(Desk.stripHandle) { $0.status = Desk.taken(origin: .mouseInterface) }
        harness.source.unplug(Desk.stripHandle)
        harness.source.plugIn(Desk.stripScreen(handle: DeviceHandle(rawValue: 7)))
        harness.displays.set(DeskFixture.displays)
        harness.conditions.setSessionActive(false)
        harness.conditions.setSessionActive(true)
        harness.model.perform(.setTouchscreenOn(Desk.ilitekID, false))
        harness.model.perform(.setTouchscreenOn(Desk.ilitekID, true))
        harness.model.perform(.beginSetUpMode)
        harness.model.perform(.cancelSetUp)
        let other = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: other))
        harness.model.perform(.endSupportCheck(claim: other))

        XCTAssertEqual(takes(harness, Desk.ilitekHandle), takenBefore, "never taken again")
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .stoppedAnswering)
        XCTAssertEqual(harness.source.state(of: DeviceHandle(rawValue: 7)), .taken, "the other is taken as usual")
    }

    /// Each check's claim still holds: one check's hand-back saying the device stopped answering
    /// leaves another's claim, and the other's later hand-back doesn't take the touchscreen back.
    func testAnotherChecksClaimStillHoldsWhenOneGivesUp() throws {
        let harness = try deskHarness()
        let a = UUID(), b = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: a))
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: b))
        harness.model.perform(.endSupportCheck(claim: a, deviceStoppedAnswering: true))
        XCTAssertEqual(harness.model.inputs.supportChecks, [b: Desk.ilitekID], "only its own claim goes")
        harness.model.perform(.endSupportCheck(claim: b))
        XCTAssertEqual(harness.model.inputs.supportChecks, [:])
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, .stoppedAnswering)
    }

    /// Plugging it in again clears it: the new connection is taken as usual.
    func testPluggingItInAgainClearsItAndTakesItAsUsual() throws {
        let harness = try deskHarness()
        let before = harness.touchscreen(Desk.ilitekID)
        stopAnswering(harness)
        harness.source.unplug(Desk.ilitekHandle)
        XCTAssertEqual(harness.model.inputs.stoppedAnswering, [], "the connection that stopped answering has gone")
        let replugged = DeviceHandle(rawValue: 3)
        harness.source.plugIn(Desk.ilitek(handle: replugged))
        XCTAssertEqual(harness.source.state(of: replugged), .taken)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.status, before?.status)
    }

    /// Turning Tactile off and on clears it, and takes it as usual.
    func testTurningTactileOffAndOnClearsIt() throws {
        let harness = try deskHarness()
        stopAnswering(harness)
        harness.model.perform(.setOn(false))
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        harness.model.perform(.setOn(true))
        XCTAssertEqual(harness.model.inputs.stoppedAnswering, [])
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
    }

    /// Sleep and wake clear it, and take it as usual.
    func testSleepAndWakeClearIt() throws {
        let harness = try deskHarness()
        stopAnswering(harness)
        harness.conditions.sleep()
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .released)
        harness.conditions.wake()
        XCTAssertEqual(harness.model.inputs.stoppedAnswering, [])
        XCTAssertEqual(harness.source.state(of: Desk.ilitekHandle), .taken)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
    }

    /// Unplugged and plugged in again before the check gave up: the connection that stopped
    /// answering has gone, and the new one, which nothing has failed on, is taken as usual.
    func testAGiveUpAfterAReplugLeavesTheNewConnectionAlone() throws {
        let harness = try deskHarness()
        let claim = UUID()
        harness.model.perform(.beginSupportCheck(Desk.ilitekID, claim: claim))
        harness.source.unplug(Desk.ilitekHandle)
        let replugged = DeviceHandle(rawValue: 3)
        harness.source.plugIn(Desk.ilitek(handle: replugged))
        XCTAssertEqual(harness.source.state(of: replugged), .released, "the claim still holds it")
        harness.model.perform(.endSupportCheck(claim: claim, deviceStoppedAnswering: true))
        XCTAssertEqual(harness.model.inputs.stoppedAnswering, [])
        XCTAssertEqual(harness.source.state(of: replugged), .taken)
        XCTAssertEqual(harness.touchscreen(Desk.ilitekID)?.mode, .driving)
    }
}
