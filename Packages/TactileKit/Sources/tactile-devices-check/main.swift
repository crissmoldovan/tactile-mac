// A check of the device layer against the touchscreens plugged into this Mac, for scripts and
// diagnostics, to run while nobody touches them. It uses HIDTouchscreenSource and nothing else of
// the app. It opens no window and posts no event.
//
//   tactile-devices-check list               Lists every touchscreen. Opens nothing.
//   tactile-devices-check take [--seconds N] Takes every touchscreen for N seconds (1 to 5, default
//                                            3), printing each status change and counting frames,
//                                            then releases them all and prints their final status.

import Darwin
import Foundation
import IOKit.hid
import TactileDevices
import TactileReading
import TactileScreens

@MainActor
final class Check: TouchscreenSourceDelegate {
    let source = HIDTouchscreenSource()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private(set) var order: [DeviceHandle] = []
    private(set) var latest: [DeviceHandle: ConnectedTouchscreen] = [:]
    private var frames: [DeviceHandle: Int] = [:]
    private var framesWithContacts: [DeviceHandle: Int] = [:]
    /// Whether changes are printed as they happen.
    var narrating = false
    /// SIGINT, SIGTERM, SIGHUP and SIGQUIT, kept alive for the whole run.
    var signalSources: [DispatchSourceSignal] = []

    init() {
        source.delegate = self
    }

    // MARK: TouchscreenSourceDelegate

    func touchscreenConnected(_ touchscreen: ConnectedTouchscreen) {
        order.append(touchscreen.handle)
        latest[touchscreen.handle] = touchscreen
        if narrating { say("\(stamp()) \(touchscreen.handle) connected: \(touchscreen.facts.name)") }
    }

    func touchscreenChanged(_ touchscreen: ConnectedTouchscreen) {
        latest[touchscreen.handle] = touchscreen
        if narrating {
            say("\(stamp()) \(touchscreen.handle) changed: \(Self.describe(touchscreen.status)); mouse interface \(touchscreen.hasMouseInterface ? "yes" : "no")")
        }
    }

    func touchscreenDisconnected(_ handle: DeviceHandle) {
        if narrating { say("\(stamp()) \(handle) disconnected") }
        latest[handle] = nil
    }

    func touchscreen(_ handle: DeviceHandle, produced frame: ContactFrame) {
        frames[handle, default: 0] += 1
        if !frame.contacts.isEmpty { framesWithContacts[handle, default: 0] += 1 }
    }

    // MARK: Commands

    func list() -> Int32 {
        say(Self.inputMonitoringLine())
        source.start()
        printTouchscreens()
        source.stop()
        return 0
    }

    func take(seconds: Double) -> Int32 {
        say(Self.inputMonitoringLine())
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            say("Not taking anything: Input Monitoring has not been decided for this process, and opening a")
            say("mouse interface could make macOS ask. Run `list`, or decide Input Monitoring first.")
            return 3
        }
        let others = Self.conflictingProcesses()
        if !others.isEmpty {
            say("Not taking anything: these also read touchscreens and are running:")
            for other in others { say("  \(other)") }
            return 3
        }
        source.start()
        printTouchscreens()
        guard !order.isEmpty else { return 0 }

        say("")
        say("Taking every touchscreen for \(Self.seconds(seconds)) s. Nobody touches them.")
        narrating = true
        for handle in order where latest[handle] != nil { source.setState(.taken, for: handle) }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        say("\(stamp()) releasing")
        for handle in order where latest[handle] != nil { source.setState(.released, for: handle) }
        narrating = false

        say("")
        say("Final status:")
        for handle in order {
            guard let touchscreen = latest[handle] else {
                say("  \(handle): disconnected during the check")
                continue
            }
            say("  \(handle) \"\(touchscreen.facts.name)\": \(Self.describe(touchscreen.status))")
            say("      frames: \(frames[handle, default: 0]) (\(framesWithContacts[handle, default: 0]) with a finger down)")
        }
        source.stop()
        return 0
    }

    /// Releases everything at once, on SIGINT, SIGTERM, SIGHUP or SIGQUIT.
    func interrupt(_ signal: Int32) -> Never {
        // Released first: after SIGHUP the terminal is gone, and nothing printed may come before it.
        source.stop()
        say("")
        say("Interrupted: every touchscreen was released.")
        exit(128 + signal)
    }

    // MARK: Printing

    private func printTouchscreens() {
        if order.isEmpty {
            say("No touchscreen is connected.")
            return
        }
        for handle in order {
            guard let t = latest[handle] else { continue }
            let f = t.facts
            say("")
            say("\(t.handle)  \"\(f.name)\"  USB \(String(format: "%04x:%04x", f.vendorID, f.productID))  serial \"\(f.serial)\"  location \(String(format: "0x%08x", f.locationID))")
            let size = t.reportedSizeMM.map { String(format: "%.1f × %.1f mm", $0.width, $0.height) } ?? "none"
            say("    contacts per report: \(t.maxContacts)   reported size: \(size)   mouse interface: \(t.hasMouseInterface ? "yes" : "no")")
            say("    status: \(Self.describe(t.status))")
        }
    }

    private func stamp() -> String {
        String(format: "[+%.3f s]", ProcessInfo.processInfo.systemUptime - startedAt)
    }

    static func describe(_ status: DeviceStatus) -> String {
        "\(status.state.rawValue), input mode \(status.inputMode.rawValue), touches \(status.touchOrigin.rawValue), exclusive access \(status.exclusive.rawValue)"
    }

    static func seconds(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    static func inputMonitoringLine() -> String {
        let access: String
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: access = "granted"
        case kIOHIDAccessTypeDenied: access = "denied"
        default: access = "not decided"
        }
        return "Input Monitoring for this process (as IOHIDCheckAccess reports it, without asking): \(access)"
    }

    /// Tactile or Touch Up, running now: they read the same touchscreens.
    static func conflictingProcesses() -> [String] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var found: [String] = []
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(max(0, count))) where pid > 0 && pid != getpid() {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let text = String(cString: path)
            if text.contains("Tactile.app/Contents/MacOS") || text.contains("Touch Up") { found.append("\(pid) \(text)") }
        }
        return found
    }
}

/// Prints a line. A failed write (the terminal gone, the pipe closed) is ignored, never fatal.
func say(_ text: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8))
}

func usage() -> Int32 {
    say("usage: tactile-devices-check list")
    say("       tactile-devices-check take [--seconds N]   (N from 1 to 5; default 3)")
    return 2
}

@MainActor
func run(_ arguments: [String]) -> Int32 {
    guard let command = arguments.first else { return usage() }
    switch command {
    case "list":
        guard arguments.count == 1 else { return usage() }
        return Check().list()
    case "take":
        var seconds = 3.0
        let rest = Array(arguments.dropFirst())
        if !rest.isEmpty {
            guard rest.count == 2, rest[0] == "--seconds", let value = Double(rest[1]), value >= 1, value <= 5 else { return usage() }
            seconds = value
        }
        let check = Check()
        // Suspending (Ctrl-Z) would leave the touchscreens held while nothing reads them: ignored.
        signal(SIGTSTP, SIG_IGN)
        // Output to a pipe whose reader has gone fails as a write error rather than killing the tool.
        signal(SIGPIPE, SIG_IGN)
        // Ctrl-C, a kill, a closed terminal and Ctrl-\ all release everything first.
        for number in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { check.interrupt(number) } }
            source.resume()
            check.signalSources.append(source)
        }
        return check.take(seconds: seconds)
    default:
        return usage()
    }
}

let status = MainActor.assumeIsolated { run(Array(CommandLine.arguments.dropFirst())) }
exit(status)
