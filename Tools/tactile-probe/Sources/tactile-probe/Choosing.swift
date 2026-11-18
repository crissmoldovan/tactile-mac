// Choosing the one touchscreen a survey records, and the display its instructions appear on.
// Pure: the connected touchscreens and displays come in as values, and the state file as a path.

import Foundation

// MARK: - The touchscreen

/// What choosing needs to know about one connected touchscreen.
struct TouchscreenCandidate: Equatable {
    let number: Int
    /// "222a:0001"
    let usbID: String
    /// "0x01141000"
    let locationID: String
    /// "ILITEK-TP by ILITEK"
    let name: String
}

enum ChoiceReason: Equatable {
    case named
    case onlyOneConnected

    /// Written into the survey file as `identifiedBy`.
    var identifiedBy: String {
        switch self {
        case .named: return IdentifiedBy.named
        case .onlyOneConnected: return IdentifiedBy.onlyOne
        }
    }
}

/// `touchscreens[].identifiedBy` in the survey file.
enum IdentifiedBy {
    static let named = "named with --touchscreen"
    static let onlyOne = "the only touchscreen connected"
    static let notChosen = "not chosen"
}

/// `touchscreens[].status` values this version adds.
enum SectionStatus {
    static let notChosen = "not chosen"
}

enum TouchscreenChoice: Equatable {
    case chosen(TouchscreenCandidate, reason: ChoiceReason)
    case noneConnected
    /// Several are connected and none was named: list them, and stop.
    case nameOne([TouchscreenCandidate])
    /// The one named is not connected.
    case notConnected(String, connected: [TouchscreenCandidate])
    /// Several connected touchscreens have the USB ID that was named.
    case cannotTellApart([TouchscreenCandidate])
}

func chooseTouchscreen(named usbID: String?, among connected: [TouchscreenCandidate]) -> TouchscreenChoice {
    guard !connected.isEmpty else { return .noneConnected }
    guard let usbID else {
        return connected.count == 1 ? .chosen(connected[0], reason: .onlyOneConnected) : .nameOne(connected)
    }
    let matches = connected.filter { $0.usbID.lowercased() == usbID.lowercased() }
    switch matches.count {
    case 0: return .notConnected(usbID, connected: connected)
    case 1: return .chosen(matches[0], reason: .named)
    default: return .cannotTellApart(matches)
    }
}

// MARK: - A display named on the command line

enum DisplaySearch: Equatable {
    case found(DisplayInfo)
    case notFound
    case ambiguous([DisplayInfo])
}

/// A display ID, else a whole name in any case, else a part of exactly one name.
func findDisplay(_ text: String, among displays: [DisplayInfo]) -> DisplaySearch {
    let wanted = text.trimmingCharacters(in: .whitespaces)
    if let id = UInt32(wanted), let display = displays.first(where: { $0.displayID == id }) { return .found(display) }
    let lower = wanted.lowercased()
    let whole = displays.filter { $0.name?.lowercased() == lower }
    if whole.count == 1 { return .found(whole[0]) }
    if whole.count > 1 { return .ambiguous(whole) }
    let partial = displays.filter { $0.name?.lowercased().contains(lower) == true }
    switch partial.count {
    case 0: return .notFound
    case 1: return .found(partial[0])
    default: return .ambiguous(partial)
    }
}

// MARK: - Tactile's state file

/// Where Tactile writes its state while it runs. It removes the file when it quits.
var defaultStateFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tactile/state.json")
}

/// The part of Tactile's state file (`AppSnapshot` in TactileApp) this tool reads. Everything is
/// optional: a field that is missing or of another kind makes the pairing "not known", never an error.
private struct StateFileSubset: Decodable {
    struct Touchscreen: Decodable {
        let usbID: String?
        let location: String?
        let pairedDisplayID: UInt32?
    }
    struct Display: Decodable {
        let id: UInt32?
        let uuid: String?
    }
    let touchscreens: [Touchscreen]?
    let displays: [Display]?
}

enum StatePairing: Equatable {
    case paired(DisplayInfo)
    /// Why not, in words for the terminal.
    case notKnown(String)
}

/// "0x01141000" and "01141000" are the same location.
private func sameLocation(_ a: String?, _ b: String) -> Bool {
    guard let a else { return false }
    func plain(_ s: String) -> String {
        let lower = s.lowercased()
        return lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
    }
    return plain(a) == plain(b)
}

/// The display Tactile paired this touchscreen with, if its state file says so and that display
/// is connected now. A display is found by its UUID when the state file has one, so a display ID
/// that has since moved to another monitor is never trusted.
func pairingFromStateFile(at url: URL, usbID: String, locationID: String, displays: [DisplayInfo]) -> StatePairing {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        let missing = (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileReadNoSuchFileError
        return .notKnown(missing ? "no state file at \(url.path) (Tactile removes it when it quits)" : "the state file could not be read")
    }
    guard let state = try? JSONDecoder().decode(StateFileSubset.self, from: data) else {
        return .notKnown("the state file could not be read")
    }
    var entries = (state.touchscreens ?? []).filter { $0.usbID?.lowercased() == usbID.lowercased() }
    if entries.count > 1 { entries = entries.filter { sameLocation($0.location, locationID) } }
    guard !entries.isEmpty else { return .notKnown("the state file does not list this touchscreen") }
    guard entries.count == 1 else { return .notKnown("the state file lists this touchscreen more than once") }
    guard let pairedID = entries[0].pairedDisplayID else { return .notKnown("Tactile has it as not paired") }
    if let uuid = state.displays?.first(where: { $0.id == pairedID })?.uuid {
        guard let display = displays.first(where: { $0.uuid?.lowercased() == uuid.lowercased() }) else {
            return .notKnown("the display it is paired with is not connected now")
        }
        return .paired(display)
    }
    guard let display = displays.first(where: { $0.displayID == pairedID }) else {
        return .notKnown("the display it is paired with is not connected now")
    }
    return .paired(display)
}

// MARK: - Which source wins

/// Where the display that shows the instructions came from. `touchscreens[].display.source` in
/// the survey file.
enum DisplaySource: String, Codable, Equatable {
    case argument = "--display"
    case stateFile = "state file"
    /// The person answered the survey's question.
    case question
}

enum DisplayChoiceResult: Equatable {
    case chosen(DisplayInfo, DisplaySource)
    case notKnown(String)
    /// `--display` named nothing, or several: the run stops, rather than show the instructions
    /// somewhere else.
    case badArgument(String)
}

func displayLine(_ d: DisplayInfo) -> String {
    let pixels = d.pixelSize.map { "\($0.width) × \($0.height)" } ?? "unknown size"
    return "\(d.displayID)  \(d.name ?? "(no name)")\(d.builtIn ? " (built-in)" : ""), \(pixels)"
}

func chooseDisplay(argument: String?, stateFile: URL, touchscreen: TouchscreenCandidate, displays: [DisplayInfo]) -> DisplayChoiceResult {
    if let argument {
        switch findDisplay(argument, among: displays) {
        case .found(let display):
            return .chosen(display, .argument)
        case .notFound:
            return .badArgument("No connected display is called \"\(argument)\". The displays are:\n"
                                + displays.map { "  " + displayLine($0) }.joined(separator: "\n"))
        case .ambiguous(let matches):
            return .badArgument("\"\(argument)\" fits more than one display:\n"
                                + matches.map { "  " + displayLine($0) }.joined(separator: "\n")
                                + "\nUse its whole name or its ID.")
        }
    }
    switch pairingFromStateFile(at: stateFile, usbID: touchscreen.usbID, locationID: touchscreen.locationID, displays: displays) {
    case .paired(let display): return .chosen(display, .stateFile)
    case .notKnown(let why): return .notKnown(why)
    }
}

// MARK: - Which displays show what

/// The chosen display shows the instruction; every other display that is not built in says
/// "Not this one". With no display known, every external display shows the instruction.
/// `drawable` are the displays that have a screen of their own to draw on (nil: all of them). A
/// display mirrored onto another has none; when the chosen one is such a display, no window is
/// shown anywhere, since a "Not this one" on the display it mirrors would appear on its glass too.
struct BoardPlan: Equatable {
    let target: DisplayInfo?
    let instructionDisplays: [DisplayInfo]
    let notThisOneDisplays: [DisplayInfo]
    let targetCannotBeDrawnOn: Bool
    var knowsTheDisplay: Bool { target != nil }

    init(target: DisplayInfo?, displays: [DisplayInfo], drawable: Set<UInt32>? = nil) {
        self.target = target
        func canDraw(_ d: DisplayInfo) -> Bool { drawable?.contains(d.displayID) ?? true }
        let external = displays.filter { !$0.builtIn && canDraw($0) }
        if let target {
            targetCannotBeDrawnOn = !canDraw(target)
            instructionDisplays = targetCannotBeDrawnOn ? [] : [target]
            notThisOneDisplays = targetCannotBeDrawnOn ? [] : external.filter { $0.displayID != target.displayID }
        } else {
            targetCannotBeDrawnOn = false
            instructionDisplays = external
            notThisOneDisplays = []
        }
    }
}

/// The numbered list the survey asks from when no display is known: every external display,
/// numbered by its display ID, as `list` and `--display` number them.
func displayQuestionChoices(_ displays: [DisplayInfo]) -> [DisplayChoice] {
    displays.filter { !$0.builtIn }.map { DisplayChoice(number: Int($0.displayID), displayID: $0.displayID, name: $0.name) }
}
