import CryptoKit
import Foundation

/// Where the tool prints and what it reads. The real one is the terminal; the tests collect the text.
public struct Console {
    public var out: (String) -> Void
    public var err: (String) -> Void
    public var readInput: () -> Data
    /// Standard input is a terminal (then `import` refuses: the key would have to be typed or pasted
    /// where it can be seen).
    public var inputIsTerminal: Bool

    public init(out: @escaping (String) -> Void, err: @escaping (String) -> Void,
                readInput: @escaping () -> Data, inputIsTerminal: Bool) {
        self.out = out
        self.err = err
        self.readInput = readInput
        self.inputIsTerminal = inputIsTerminal
    }
}

/// tactile-release's commands. Exit status: 0 done, 1 refused or failed, 2 a usage error.
public enum Tool {
    public static let usage = """
    usage: tactile-release <command> [options]

    The update key (Ed25519; the formats are the ones in the updates contract):
      keygen --key-id <id>        make a new key and store its private half in the login keychain
                                  (refuses if there is one); prints the public key, the keyId, and
                                  how to back the private half up without it being shown
      import --key-id <id>        store a backed-up private key piped in on standard input
                                  (pbpaste | tactile-release import --key-id k1); prints its public key
      public-key --key-id <id>    print the public key (base64) of the stored private key
      sign --key-id <id> <file>   print the signature (base64) of the file's bytes
      verify --public-key <base64> --signature <base64> <file>
                                  exit 0 when the signature is the file's under that key, else 1

    For release.sh:
      check-settings --key-id <id> --public-key <base64> --site <url> <app>
                                  exit 0 when the app's Info.plist, read as the app reads it,
                                  trusts that key under that keyId and asks that site, else 1
      find-key --public-key <base64> <app>
                                  exit 0 when a file in the app carries that public key, else 1
      manifest --version <v> --build <n> --minimum-system-version <v> --notes-file <file>
               --zip <file> --dmg <file> --signature <base64> --key-id <id> --public-key <base64>
               [--published-at <yyyy-mm-ddThh:mm:ssZ>]
                                  print update.json (the signature is checked first)

    The private key is kept in the login keychain (generic password, service "Tactile update
    signing key", account the keyId), read and written only through /usr/bin/security, and never
    printed or written to a file.

    Exit status: 0 done, 1 refused or failed, 2 a usage error.
    """

    private struct Spec {
        var options: Set<String>
        var optional: Set<String> = []
        var positionals: Int = 0
    }

    private static let specs: [String: Spec] = [
        "keygen": Spec(options: ["--key-id"]),
        "import": Spec(options: ["--key-id"]),
        "public-key": Spec(options: ["--key-id"]),
        "sign": Spec(options: ["--key-id"], positionals: 1),
        "verify": Spec(options: ["--public-key", "--signature"], positionals: 1),
        "find-key": Spec(options: ["--public-key"], positionals: 1),
        "check-settings": Spec(options: ["--key-id", "--public-key", "--site"], positionals: 1),
        "manifest": Spec(
            options: ["--version", "--build", "--minimum-system-version", "--notes-file", "--zip", "--dmg",
                      "--signature", "--key-id", "--public-key", "--published-at"],
            optional: ["--published-at"]),
    ]

    struct UsageError: Error { var message: String }
    struct Refusal: Error { var message: String }

    public static func run(_ arguments: [String], store: KeyStore, console: Console, now: Date = Date()) -> Int32 {
        guard let command = arguments.first else {
            console.err(usage)
            return 2
        }
        if ["-h", "--help", "help"].contains(command) {
            console.out(usage)
            return 0
        }
        do {
            guard let spec = specs[command] else { throw UsageError(message: "unknown command: \(command)") }
            let (options, positionals) = try parse(Array(arguments.dropFirst()), spec: spec)
            switch command {
            case "keygen": try keygen(keyID: try keyID(options), store: store, console: console)
            case "import": try importKey(keyID: try keyID(options), store: store, console: console)
            case "public-key": console.out(UpdateKey.encode(try storedKey(try keyID(options), store: store).publicKey))
            case "sign": try sign(keyID: try keyID(options), file: positionals[0], store: store, console: console)
            case "verify": try verify(options: options, file: positionals[0], console: console)
            case "find-key": try findKey(publicKey: options["--public-key"]!, path: positionals[0], console: console)
            case "check-settings": try checkSettings(options: options, app: positionals[0], console: console)
            default: try manifest(options: options, now: now, console: console)
            }
            return 0
        } catch let error as UsageError {
            console.err("tactile-release: \(error.message)")
            console.err("Run tactile-release --help for the commands.")
            return 2
        } catch let error as Refusal {
            console.err("tactile-release: \(error.message)")
            return 1
        } catch {
            console.err("tactile-release: \(error)")
            return 1
        }
    }

    // MARK: The arguments

    private static func parse(_ arguments: [String], spec: Spec) throws -> ([String: String], [String]) {
        var options: [String: String] = [:]
        var positionals: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                guard spec.options.contains(argument) else { throw UsageError(message: "unknown option: \(argument)") }
                guard options[argument] == nil else { throw UsageError(message: "\(argument) is given twice") }
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw UsageError(message: "\(argument) needs a value")
                }
                options[argument] = arguments[index + 1]
                index += 2
            } else {
                positionals.append(argument)
                index += 1
            }
        }
        for option in spec.options.subtracting(spec.optional).sorted() where options[option] == nil {
            throw UsageError(message: "\(option) is required")
        }
        guard positionals.count == spec.positionals else {
            throw UsageError(message: spec.positionals == 0 ? "unexpected argument: \(positionals[0])"
                : "expected \(spec.positionals) file, got \(positionals.count)")
        }
        return (options, positionals)
    }

    private static func keyID(_ options: [String: String]) throws -> String {
        let keyID = options["--key-id"]!
        guard UpdateKey.isValidKeyID(keyID) else {
            throw UsageError(message: "'\(keyID)' is not a keyId (letters, digits, '.', '_' and '-', at most 32; the first key is k1)")
        }
        return keyID
    }

    private static func item(_ keyID: String) -> String {
        "service \"\(UpdateKey.keychainService)\", account \"\(keyID)\""
    }

    // MARK: The key

    private static func keygen(keyID: String, store: KeyStore, console: Console) throws {
        if try store.contains(keyID: keyID) {
            throw Refusal(message: """
            there is already an update key \(keyID) in the keychain (\(item(keyID))); it was left as it is.
            A new key needs a new keyId (k2, ...), and Tactile must trust it before a release is signed with it.
            """)
        }
        let key = UpdateKey.newPrivateKey()
        try store.add(keyID: keyID, privateKey: UpdateKey.encode(key))
        try confirmStored(keyID: keyID, publicKey: UpdateKey.encode(key.publicKey), store: store)
        let publicKey = UpdateKey.encode(key.publicKey)
        console.out("""
        Made the update key \(keyID). Its private half is in the login keychain, as a generic password
        (\(item(keyID))), readable by /usr/bin/security without a prompt.
        It was not shown here, and is not written anywhere else.

        keyId:       \(keyID)
        Public key:  \(publicKey)

        Tactile must trust this public key, under \(keyID), before an update signed with it can install:
        it goes into the updater's list of trusted keys. release.sh checks that the app carries it.

        Back up the private half now, into your password manager. In your own terminal, run:

          security find-generic-password -s '\(UpdateKey.keychainService)' -a '\(keyID)' -w | pbcopy

        paste it into a new entry there (call it "Tactile update signing key \(keyID)"), then clear the
        clipboard (a clipboard history app may also have kept it: remove it there too):

          pbcopy < /dev/null

        Why it matters: every installed Tactile checks an update against the public keys built into it.
        If this private key is lost, no update can be signed with \(keyID) again, so copies that trust only
        \(keyID) can no longer update themselves: each would need the DMG installed by hand. With the backup,
        it can be put back on any Mac (Tools/RELEASING.md says how).
        """)
    }

    private static func importKey(keyID: String, store: KeyStore, console: Console) throws {
        guard !console.inputIsTerminal else {
            throw UsageError(message: """
            pipe the key in, so that it is never shown or typed: pbpaste | tactile-release import --key-id \(keyID)
            """)
        }
        let text = String(decoding: console.readInput(), as: UTF8.self)
        guard let key = try? UpdateKey.privateKey(base64: text) else {
            throw Refusal(message: "what was piped in is not an update key's private half (standard base64 of 32 bytes). Nothing was stored.")
        }
        if try store.contains(keyID: keyID) {
            throw Refusal(message: "there is already an update key \(keyID) in the keychain (\(item(keyID))); it was left as it is.")
        }
        try store.add(keyID: keyID, privateKey: UpdateKey.encode(key))
        let publicKey = UpdateKey.encode(key.publicKey)
        try confirmStored(keyID: keyID, publicKey: publicKey, store: store)
        console.out("""
        Stored the update key \(keyID) in the login keychain (generic password, \(item(keyID))).

        keyId:       \(keyID)
        Public key:  \(publicKey)

        Check that this is the public key Tactile trusts under \(keyID). Then clear the clipboard: pbcopy < /dev/null
        """)
    }

    /// Reads the item back: it must hold the key just made (`security -i` does not say whether its
    /// command worked).
    private static func confirmStored(keyID: String, publicKey: String, store: KeyStore) throws {
        let stored: String?
        do {
            stored = try store.privateKey(keyID: keyID)
        } catch {
            throw Refusal(message: "the key was written, but it could not be read back to confirm it: \(error)")
        }
        guard let stored else {
            throw Refusal(message: "the key could not be stored in the login keychain (it is not there after writing it). Is the keychain unlocked?")
        }
        guard let storedKey = try? UpdateKey.privateKey(base64: stored), UpdateKey.encode(storedKey.publicKey) == publicKey else {
            throw Refusal(message: """
            the keychain item \(keyID) does not hold the key just made (another run may have made one meanwhile). \
            Run tactile-release public-key --key-id \(keyID) to see what it holds.
            """)
        }
    }

    private static func storedKey(_ keyID: String, store: KeyStore) throws -> Curve25519.Signing.PrivateKey {
        guard let stored = try store.privateKey(keyID: keyID) else {
            throw Refusal(message: """
            there is no update key \(keyID) in the keychain (\(item(keyID))). Make one with keygen, \
            or put a backed-up one back with import.
            """)
        }
        guard let key = try? UpdateKey.privateKey(base64: stored) else {
            throw Refusal(message: "the keychain item for \(keyID) does not hold a valid update key.")
        }
        return key
    }

    // MARK: Signatures

    private static func readFile(_ path: String) throws -> Data {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw Refusal(message: "there is no file at \(path).")
        }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {
            throw Refusal(message: "could not read \(path).")
        }
    }

    private static func sign(keyID: String, file: String, store: KeyStore, console: Console) throws {
        let key = try storedKey(keyID, store: store)
        let data = try readFile(file)
        console.out(try UpdateKey.sign(data, with: key))
    }

    private static func verify(options: [String: String], file: String, console: Console) throws {
        let data = try readFile(file)
        let valid: Bool
        do {
            valid = try UpdateKey.isValid(signature: options["--signature"]!, of: data, publicKey: options["--public-key"]!)
        } catch {
            throw Refusal(message: "\(error)")
        }
        guard valid else { throw Refusal(message: "the signature does not verify over \(file) with that public key.") }
        console.out("The signature verifies over \(file).")
    }

    // MARK: For release.sh

    private static func findKey(publicKey: String, path: String, console: Console) throws {
        let matches = try KeySearch.find(publicKey: publicKey, in: URL(fileURLWithPath: path))
        guard !matches.isEmpty else { throw Refusal(message: "no file in \(path) carries that public key.") }
        for match in matches { console.out("\(match.path) (\(match.form))") }
    }

    private static func checkSettings(options: [String: String], app: String, console: Console) throws {
        let keyID = try keyID(options)
        let publicKey = options["--public-key"]!
        _ = try UpdateKey.decode(publicKey, length: UpdateKey.keyLength, what: "public key")
        guard let site = UpdateSettingsCheck.site(options["--site"]!) else {
            throw UsageError(message: "--site must be an https origin, not \(options["--site"]!)")
        }
        do {
            console.out(try UpdateSettingsCheck.check(app: URL(fileURLWithPath: app), keyID: keyID, publicKey: publicKey, site: site))
        } catch let error as UpdateSettingsCheck.Failure {
            throw Refusal(message: error.message)
        }
    }

    private static func manifest(options: [String: String], now: Date, console: Console) throws {
        guard let build = Int(options["--build"]!) else {
            throw UsageError(message: "--build must be a whole number, not \(options["--build"]!)")
        }
        var publishedAt = now
        if let text = options["--published-at"] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw UsageError(message: "--published-at must look like 2026-11-18T10:00:00Z, not \(text)")
            }
            publishedAt = date
        }
        let notesPath = options["--notes-file"]!
        guard let notes = try? String(contentsOf: URL(fileURLWithPath: notesPath), encoding: .utf8) else {
            throw Refusal(message: "could not read the notes in \(notesPath) as UTF-8 text.")
        }
        let input = Manifest.Input(
            version: options["--version"]!, build: build,
            minimumSystemVersion: options["--minimum-system-version"]!, publishedAt: publishedAt, notes: notes,
            zip: URL(fileURLWithPath: options["--zip"]!), dmg: URL(fileURLWithPath: options["--dmg"]!),
            signature: options["--signature"]!, keyID: try keyID(options), publicKey: options["--public-key"]!)
        console.out(try Manifest.json(input))
    }
}
