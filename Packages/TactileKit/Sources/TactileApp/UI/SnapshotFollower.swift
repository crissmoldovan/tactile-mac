// The windows that aren't scenes follow the snapshot through their own observer: the set-up screens
// (`SetUpOverlay`) and the first-run window (`FirstRunWindow`). Not through the menu-bar label: if
// the person hides the icon, SwiftUI may stop updating the label, and nothing would take the set-up
// screens down after Done, Cancel or the two minutes without input.

import Foundation
import Observation

/// Watches `model.steadySnapshot` with Observation, re-armed after every change, and tells the set-up
/// screens and the first-run window what to show whenever theirs changes: once at the start, then
/// only on a change. It notices an offer made long after launch (the model makes one only once
/// Accessibility is granted, or when a touchscreen is plugged in). The steady snapshot leaves out
/// the gesture tester's feed, which neither shows: a gesture in the tester doesn't wake it.
@MainActor
final class SnapshotFollower {
    private let model: any AppModel
    private let showSetUp: @MainActor (SetUpPresentation) -> Void
    private let showFirstRun: @MainActor (FirstRunOffer?) -> Void
    private var isFollowing = false
    private var lastSetUp: SetUpPresentation?
    private var lastOffer: FirstRunOffer?
    private var hasToldOffer = false

    init(
        model: any AppModel, showSetUp: @escaping @MainActor (SetUpPresentation) -> Void,
        showFirstRun: @escaping @MainActor (FirstRunOffer?) -> Void
    ) {
        self.model = model
        self.showSetUp = showSetUp
        self.showFirstRun = showFirstRun
    }

    /// Starts following, and tells both at once. Starting again changes nothing.
    func start() {
        guard !isFollowing else { return }
        isFollowing = true
        follow()
    }

    func stop() {
        isFollowing = false
    }

    private func follow() {
        guard isFollowing else { return }
        let snapshot = withObservationTracking {
            model.steadySnapshot
        } onChange: { [weak self] in
            // Called as the snapshot is about to change: read it once it has.
            Task { @MainActor in self?.follow() }
        }
        tell(snapshot)
    }

    private func tell(_ snapshot: AppSnapshot) {
        let setUp = SetUpPresentation(snapshot)
        if setUp != lastSetUp {
            lastSetUp = setUp
            showSetUp(setUp)
        }
        let offer = FirstRunOffer(snapshot)
        if !hasToldOffer || offer != lastOffer {
            hasToldOffer = true
            lastOffer = offer
            showFirstRun(offer)
        }
    }

    // MARK: - The app's

    private static var started: (model: ObjectIdentifier, follower: SnapshotFollower)?

    /// Follows `model` for the app's set-up screens and first-run window, once: called again for the
    /// same model (SwiftUI may make the scenes again), it changes nothing.
    static func startForTheApp(_ model: any AppModel) {
        let id = ObjectIdentifier(model)
        guard started?.model != id else { return }
        started?.follower.stop()
        let follower = SnapshotFollower(
            model: model,
            showSetUp: { [weak model] presentation in
                SetUpOverlay.shared.show(
                    presentation, perform: { model?.perform($0) },
                    check: { id in
                        guard let model else { return }
                        SetUpModeCheck.leaveThenCheck(id, model: model)
                    })
            },
            showFirstRun: { [weak model] offer in
                FirstRunWindow.shared.show(offer, perform: { model?.perform($0) })
            })
        started = (id, follower)
        InterfaceLog.log.info("following the snapshot for the set-up screens and the first-run window")
        follower.start()
    }
}
