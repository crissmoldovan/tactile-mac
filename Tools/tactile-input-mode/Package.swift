// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "tactile-input-mode",
    platforms: [.macOS(.v12)],
    targets: [
        // Pure rules: the descriptor parser, what may be written, and how reports are counted. Tested.
        .target(name: "InputModeCore", path: "Sources/InputModeCore"),
        // The command-line tool: IOKit discovery, opens, writes and listening.
        .executableTarget(name: "tactile-input-mode", dependencies: ["InputModeCore"], path: "Sources/tactile-input-mode"),
        .testTarget(name: "InputModeCoreTests", dependencies: ["InputModeCore"], path: "Tests/InputModeCoreTests"),
    ]
)
