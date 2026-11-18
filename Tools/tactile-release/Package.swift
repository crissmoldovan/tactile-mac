// swift-tools-version:5.9
import PackageDescription

// The update key's tool: makes the key, signs releases with it, checks signatures, writes update.json.
// The formats are the ones the updates contract pins (Ed25519 through CryptoKit, standard base64).
// It reads a built app's update settings with the app's own code, TactileKit's TactileUpdates.
let package = Package(
    name: "tactile-release",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/TactileKit"),
    ],
    targets: [
        // Everything that can be tested: the key formats, signing and checking, the command line, the
        // manifest, the search for a public key in an app, the check of an app's update settings. The
        // Keychain sits behind `KeyStore`, so the tests use a fake and never touch a real Keychain item.
        .target(
            name: "ReleaseCore",
            dependencies: [.product(name: "TactileUpdates", package: "TactileKit")],
            path: "Sources/ReleaseCore"),
        .executableTarget(name: "tactile-release", dependencies: ["ReleaseCore"], path: "Sources/tactile-release"),
        .testTarget(name: "ReleaseCoreTests", dependencies: ["ReleaseCore"], path: "Tests/ReleaseCoreTests"),
    ]
)
