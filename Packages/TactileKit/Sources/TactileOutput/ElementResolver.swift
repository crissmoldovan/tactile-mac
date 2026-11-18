import ApplicationServices
import Foundation
import TactileGestures

/// Asks an app, through Accessibility, what's under a finger, and turns the answer into drag or scroll.
public final class ElementResolver {
    private let budget: TimeInterval

    /// - Parameter budget: the most time to spend on one question; past it, the answer is drag.
    public init(budget: TimeInterval = 0.02) {
        self.budget = budget
        // Set on the system-wide element, the timeout applies to every Accessibility call this app makes.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Float(budget))
    }

    /// Asked of the app `pid` alone, whose window is under the finger (`AppUnderPoint`), never of
    /// the whole screen: Accessibility hit-tests by window order, so the system-wide element could
    /// answer with whatever is topmost there, Tactile's touch circles included.
    ///
    /// - Parameter point: global screen coordinates, origin at the top left.
    public func intent(at point: CGPoint, inApp pid: pid_t) -> OneFingerIntent {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var hit: AXUIElement?
        guard pid != getpid(),
              AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(point.x), Float(point.y),
                                               &hit) == .success,
              let element = hit else { return .drag }

        // A read the app didn't answer counts as no answer in time, like the deadline passing.
        var completed = true
        var roles: [String] = []
        var node: AXUIElement? = element
        walk: while let current = node, roles.count < 8 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { completed = false; break }
            switch Self.read(current, kAXRoleAttribute) {
            case .value(let role): roles.append(role as? String ?? "")
            case .absent: roles.append("")
            case .noAnswer: completed = false; break walk
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { completed = false; break }
            switch Self.read(current, kAXParentAttribute) {
            case .value(let parent) where CFGetTypeID(parent) == AXUIElementGetTypeID():
                node = (parent as! AXUIElement)
            case .value, .absent: node = nil  // the top of the tree
            case .noAnswer: completed = false; break walk
            }
        }
        var hasSelection = false
        if completed, ProcessInfo.processInfo.systemUptime < deadline {
            switch Self.read(element, kAXSelectedTextRangeAttribute) {
            case .value(let range): hasSelection = Self.length(ofRange: range) > 0
            case .absent: break
            case .noAnswer: completed = false
            }
        }
        // The walk stops early, and the selection check is skipped, only once the deadline has
        // passed or a read went unanswered, and the clock only moves forward. So one more look at
        // the clock tells whether everything finished inside the budget. If not, the classifier
        // answers drag.
        completed = completed && ProcessInfo.processInfo.systemUptime < deadline
        return ElementClassifier.intent(roles: roles, hasSelectedText: hasSelection, completed: completed)
    }

    /// What one Accessibility read gave.
    private enum Read {
        case value(CFTypeRef)
        /// The element doesn't have the attribute, or doesn't support it: a real answer.
        case absent
        /// The app didn't answer (`.cannotComplete`, past the messaging timeout), or the read
        /// failed some other way.
        case noAnswer
    }

    private static func read(_ element: AXUIElement, _ attribute: String) -> Read {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, attribute as CFString, &value) {
        case .success: return value.map { .value($0) } ?? .absent
        case .noValue, .attributeUnsupported: return .absent
        default: return .noAnswer
        }
    }

    /// The length of a selected-text range value; 0 for anything that isn't one.
    private static func length(ofRange value: CFTypeRef) -> Int {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return 0 }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return 0 }
        return range.length
    }
}
