import Observation

/// What the interface sees and can ask for. The live model and the interface's preview model both
/// conform. The interface reads `snapshot` and sends commands; it holds no other state of the app.
@MainActor
public protocol AppModel: AnyObject, Observable {
    var snapshot: AppSnapshot { get }
    /// `snapshot` without the gesture tester's live feed (`AppSnapshot.withoutTesterFeed`), for every
    /// window but the tester's: it changes only when something they show changes, so the feed's
    /// updates, ten a second while a gesture goes on, don't draw them again. Set with `snapshot`.
    var steadySnapshot: AppSnapshot { get }
    func perform(_ command: AppCommand)
}

extension AppModel {
    /// For a model that keeps no steady snapshot of its own: worked out from `snapshot`, so it is
    /// right, and it changes whenever `snapshot` does.
    public var steadySnapshot: AppSnapshot { snapshot.withoutTesterFeed }
}

extension AppSnapshot {
    /// The snapshot with the gesture tester's feed, its counts and the fingers on the glass left out:
    /// whether the tester is open, and for which touchscreen and display, stays.
    public var withoutTesterFeed: AppSnapshot {
        guard var tester = gestureTester else { return self }
        tester.fingersDown = 0
        tester.recent = []
        tester.seen = []
        var steady = self
        steady.gestureTester = tester
        return steady
    }
}
