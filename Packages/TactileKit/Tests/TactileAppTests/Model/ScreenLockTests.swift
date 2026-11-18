// Whether the screen is locked, from the lock notifications and the session dictionary together.

@testable import TactileApp
import XCTest

final class ScreenLockTests: XCTestCase {

    func testANotifiedLockOutlastsPollsThatDoNotShowTheKey() {
        var lock = ScreenLock(dictionaryShowsLock: false)
        XCTAssertTrue(lock.notified(locked: true).changed)
        XCTAssertTrue(lock.isLocked)
        for _ in 0..<5 {
            XCTAssertFalse(lock.polled(dictionaryShowsLock: false).changed)
            XCTAssertTrue(lock.isLocked, "a dictionary that never shows the key can't undo the notification")
        }
    }

    func testTheKeyThenNoKeyUnlocks() {
        var lock = ScreenLock(dictionaryShowsLock: false)
        _ = lock.notified(locked: true)
        XCTAssertFalse(lock.polled(dictionaryShowsLock: true).changed)
        XCTAssertTrue(lock.isLocked)
        // The unlock notification never came; the dictionary, having shown the lock, now doesn't.
        let outcome = lock.polled(dictionaryShowsLock: false)
        XCTAssertTrue(outcome.changed)
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(outcome.report, "Screen lock ended (by the session dictionary): the lock notification saw it yes, the session dictionary yes")
    }

    func testTheUnlockNotificationUnlocks() {
        var lock = ScreenLock(dictionaryShowsLock: false)
        _ = lock.notified(locked: true)
        let outcome = lock.notified(locked: false)
        XCTAssertTrue(outcome.changed)
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(outcome.report, "Screen lock ended (by the unlock notification): the lock notification saw it yes, the session dictionary no")
        XCTAssertNil(lock.polled(dictionaryShowsLock: false).report, "one line per lock")
        XCTAssertNil(lock.notified(locked: false).report)
    }

    func testALockTheDictionaryAloneShowsLocksAndUnlocks() {
        var lock = ScreenLock(dictionaryShowsLock: false)
        XCTAssertTrue(lock.polled(dictionaryShowsLock: true).changed, "a missed lock notification")
        XCTAssertTrue(lock.isLocked)
        let outcome = lock.polled(dictionaryShowsLock: false)
        XCTAssertTrue(outcome.changed)
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(outcome.report, "Screen lock ended (by the session dictionary): the lock notification saw it no, the session dictionary yes")
    }

    func testTheReadOnWakingKeepsTheLock() {
        // Locked by the notification; the Mac sleeps and wakes; the read on waking sees no key.
        var lock = ScreenLock(dictionaryShowsLock: false)
        _ = lock.notified(locked: true)
        XCTAssertFalse(lock.polled(dictionaryShowsLock: false).changed)
        XCTAssertTrue(lock.isLocked)
    }

    func testALateLockNotificationNeedsTheKeyAgain() {
        // The dictionary showed the lock first; the notification came after it. The dictionary must
        // show the key again, after that notification, before its "unlocked" counts.
        var lock = ScreenLock(dictionaryShowsLock: false)
        _ = lock.polled(dictionaryShowsLock: true)
        XCTAssertFalse(lock.notified(locked: true).changed)
        XCTAssertFalse(lock.polled(dictionaryShowsLock: false).changed)
        XCTAssertTrue(lock.isLocked)
        _ = lock.polled(dictionaryShowsLock: true)
        XCTAssertTrue(lock.polled(dictionaryShowsLock: false).changed)
        XCTAssertFalse(lock.isLocked)
    }

    func testLockedAtLaunch() {
        var lock = ScreenLock(dictionaryShowsLock: true)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.polled(dictionaryShowsLock: false).changed, "the dictionary's own lock")
        XCTAssertFalse(lock.isLocked)
    }

    // MARK: - What the log is told

    func testEachLockSaysWhatSawItStart() {
        var byNotification = ScreenLock(dictionaryShowsLock: false)
        XCTAssertEqual(byNotification.notified(locked: true).report, "Screen lock started (seen by the lock notification)")
        XCTAssertNil(byNotification.notified(locked: true).report, "already locked: nothing new")

        var byDictionary = ScreenLock(dictionaryShowsLock: false)
        XCTAssertEqual(byDictionary.polled(dictionaryShowsLock: true).report,
                       "Screen lock started (seen by the session dictionary; no lock notification)")
        XCTAssertNil(byDictionary.polled(dictionaryShowsLock: true).report)
        XCTAssertNil(byDictionary.notified(locked: true).report, "a late notification starts nothing")
        XCTAssertNil(byDictionary.polled(dictionaryShowsLock: true).report, "it was the dictionary's lock all along")

        XCTAssertNil(ScreenLock(dictionaryShowsLock: false).reportAtLaunch)
        XCTAssertEqual(ScreenLock(dictionaryShowsLock: true).reportAtLaunch,
                       "Screen locked at launch (seen by the session dictionary)")
    }

    func testTheDictionaryConfirmingANotifiedLockIsSaidOnce() {
        var lock = ScreenLock(dictionaryShowsLock: false)
        _ = lock.notified(locked: true)
        XCTAssertNil(lock.polled(dictionaryShowsLock: false).report, "not yet")
        XCTAssertEqual(lock.polled(dictionaryShowsLock: true).report,
                       "Screen lock: the session dictionary shows it too")
        XCTAssertNil(lock.polled(dictionaryShowsLock: true).report, "only the first time")
        // Another lock notification during the same lock: the dictionary must show the key again
        // before its "unlocked" counts, but it has already been said to work.
        _ = lock.notified(locked: true)
        XCTAssertNil(lock.polled(dictionaryShowsLock: true).report)
        XCTAssertNotNil(lock.polled(dictionaryShowsLock: false).report, "the end is said")

        // The next lock says it again.
        _ = lock.notified(locked: true)
        XCTAssertEqual(lock.polled(dictionaryShowsLock: true).report, "Screen lock: the session dictionary shows it too")
    }

    func testTheLinesChangeNothingAboutTheLock() {
        // The same sequence of events as the tests above, read only for `isLocked`.
        var lock = ScreenLock(dictionaryShowsLock: false)
        XCTAssertTrue(lock.notified(locked: true).changed)
        XCTAssertFalse(lock.polled(dictionaryShowsLock: true).changed)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.polled(dictionaryShowsLock: false).changed)
        XCTAssertFalse(lock.isLocked)
    }
}
