import CoreGraphics
import Foundation
import TactileReading
import TactileScreens

/// One connection of one touchscreen. Never reused while the app runs: a touchscreen that is
/// unplugged and plugged back in gets a new handle.
public struct DeviceHandle: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public var description: String { "device-\(rawValue)" }
}

/// What the app asks of a touchscreen. A touchscreen that has just connected is `released`.
public enum DeviceState: String, Codable, Sendable { case taken, released }

/// What happened when Tactile last switched the panel to multi-touch.
public enum InputModeStatus: String, Codable, Sendable {
    case notSwitched, switchedToMultiTouch, switchRefused, noInputModeSetting
}

/// Where this touchscreen's touches are coming from, decided afresh each time it is taken.
public enum TouchOrigin: String, Codable, Sendable {
    /// Taken, and nothing has arrived yet.
    case undetermined
    /// Its touchscreen interface sends touches.
    case touchInterface
    /// It stayed in mouse mode: one finger, read from its mouse interface.
    case mouseInterface
    /// Its reports can't be read at all: no usable descriptor, or it could not be opened.
    case unreadable
}

public enum ExclusiveAccess: String, Codable, Sendable { case notHeld, held, failed }

public struct DeviceStatus: Equatable, Sendable {
    public var state: DeviceState
    public var inputMode: InputModeStatus
    public var touchOrigin: TouchOrigin
    public var exclusive: ExclusiveAccess
    public init(state: DeviceState = .released, inputMode: InputModeStatus = .notSwitched,
                touchOrigin: TouchOrigin = .undetermined, exclusive: ExclusiveAccess = .notHeld) {
        self.state = state; self.inputMode = inputMode; self.touchOrigin = touchOrigin; self.exclusive = exclusive
    }
}

public struct ConnectedTouchscreen: Equatable, Sendable {
    public let handle: DeviceHandle
    public var facts: TouchscreenFacts
    /// The most contacts one report can carry, from the descriptor; 1 when unknown.
    public var maxContacts: Int
    /// The glass size the panel itself reports, when it reports one.
    public var reportedSizeMM: CGSize?
    public var hasMouseInterface: Bool
    /// Whether its touch reports carry contact size or confidence, from the descriptor: what palm
    /// rejection needs to tell a palm from a finger. False when the descriptor can't be read.
    public var reportsPalms: Bool
    public var status: DeviceStatus
    public init(handle: DeviceHandle, facts: TouchscreenFacts, maxContacts: Int, reportedSizeMM: CGSize?,
                hasMouseInterface: Bool, reportsPalms: Bool, status: DeviceStatus = DeviceStatus()) {
        self.handle = handle; self.facts = facts; self.maxContacts = maxContacts
        self.reportedSizeMM = reportedSizeMM; self.hasMouseInterface = hasMouseInterface
        self.reportsPalms = reportsPalms; self.status = status
    }
}

@MainActor
public protocol TouchscreenSourceDelegate: AnyObject {
    func touchscreenConnected(_ touchscreen: ConnectedTouchscreen)
    /// Its status, or whether it has a mouse interface, changed.
    func touchscreenChanged(_ touchscreen: ConnectedTouchscreen)
    func touchscreenDisconnected(_ handle: DeviceHandle)
    /// A complete frame of contacts as glass points, from a taken touchscreen. An empty frame means
    /// every finger has lifted.
    func touchscreen(_ handle: DeviceHandle, produced frame: ContactFrame)
}

/// The live USB side. The app decides; the source does. It never discards touches itself.
@MainActor
public protocol TouchscreenSource: AnyObject {
    var delegate: TouchscreenSourceDelegate? { get set }
    /// Begins watching. Every touchscreen already connected is announced through the delegate.
    func start()
    /// Releases every touchscreen and stops watching. Done by the time it returns.
    func stop()
    /// Takes a touchscreen over or lets it go. Asking for the state it already has does nothing.
    func setState(_ state: DeviceState, for handle: DeviceHandle)
    /// Switches every taken touchscreen to multi-touch again, as a take does (its feature reports
    /// read, then Input Mode 2 written where it has the setting). The app doesn't call it: it
    /// takes every touchscreen again on wake.
    func refresh()
}
