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
}
