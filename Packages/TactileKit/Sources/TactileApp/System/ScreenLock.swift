// Whether the screen is locked, from the two places macOS says so. Pure, so it is tested.

/// Whether the screen is locked, combining the `com.apple.screenIsLocked` / `…Unlocked`
/// notifications with the session dictionary's `CGSSessionScreenIsLocked` key, read every 2 seconds
/// and on waking.
///
/// The dictionary has no key while unlocked; whether it shows the key while locked, and how soon,
/// is not known on every macOS. So it can confirm a lock, catch one whose notification never came,
/// and end one whose unlock notification never came, but it can't undo a lock it hasn't itself
/// seen:
/// - a lock notification locks;
/// - an unlock notification unlocks;
/// - the dictionary showing the key locks;
/// - the dictionary not showing it unlocks only if it has shown the key since the last lock
///   notification (or the lock was its own, with no notification).
///
/// It also says what the log should be told, at most one line for each event:
/// - when a lock starts, which of the two saw it (`reportAtLaunch` for one already there at launch);
/// - during a lock a notification started, the first time the dictionary shows the key, so a log
///   that never says so shows a macOS whose dictionary can't end a lock whose unlock notification
///   was missed;
/// - when a lock ends, which of the two saw it, and which ended it.
/// The lines change nothing about when the screen counts as locked.
struct ScreenLock: Equatable {
    struct Outcome: Equatable {
        /// Whether `isLocked` changed.
        var changed: Bool
        /// A line for the log, when one is due: a lock started, confirmed by the dictionary, or ended.
        var report: String?
    }

    private(set) var isLocked: Bool
    /// Whether a lock notification started the current lock.
    private var notificationStartedIt = false
    /// Whether a lock notification saw the current lock.
    private var notificationSawIt = false
    /// Whether the dictionary has shown the key since the last lock notification, or, for a lock
    /// with no notification, at all.
    private var dictionaryConfirmed = false
    /// Whether the dictionary showed the key at any time during the current lock.
    private var dictionarySawIt = false

    /// As the session dictionary says at the start.
    init(dictionaryShowsLock: Bool) {
        isLocked = dictionaryShowsLock
        dictionaryConfirmed = dictionaryShowsLock
        dictionarySawIt = dictionaryShowsLock
    }

    /// The line for a lock already there when Tactile starts; nil when unlocked.
    var reportAtLaunch: String? {
        isLocked && !notificationSawIt ? "Screen locked at launch (seen by the session dictionary)" : nil
    }

    mutating func notified(locked: Bool) -> Outcome {
        if locked {
            let changed = !isLocked
            if changed {
                dictionarySawIt = false
                notificationStartedIt = true
            }
            isLocked = true
            notificationSawIt = true
            dictionaryConfirmed = false
            return Outcome(changed: changed, report: changed ? "Screen lock started (seen by the lock notification)" : nil)
        }
        return unlock(by: "the unlock notification")
    }

    mutating func polled(dictionaryShowsLock: Bool) -> Outcome {
        if dictionaryShowsLock {
            let changed = !isLocked
            var report: String?
            if changed {
                notificationSawIt = false
                notificationStartedIt = false
                report = "Screen lock started (seen by the session dictionary; no lock notification)"
            } else if notificationStartedIt, !dictionarySawIt {
                report = "Screen lock: the session dictionary shows it too"
            }
            isLocked = true
            dictionaryConfirmed = true
            dictionarySawIt = true
            return Outcome(changed: changed, report: report)
        }
        guard isLocked, dictionaryConfirmed else { return Outcome(changed: false) }
        return unlock(by: "the session dictionary")
    }

    private mutating func unlock(by source: String) -> Outcome {
        guard isLocked else { return Outcome(changed: false) }
        let report = "Screen lock ended (by \(source)): the lock notification saw it \(notificationSawIt ? "yes" : "no"), "
            + "the session dictionary \(dictionarySawIt ? "yes" : "no")"
        self = ScreenLock(dictionaryShowsLock: false)
        return Outcome(changed: true, report: report)
    }
}
