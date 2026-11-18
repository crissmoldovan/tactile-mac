import Foundation

/// Whether a built app carries an update key's public half. The updater compiles its trusted keys into
/// the app as base64 strings, and a Swift string literal of that length is stored whole in the binary;
/// the key's raw 32 bytes are looked for as well, in case they are ever compiled in that form. Every
/// regular file in the bundle is searched (binaries, frameworks, resources, Info.plist); symbolic links
/// are not followed, so nothing outside the bundle can answer for it.
public enum KeySearch {
    public struct Match: Equatable {
        /// The file's path inside the searched folder.
        public var path: String
        /// "base64" or "raw bytes".
        public var form: String

        public init(path: String, form: String) {
            self.path = path
            self.form = form
        }
    }

    public static func find(publicKey: String, in root: URL) throws -> [Match] {
        let raw = try UpdateKey.decode(publicKey, length: UpdateKey.keyLength, what: "public key")
        let text = Data(publicKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw KeySearchError("There is nothing at \(root.path).")
        }
        let files: [(URL, String)]
        if isDirectory.boolValue {
            files = try regularFiles(under: root)
        } else {
            files = [(root, root.lastPathComponent)]
        }
        var matches: [Match] = []
        for (url, relative) in files {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                throw KeySearchError("Could not read \(url.path).")
            }
            if data.range(of: text) != nil { matches.append(Match(path: relative, form: "base64")) }
            if data.range(of: raw) != nil { matches.append(Match(path: relative, form: "raw bytes")) }
        }
        return matches
    }

    static func regularFiles(under root: URL) throws -> [(URL, String)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else {
            throw KeySearchError("Could not list \(root.path).")
        }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        var files: [(URL, String)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            // The enumerator does not descend into symbolic links to folders; links to files are skipped here.
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
            files.append((url, relative))
        }
        return files.sorted { $0.1 < $1.1 }
    }
}

public struct KeySearchError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
