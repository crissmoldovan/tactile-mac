// Whether Tactile can replace itself where it is.

import Darwin
import Foundation

/// Where the running app is, as far as installing goes: Tactile replaces itself only when the folder
/// it is in can be written by this account, and it isn't running translocated (macOS's App
/// Translocation runs an app opened from a quarantined download from a randomised read-only place;
/// replacing that copy would change nothing the person can see).
public struct InstallLocation: Sendable {
    public var isTranslocated: @Sendable (URL) -> Bool
    public var isWritable: @Sendable (URL) -> Bool

    public init(isTranslocated: @escaping @Sendable (URL) -> Bool, isWritable: @escaping @Sendable (URL) -> Bool) {
        self.isTranslocated = isTranslocated
        self.isWritable = isWritable
    }

    /// The live checks: the path, then the Security framework, for translocation; `access(2)` for
    /// writing the folder.
    public static let live = InstallLocation(
        isTranslocated: { pathLooksTranslocated($0) || securityReportsTranslocated($0) },
        isWritable: { access($0.path, W_OK) == 0 })

    /// Why Tactile at `app` can't replace itself, or nil when it can.
    public func refusal(for app: URL) -> UpdateFailure? {
        if isTranslocated(app) { return .translocated }
        let folder = app.deletingLastPathComponent()
        if !isWritable(folder) { return .folderNotWritable(folder: folder.path) }
        return nil
    }

    /// A translocated app runs from somewhere under `/AppTranslocation/`.
    public static func pathLooksTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    /// `SecTranslocateIsTranslocatedURL`, which the Security framework exports without declaring it
    /// in its headers, looked up at run time. False when it can't be found or doesn't answer.
    public static func securityReportsTranslocated(_ url: URL) -> Bool {
        typealias IsTranslocated = @convention(c) (
            CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> UInt8
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_NOLOAD)
                ?? dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateIsTranslocatedURL")
        else { return false }
        let function = unsafeBitCast(symbol, to: IsTranslocated.self)
        var translocated = false
        guard function(url as CFURL, &translocated, nil) != 0 else { return false }
        return translocated
    }
}
