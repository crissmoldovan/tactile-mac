import Foundation

/// Where the update key's private half is kept. The real one is the login keychain, through
/// `/usr/bin/security`; the tests use a fake, so no test touches a real Keychain item.
public protocol KeyStore {
    /// Whether there is an item for this keyId. Never reads the secret.
    func contains(keyID: String) throws -> Bool
    /// The stored private key (base64), or nil when there is no item for this keyId.
    func privateKey(keyID: String) throws -> String?
    /// Stores a new item. The caller has checked that there is none, and reads it back afterwards.
    func add(keyID: String, privateKey: String) throws
}

public struct KeyStoreError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct ProcessResult: Equatable {
    public var status: Int32
    public var output: Data
    public var errorOutput: Data
    public init(status: Int32, output: Data = Data(), errorOutput: Data = Data()) {
        self.status = status
        self.output = output
        self.errorOutput = errorOutput
    }
}

/// Runs a program and collects what it prints. Behind a protocol so the tests can see the exact
/// arguments and standard input `SecurityToolKeyStore` would pass, without running `security`.
public protocol ProcessRunning {
    func run(_ executable: String, _ arguments: [String], input: Data?) throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], input: Data?) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        if let input { inPipe.fileHandleForWriting.write(input) }
        try? inPipe.fileHandleForWriting.close()
        // What `security` prints here is a few hundred bytes at most, well under a pipe's buffer, so
        // reading one pipe to its end and then the other cannot block.
        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: output, errorOutput: errorOutput)
    }
}

/// The update key in the login keychain, as the contract says: a generic password, service
/// "Tactile update signing key", account the keyId, data the base64 private key. Created and read only
/// through `/usr/bin/security`; created with `-T /usr/bin/security`, so reading it raises no Keychain
/// prompt; written through `security -i` on standard input, so the key is never in a process list.
/// Nothing `security` prints is passed on, except the first line of an error from a command that does
/// not handle the secret.
public struct SecurityToolKeyStore: KeyStore {
    public static let securityPath = "/usr/bin/security"
    /// `security`'s status when there is no such item (errSecItemNotFound).
    static let notFound: Int32 = 44

    let runner: ProcessRunning
    let service: String

    public init(runner: ProcessRunning = SystemProcessRunner(), service: String = UpdateKey.keychainService) {
        self.runner = runner
        self.service = service
    }

    public func contains(keyID: String) throws -> Bool {
        try checkKeyID(keyID)
        // Without -w or -g, find-generic-password prints the item's attributes only, never its data.
        let result = try runner.run(Self.securityPath, ["find-generic-password", "-s", service, "-a", keyID], input: nil)
        switch result.status {
        case 0: return true
        case Self.notFound: return false
        default: throw KeyStoreError("security could not look for the update key \(keyID) (status \(result.status))\(Self.firstLine(result.errorOutput)).")
        }
    }

    public func privateKey(keyID: String) throws -> String? {
        try checkKeyID(keyID)
        let result = try runner.run(Self.securityPath, ["find-generic-password", "-s", service, "-a", keyID, "-w"], input: nil)
        switch result.status {
        case 0:
            return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        case Self.notFound:
            return nil
        default:
            // Its error output is not passed on: on this command it could, in principle, hold the data.
            throw KeyStoreError("security could not read the update key \(keyID) (status \(result.status)). Is the login keychain unlocked?")
        }
    }

    public func add(keyID: String, privateKey: String) throws {
        try checkKeyID(keyID)
        let keychain = try loginKeychain()
        let line = try Self.addCommand(service: service, keyID: keyID, privateKey: privateKey, keychain: keychain)
        // `security -i` answers 0 even when its command failed, and what it prints is not passed on;
        // the caller reads the item back to know it is there.
        _ = try runner.run(Self.securityPath, ["-i"], input: Data(line.utf8))
    }

    /// The line `security -i` reads on standard input to create the item. Every argument is quoted, and
    /// none may hold a quote or a backslash, so none can end early or run into the next.
    static func addCommand(service: String, keyID: String, privateKey: String, keychain: String) throws -> String {
        for value in [service, keyID, privateKey, keychain] where value.contains("\"") || value.contains("\\") || value.contains("\n") {
            throw KeyStoreError("A value for the keychain command has a quote, a backslash or a line break, which it can't carry.")
        }
        return "add-generic-password -s \"\(service)\" -a \"\(keyID)\" -T \"\(securityPath)\" -w \"\(privateKey)\" \"\(keychain)\"\n"
    }

    /// The path of the login keychain (`security login-keychain` prints it quoted and indented).
    func loginKeychain() throws -> String {
        let result = try runner.run(Self.securityPath, ["login-keychain"], input: nil)
        let path = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard result.status == 0, path.hasPrefix("/") else {
            throw KeyStoreError("security could not name the login keychain (status \(result.status))\(Self.firstLine(result.errorOutput)).")
        }
        return path
    }

    private func checkKeyID(_ keyID: String) throws {
        guard UpdateKey.isValidKeyID(keyID) else { throw KeyStoreError("'\(keyID)' is not a keyId (letters, digits, '.', '_' and '-', at most 32).") }
    }

    private static func firstLine(_ data: Data) -> String {
        let line = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? "" : ": \(line)"
    }
}
