// The live Dock-swipe sender's waits, kept so they can be run at once when the app quits.

import Foundation

/// Runs each piece of work on the main thread after its delay, as the sender asks (its repeated
/// end, a held-back `changed`), and keeps it until then, so `runNow()` can run every one still
/// waiting at once: at quit, a wait would die with the process, and with it the repeated end.
/// Each piece runs once, whichever comes first.
@MainActor
final class DockSwipeWaits {
    private var waiting: [Int: @MainActor () -> Void] = [:]
    private var next = 0

    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let key = next
        next += 1
        waiting[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.run(key) }
        }
    }

    /// Runs every piece still waiting, in the order they were asked for.
    func runNow() {
        for key in waiting.keys.sorted() { run(key) }
    }

    private func run(_ key: Int) {
        waiting.removeValue(forKey: key)?()
    }
}
