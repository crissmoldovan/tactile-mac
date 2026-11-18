// `tactile-probe list`: what is attached, as text, and optionally as JSON.

import Foundation

func buildList(_ touchscreens: [ProbeTouchscreen]) -> ListData {
    ListData(environment: environmentInfo(), displays: allDisplays(), touchscreens: touchscreens.map(touchscreenInfo))
}

private func mm(_ v: Double) -> String { String(format: "%.1f", v) }

private func fieldText(_ name: String, _ f: FieldPresence) -> String {
    guard f.present else { return name }
    var parts: [String] = []
    if let bits = f.bits { parts.append("\(bits) bit\(bits == 1 ? "" : "s")") }
    if let lo = f.logicalMin, let hi = f.logicalMax, !(lo == 0 && hi == 1) { parts.append("\(lo)…\(hi)") }
    return parts.isEmpty ? name : "\(name) (\(parts.joined(separator: ", ")))"
}

private func axisText(_ name: String, _ a: AxisInfo?) -> String {
    guard let a else { return "\(name): not reported" }
    var text = "\(name): logical \(a.logicalMin)…\(a.logicalMax), physical \(a.physicalMin)…\(a.physicalMax), unit \(a.unitName), exponent \(a.exponent)"
    text += a.sizeMM.map { " -> \(mm($0)) mm" } ?? " -> no physical size"
    return text
}

func printList(_ list: ListData) {
    let env = list.environment
    say("\(toolName) \(toolVersion) on macOS \(env.macOSVersion)\(env.macOSBuild.map { " (\($0))" } ?? "")\(env.hardwareModel.map { ", \($0)" } ?? "")")
    say("Input Monitoring for this terminal: \(env.inputMonitoring); Accessibility: \(env.accessibility ? "granted" : "not granted")")
    say("")
    say("Displays (\(list.displays.count))")
    for d in list.displays {
        var tags: [String] = []
        if d.builtIn { tags.append("built-in") }
        if d.main { tags.append("main") }
        if !d.active { tags.append("inactive") }
        if d.asleep { tags.append("asleep") }
        say("  \(d.displayID)  \(d.name ?? "(no name)")\(tags.isEmpty ? "" : " (\(tags.joined(separator: ", ")))")")
        let pixels = d.pixelSize.map { "\($0.width) × \($0.height) pixels" } ?? "unknown pixels"
        let refresh = d.refreshRateHz.map { String(format: ", %.0f Hz", $0) } ?? ""
        say(String(format: "      %@ (%.0f × %.0f points), %@ × %@ mm%@, rotation %.0f°",
                   pixels, d.pointSize.width, d.pointSize.height, mm(d.physicalSizeMM.width), mm(d.physicalSizeMM.height), refresh, d.rotationDegrees))
        var mirror = "not mirrored"
        if d.mirroring.inMirrorSet {
            mirror = d.mirroring.mirrorsDisplayID.map { "mirrors display \($0)" } ?? "in a mirror set (primary \(d.mirroring.primaryDisplayID))"
        }
        say(String(format: "      origin (%.0f, %.0f) in the global arrangement, %@", d.origin.x, d.origin.y, mirror))
        say(String(format: "      vendor 0x%04x, model 0x%04x, serial 0x%08x, UUID %@", d.vendorNumber, d.modelNumber, d.serialNumber, d.uuid ?? "unknown"))
    }
    say("")
    say("Touchscreens (\(list.touchscreens.count))")
    if list.touchscreens.isEmpty { say("  None found. Is one plugged in over USB?") }
    for t in list.touchscreens {
        say("  Touchscreen \(t.number): \(t.product ?? "(no name)") by \(t.manufacturer ?? "(unknown maker)")")
        var line = "      USB \(t.usbID), serial \(t.serialNumber ?? "none"), location \(t.locationID)"
        if let speed = t.usbDevice?.speed { line += ", \(speed)" }
        say(line)
        var chain = t.usbHubs.map { hub -> String in
            var bits: [String] = []
            if let v = hub.vendorName { bits.append(v) }
            if let id = hub.usbID { bits.append(id) }
            if let loc = hub.locationID { bits.append(loc) }
            return "\(hub.productName ?? hub.registryName ?? "hub")\(bits.isEmpty ? "" : " (\(bits.joined(separator: ", ")))")"
        }
        if let controller = t.usbController { chain.append(controller) }
        say("      Behind: \(chain.isEmpty ? "nothing (directly on the controller)" : chain.joined(separator: " > "))")
        say("      HID interfaces:")
        for i in t.interfaces {
            let pad = i.key.padding(toLength: max(12, i.key.count), withPad: " ", startingAt: 0)
            let usages = i.topLevelUsages.map { "\($0.text)\($0.name.map { " \($0)" } ?? "")" }.joined(separator: ", ")
            say("        \(pad)  top-level \(usages)")
            var groups: [String] = []
            for type in [ReportType.input, .output, .feature] {
                let reports = i.reports.filter { $0.type == type }
                guard !reports.isEmpty else { continue }
                let items = reports.map { r -> String in
                    var extra = "\(r.bytes) bytes"
                    if let kind = r.decodedAs { extra += ", \(kind)" }
                    if let slots = r.fingerSlots { extra += ", \(slots) finger slots" }
                    return "\(i.usesReportIDs ? r.idHex : "(no ID)") (\(extra))"
                }
                groups.append("\(type.rawValue) \(items.joined(separator: ", "))")
            }
            let blank = String(repeating: " ", count: pad.count)
            say("        \(blank)  \(groups.isEmpty ? "no reports" : groups.joined(separator: "; "))")
            say("        \(blank)  descriptor: \(i.reportDescriptorLength ?? 0) bytes; parser \(i.parserCheck)")
            for f in i.featureReports {
                let bad = f.startsWithReportID == false ? "; MALFORMED: does not start with its report ID" : ""
                say("        \(blank)  feature \(f.idHex) raw: \(f.bytes ?? "unreadable") (\(f.contains.joined(separator: ", ")); IOReturn \(f.ioReturn)\(bad))")
            }
        }
        guard let touch = t.touchInterface else {
            say("      No touch interface could be read.")
            continue
        }
        say("      Touch interface (\(touch.interfaceKey)):")
        let ccm = touch.contactCountMaximum
        if ccm.present {
            say("        Contact Count Maximum: \(ccm.value.map(String.init) ?? "unreadable") (feature report \(ccm.reportID.map(hexByte) ?? "?"), IOReturn \(ccm.ioReturn ?? "none"))")
            if ccm.valueTrusted == false { say("          Not a real reading: the panel's answer \(ccm.rawReport ?? "") is malformed.") }
        } else {
            say("        Contact Count Maximum: not declared")
        }
        let hybrid = touch.hybridModeWouldApply.map { $0 ? "yes" : "no" } ?? "unknown"
        say("        Finger collections: \(touch.fingerCollections); hybrid mode would apply: \(hybrid)")
        let mode = touch.inputMode
        if mode.present {
            say("        Input Mode: present (feature report \(mode.reportID.map(hexByte) ?? "?")), now \(mode.value.map { "\($0) = \(describeMode($0))" } ?? "unreadable") (IOReturn \(mode.ioReturn ?? "none"))")
            if mode.valueTrusted == false {
                say("          Not a real reading: the panel answers GET_REPORT with \(mode.rawReport ?? "?"), which does not start with")
                say("          its report ID, so IOKit returns its own default. The panel's real mode cannot be read back.")
            }
        } else {
            say("        Input Mode: not present")
        }
        say("        \(axisText("X", touch.x))")
        say("        \(axisText("Y", touch.y))")
        if let s = touch.surfaceSizeMM { say("        Surface: \(mm(s.width)) × \(mm(s.height)) mm") }
        let ff = touch.fingerFields
        let all: [(String, FieldPresence)] = [("tip switch", ff.tipSwitch), ("in range", ff.inRange), ("confidence", ff.confidence),
                                              ("contact ID", ff.contactID), ("width", ff.width), ("height", ff.height),
                                              ("azimuth", ff.azimuth), ("pressure", ff.pressure)]
        let present = all.filter { $0.1.present }.map { fieldText($0.0, $0.1) }
        let missing = all.filter { !$0.1.present }.map(\.0)
        say("        Per-finger fields present: \(present.isEmpty ? "none" : present.joined(separator: ", "))")
        say("        Per-finger fields missing: \(missing.isEmpty ? "none" : missing.joined(separator: ", "))")
        say("        Report fields: \(touch.contactCount.present ? fieldText("contact count", touch.contactCount) : "no contact count"), "
            + "\(touch.scanTime.present ? fieldText("scan time", touch.scanTime) : "no scan time")")
        say("        Input report \(touch.inputReportID.map(hexByte) ?? "?"): \(touch.inputReportBytes.map(String.init) ?? "?") bytes")
    }
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}
