// The command line, parsed into a value. Pure: nothing here touches a device or the screen.

import Foundation

let usageText = """
Usage:
  tactile-probe list [--json <path>]
  tactile-probe survey [--touchscreen <vendor:product>] [--display <display ID or name>]
                       [--from <take> | --only <take,take,…>] [--out <dir>] [--step-timeout <seconds>]
                       [--no-windows]
  tactile-probe takes
  tactile-probe preview --out <dir>
  tactile-probe --version

  survey      surveys ONE touchscreen. With two connected, name it: --touchscreen 222a:0001.
              Its instructions appear on the display from --display; else on the one Tactile
              paired it with; else the survey asks.
  --from 16   starts at take 16 and runs to the end. --only 16,18 or --only 16-20 runs just those.
  --no-windows  nothing on the glass: the takes are in the terminal only, as in version 1.0.
  takes       lists the takes and their numbers.
  preview     draws what the windows on the glass look like into PNG files. It opens no window
              and no device.
"""

struct CommandLineError: Error, Equatable, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// Which takes a survey runs.
enum TakeSelection: Equatable {
    case all
    case from(Int)
    /// Sorted, without duplicates.
    case only([Int])

    var numbers: [Int] {
        switch self {
        case .all: return Array(1...Takes.count)
        case .from(let first): return Array(first...Takes.count)
        case .only(let list): return list
        }
    }

    var takes: [TakeSpec] { numbers.compactMap(Takes.take) }

    /// For the survey file's name: "" for every take, else "-takes16to22", "-takes16to20+22", "-takes21+22", "-take9".
    var fileNameTag: String {
        if self == .all { return "" }
        let list = numbers
        if list.count == 1 { return "-take\(list[0])" }
        var runs: [String] = []
        var i = 0
        while i < list.count {
            var j = i
            while j + 1 < list.count, list[j + 1] == list[j] + 1 { j += 1 }
            // Three or more in a row become a range; a pair stays a pair.
            if j - i >= 2 {
                runs.append("\(list[i])to\(list[j])")
            } else {
                runs += list[i...j].map(String.init)
            }
            i = j + 1
        }
        return "-takes" + runs.joined(separator: "+")
    }

    /// "takes 16 to 22 (7 takes)", for the terminal.
    var text: String {
        let list = numbers
        if list.count == 1 { return "take \(list[0]) only" }
        switch self {
        case .all: return "all \(Takes.count) takes"
        case .from(let first): return "takes \(first) to \(Takes.count) (\(list.count) takes)"
        case .only:
            let head = list.dropLast().map(String.init).joined(separator: ", ")
            return "takes \(head) and \(list.last!) (\(list.count) takes)"
        }
    }
}

struct SurveyOptions: Equatable {
    /// A USB ID, "222a:0001", in lower case.
    var touchscreen: String?
    /// As typed: a display ID or a name.
    var display: String?
    var selection: TakeSelection = .all
    var outDir: String?
    var stepTimeout: Double = 30
    /// The instructions on the glass. Off only with --no-windows.
    var showsWindows = true
    /// The arguments after `survey`, as typed, for the survey file.
    var arguments: [String] = []
}

enum ProbeCommand: Equatable {
    case list(jsonPath: String?)
    case survey(SurveyOptions)
    case takes
    case preview(outDir: String)
    case version
    case help
}

/// Reads "--name value" pairs, and switches that take no value (their value is ""); an unknown
/// name, a missing value or a repeated name is an error.
private func optionPairs(_ args: ArraySlice<String>, allowed: Set<String>, switches: Set<String> = []) throws -> [String: String] {
    var result: [String: String] = [:]
    var i = args.startIndex
    while i < args.endIndex {
        let name = args[i]
        if switches.contains(name) {
            guard result[name] == nil else { throw CommandLineError("\(name) is given twice.") }
            result[name] = ""
            i += 1
            continue
        }
        guard allowed.contains(name) else { throw CommandLineError("Unknown option \(name).") }
        guard i + 1 < args.endIndex else { throw CommandLineError("\(name) needs a value.") }
        guard result[name] == nil else { throw CommandLineError("\(name) is given twice.") }
        result[name] = args[i + 1]
        i += 2
    }
    return result
}

private func takeNumber(_ text: String, option: String) throws -> Int {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let n = Int(trimmed), (1...Takes.count).contains(n) else {
        throw CommandLineError("\(option) needs take numbers from 1 to \(Takes.count); \"\(text)\" is not one. `tactile-probe takes` lists them.")
    }
    return n
}

/// "16,17,22" or "16-20,22": sorted, without duplicates.
func parseTakeList(_ text: String) throws -> [Int] {
    let parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandLineError("--only needs take numbers, such as 16,17 or 16-20.") }
    var numbers = Set<Int>()
    for part in parts {
        let ends = part.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        switch ends.count {
        case 1:
            numbers.insert(try takeNumber(part, option: "--only"))
        case 2:
            let low = try takeNumber(ends[0], option: "--only")
            let high = try takeNumber(ends[1], option: "--only")
            guard low <= high else { throw CommandLineError("--only: \"\(part)\" runs backwards; write it as \(high)-\(low).") }
            numbers.formUnion(low...high)
        default:
            throw CommandLineError("--only: \"\(part)\" is not a take number or a range such as 16-20.")
        }
    }
    return numbers.sorted()
}

/// "222a:0001": four hex digits, a colon, four hex digits. Returned in lower case.
func parseUSBID(_ text: String) -> String? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
    return text.lowercased()
}

func parseCommandLine(_ args: [String]) throws -> ProbeCommand {
    switch args.first {
    case "list"?:
        let opts = try optionPairs(args.dropFirst(), allowed: ["--json"])
        return .list(jsonPath: opts["--json"])

    case "survey"?:
        let opts = try optionPairs(args.dropFirst(),
                                   allowed: ["--touchscreen", "--display", "--from", "--only", "--out", "--step-timeout"],
                                   switches: ["--no-windows"])
        var options = SurveyOptions()
        options.arguments = Array(args.dropFirst())
        if let text = opts["--touchscreen"] {
            guard let id = parseUSBID(text) else {
                throw CommandLineError("--touchscreen needs the touchscreen's USB ID as vendor:product, such as 222a:0001; \"\(text)\" is not one. `tactile-probe list` shows them.")
            }
            options.touchscreen = id
        }
        if let text = opts["--display"] {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw CommandLineError("--display needs a display ID or name, such as HDMI.") }
            options.display = trimmed
        }
        if opts["--from"] != nil, opts["--only"] != nil {
            throw CommandLineError("Use --from or --only, not both.")
        }
        if let text = opts["--from"] {
            options.selection = .from(try takeNumber(text, option: "--from"))
        }
        if let text = opts["--only"] {
            options.selection = .only(try parseTakeList(text))
        }
        options.outDir = opts["--out"]
        options.showsWindows = opts["--no-windows"] == nil
        if let text = opts["--step-timeout"] {
            guard let value = Double(text), value > 0, value.isFinite else { throw CommandLineError("--step-timeout needs a number of seconds above 0.") }
            options.stepTimeout = value
        }
        return .survey(options)

    case "takes"?:
        _ = try optionPairs(args.dropFirst(), allowed: [])
        return .takes

    case "preview"?:
        let opts = try optionPairs(args.dropFirst(), allowed: ["--out"])
        guard let out = opts["--out"] else { throw CommandLineError("preview needs --out <dir>.") }
        return .preview(outDir: out)

    case "--version"?, "version"?:
        return .version

    case "--help"?, "-h"?, "help"?:
        return .help

    case let other?:
        throw CommandLineError("Unknown command \(other).")

    case nil:
        throw CommandLineError("Name a command.")
    }
}
