import Foundation
import ReleaseCore
import XCTest

/// A key store in memory. `dropsWrites` makes `add` do nothing (as when `security -i`'s command failed).
final class FakeKeyStore: KeyStore {
    var items: [String: String] = [:]
    var dropsWrites = false
    private(set) var adds: [String] = []

    func contains(keyID: String) throws -> Bool { items[keyID] != nil }
    func privateKey(keyID: String) throws -> String? { items[keyID] }
    func add(keyID: String, privateKey: String) throws {
        adds.append(keyID)
        if !dropsWrites { items[keyID] = privateKey }
    }
}

/// Records what would be run, and answers with prepared results by the first argument.
final class FakeRunner: ProcessRunning {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
        var input: Data?
    }
    var calls: [Call] = []
    var answers: [String: ProcessResult] = [:]

    func run(_ executable: String, _ arguments: [String], input: Data?) throws -> ProcessResult {
        calls.append(Call(executable: executable, arguments: arguments, input: input))
        return answers[arguments.first ?? ""] ?? ProcessResult(status: 0)
    }
}

/// Collects what a command prints.
final class Printed {
    var out: [String] = []
    var err: [String] = []
    var input = Data()
    var inputIsTerminal = false

    var console: Console {
        Console(out: { self.out.append($0) }, err: { self.err.append($0) },
                readInput: { self.input }, inputIsTerminal: inputIsTerminal)
    }
    var all: String { (out + err).joined(separator: "\n") }
}

/// A folder in the temporary directory, removed when the test ends.
func makeTemporaryFolder(_ test: XCTestCase) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tactile-release-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
}

@discardableResult
func write(_ data: Data, to folder: URL, _ name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
}
