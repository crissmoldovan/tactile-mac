import Foundation

/// Shares the one pointer and mouse button among several touchscreens, frame by frame.
///
/// A touchscreen takes the pointer with its first finger down when no touchscreen owns it. While
/// the owner has fingers down, touches elsewhere are ignored until they lift, so half a gesture
/// never starts. Once the owner's fingers are up, a touch elsewhere takes over at once.
///
/// `fingersDown` means fingers that count: the frame's fingers after the contact filter. A contact
/// the filter refuses, such as a resting palm, never reaches the arbiter, so it can't hold the
/// pointer. `sessionEnded(for:)` only frees the pointer: it never marks that touchscreen's
/// remaining fingers as ignored. The one time a session is over with fingers still down is after
/// an engine cancel, and then either order is harmless: that touchscreen's next frame takes the
/// pointer again (its engine ignores those fingers until they lift), or the other touchscreen gets
/// in first and takes it.
///
/// Not thread-safe: call every method on the main thread.
public final class PointerArbiter<ID: Hashable> {

    public enum Verdict: Equatable {
        /// Pass the frame to this touchscreen's engine.
        case process
        /// Cancel the previous owner's engine, then pass the frame to this touchscreen's engine.
        case processAfterCancelling(ID)
        /// Don't pass the frame on.
        case ignore
    }

    /// The touchscreen using the pointer; nil while it's free.
    public private(set) var owner: ID?

    /// Whether the owner's last frame had fingers down.
    private var ownerFingersDown = false
    /// Touchscreens whose fingers came down while they couldn't take the pointer. Each stays
    /// ignored until a frame arrives from it with no fingers.
    private var waitingForLift: Set<ID> = []

    public init() {}

    /// Call once per frame, before the frame reaches that touchscreen's engine.
    public func verdict(for id: ID, fingersDown: Bool) -> Verdict {
        if id == owner {
            ownerFingersDown = fingersDown
            return .process
        }
        if waitingForLift.contains(id) {
            if !fingersDown { waitingForLift.remove(id) }
            return .ignore
        }
        guard fingersDown else { return .ignore }
        guard let previous = owner else {
            take(id)
            return .process
        }
        if ownerFingersDown {
            waitingForLift.insert(id)
            return .ignore
        }
        take(id)
        return .processAfterCancelling(previous)
    }

    /// Call when that touchscreen's engine emits `sessionEnded` or `sessionCancelled`: either way its
    /// session is over. Frees the pointer if it owns it; does nothing otherwise, as for a previous
    /// owner whose engine a take-over cancelled.
    public func sessionEnded(for id: ID) {
        guard id == owner else { return }
        release()
    }

    /// Call when the touchscreen is unplugged or stops driving. Forgets it entirely.
    public func removed(_ id: ID) {
        waitingForLift.remove(id)
        if id == owner { release() }
    }

    private func take(_ id: ID) {
        owner = id
        ownerFingersDown = true
    }

    private func release() {
        owner = nil
        ownerFingersDown = false
    }
}
