// The live halves of check 4: `ditto` to unzip, and the Security framework for the code signature.

import Foundation
import Security

/// Unzips with `/usr/bin/ditto -x -k`, as the release zipped with `ditto -c -k --keepParent`.
public struct DittoUnpacker: ArchiveUnpacking {
    public init() {}

    public func unpack(_ archive: URL, into folder: URL) async -> Bool {
        let status = await Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        if status != 0 {
            UpdatesLog.log.error("ditto ended with status \(status, privacy: .public)")
        }
        return status == 0
    }

    /// Runs a tool, without input or output, and waits for its exit status; -1 when it couldn't start.
    static func run(_ tool: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}

/// Checks an app's code signature with `SecStaticCodeCheckValidity`: every architecture, nested
/// code included, strictly, against a code requirement.
public struct SecurityCodeSignatureCheck: CodeSignatureChecking {
    /// The updates contract's requirement: Apple's anchor, Tactile's bundle identifier, a Developer
    /// ID certificate (its intermediate's and leaf's marker fields), and the official build's team.
    public static let developerIDRequirement =
        #"anchor apple generic and identifier "com.crissmoldovan.tactile" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "75K3LTUM8A""#

    /// The flags the contract names.
    public static let flags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    public var requirement: String

    public init(requirement: String = developerIDRequirement) {
        self.requirement = requirement
    }

    public func isValid(_ app: URL) -> Bool {
        let status = check(app)
        if status != errSecSuccess {
            UpdatesLog.log.error("code signature check of \(app.path, privacy: .public): status \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// The status of the check: `errSecSuccess` when the app is valid and satisfies the requirement.
    public func check(_ app: URL) -> OSStatus {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard status == errSecSuccess, let code else { return status }
        var compiled: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
        guard status == errSecSuccess, let compiled else { return status }
        return SecStaticCodeCheckValidity(code, Self.flags, compiled)
    }
}
