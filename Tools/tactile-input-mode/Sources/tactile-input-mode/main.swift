// tactile-input-mode: switches Windows-style touchscreens between mouse emulation and multi-touch,
// and tries other ways to make the wch.cn strip (27c0:0859) send real touches.
//
// Many touch panels start in mouse mode, reporting a single absolute pointer and nothing else.
// Windows and Linux switch them to multi-touch by writing the Digitizer "Input Mode" feature
// (usage page 0x0D, usage 0x52) when the panel connects. macOS never does. The panel forgets the
// setting whenever it loses power.
//
// The wch.cn strip accepts that write and carries on as a mouse. `try <method>` attempts other
// ways, within one rule: nothing is written but a feature report the touchscreen interface's own
// descriptor declares, holding only standard digitizer settings. Nothing is ever written to its
// mouse or vendor interface. Every `listen` or `try` ends by writing mouse emulation back.

import Foundation
import IOKit.hid
import InputModeCore

let usageText = """
Usage:
  tactile-input-mode                  show every touchscreen and its Input Mode as macOS reports it
  tactile-input-mode multitouch       write Input Mode 2 (multi-touch) to every touchscreen that has it.
                                      It stays in effect until `mouse` or a replug.
  tactile-input-mode mouse            write Input Mode 0 (mouse emulation) to every touchscreen that has it

  tactile-input-mode describe         the strip's interfaces, the reports they declare, and which
                                      methods apply. Opens nothing, writes nothing.
  tactile-input-mode listen           count what each interface sends, writing nothing first
  tactile-input-mode try <method>     try one way to make the strip send touches, then count what
                                      each interface sends. Methods: \(Method.allCases.map(\.rawValue).joined(separator: ", "))

Options for describe, listen and try:
  --seconds <n>                       how long to listen (default 5)
  --wait <n>                          on-plug: how long to wait to be unplugged, and to come back (default 30)
  --touchscreen <vendor:product[:serial]>
                                      which touchscreen, when more than one has an Input Mode setting.
                                      on-plug waits for the one connected now unless this is given.

Every listen and try ends by writing mouse emulation (21 00 00) and closing every interface,
including after Ctrl-C. Whether the panel obeys shows only in what it sends afterwards. If neither
that write nor its fallback is accepted while the strip is attached, the last line says
`NOT put back` and the exit code is 4.
Exit codes: 0 ran; 1 a write refused or not accepted, or a wait timed out; 2 no touchscreen;
3 Tactile or Touch Up running; 4 not put back; 64 usage.
"""

let modeNames = [0: "mouse emulation", 1: "single input", 2: "multi-touch"]

func describe(mode: Int) -> String { modeNames[mode] ?? "unknown mode \(mode)" }

/// Every interface with a Touch Screen top-level collection, in a stable order.
func touchscreenInterfaces() -> [HIDInterface] {
    hidDevices(matching: [kIOHIDDeviceUsagePageKey: 0x0D, kIOHIDDeviceUsageKey: 0x04])
        .map(HIDInterface.init)
        .sorted { $0.locationID < $1.locationID }
}

/// Asks for the current mode (GET_REPORT). On the wch.cn strip the answer is never the panel's own:
/// macOS hands back its copy of what was last written (0 until something is).
func readMode(_ device: IOHIDDevice, _ element: IOHIDElement) -> Int? {
    let placeholder = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
    var value = Unmanaged.passUnretained(placeholder)
    let result = IOHIDDeviceGetValueWithOptions(device, element, &value, IOHIDDeviceGetValueOptions.withUpdate.rawValue)
    guard result == kIOReturnSuccess else { return nil }
    return IOHIDValueGetIntegerValue(value.takeUnretainedValue())
}

/// The original commands: show, or write a mode to every touchscreen that has Input Mode.
/// A panel's mode can't be trusted when read, so a requested mode is always written.
func runModeCommand(_ requestedMode: Int?) -> Int32 {
    let interfaces = touchscreenInterfaces()
    if interfaces.isEmpty {
        say("No touchscreen found. Is it plugged in over USB?")
        return 2
    }
    var failures = 0
    for iface in interfaces {
        let name = "\(iface.product) (\(iface.usbID), USB location \(String(format: "0x%08x", iface.locationID)))"
        let opened = IOHIDDeviceOpen(iface.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            say("\(name): could not be opened (\(hex(opened))). Another app may have taken exclusive control of it.")
            failures += 1
            continue
        }
        defer { IOHIDDeviceClose(iface.device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let element = inputModeElement(iface.device) else {
            say("\(name): has no Input Mode setting, so there is nothing to switch.")
            continue
        }
        let current = readMode(iface.device, element)
        let currentText = current.map(describe(mode:)) ?? "unknown (the panel did not answer)"
        guard let target = requestedMode else {
            say("\(name): \(currentText), as macOS reports it. Some panels can't be read: this is then the last mode written.")
            continue
        }
        let written = writeInputModeElement(iface, target)
        if written == kIOReturnSuccess {
            var line = "\(name): wrote \(describe(mode: target)) (\(hex(written)), accepted). Whether the panel obeys shows only in what it sends."
            if target != 0 { line += " It stays in effect until `mouse` or a replug." }
            say(line)
        } else {
            say("\(name): writing \(describe(mode: target)) failed (\(hex(written))).")
            failures += 1
        }
    }
    return failures == 0 ? 0 : 1
}

// MARK: - Main

var arguments = Array(CommandLine.arguments.dropFirst())
var options = Options()

func takeOption(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    guard index + 1 < arguments.count else {
        say("\(flag) needs a value.\n\n\(usageText)")
        exit(64)
    }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

if let text = takeOption("--seconds") {
    guard let seconds = Double(text), seconds > 0, seconds <= 60 else { say("--seconds must be between 0 and 60."); exit(64) }
    options.seconds = seconds
}
if let text = takeOption("--wait") {
    guard let wait = Double(text), wait > 0, wait <= 300 else { say("--wait must be between 0 and 300."); exit(64) }
    options.wait = wait
}
if let text = takeOption("--touchscreen") {
    guard let filter = DeviceFilter(text) else {
        say("--touchscreen takes a USB ID such as 27c0:0859, or 27c0:0859:<serial>.")
        exit(64)
    }
    options.filter = filter
}

let status: Int32
switch (arguments.first, arguments.count) {
case (nil, _): status = runModeCommand(nil)
case ("multitouch"?, 1): status = runModeCommand(2)
case ("mouse"?, 1): status = runModeCommand(0)
case ("describe"?, 1): status = runDescribe(options)
case ("listen"?, 1): status = runListen(options)
case ("try"?, 2):
    guard let method = Method(rawValue: arguments[1]) else {
        say("Unknown method \(arguments[1]).\n\n\(usageText)")
        exit(64)
    }
    status = runTry(method, options)
case ("help"?, _), ("--help"?, _), ("-h"?, _):
    say(usageText)
    status = 0
default:
    say(usageText)
    status = 64
}
exit(status)
