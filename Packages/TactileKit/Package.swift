// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TactileKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TactileGestures", targets: ["TactileGestures"]),
        .library(name: "TactileOutput", targets: ["TactileOutput"]),
        .library(name: "TactileReading", targets: ["TactileReading"]),
        .library(name: "TactileScreens", targets: ["TactileScreens"]),
        .library(name: "TactileDevices", targets: ["TactileDevices"]),
        .library(name: "TactileApp", targets: ["TactileApp"]),
        .library(name: "TactileUpdates", targets: ["TactileUpdates"]),
        .library(name: "TactileSupport", targets: ["TactileSupport"]),
    ],
    targets: [
        .target(name: "TactileGestures"),
        .target(name: "TactileOutput", dependencies: ["TactileGestures"]),
        .target(name: "TactileReading"),
        .target(name: "TactileScreens", dependencies: ["TactileGestures"]),
        .target(name: "TactileDevices", dependencies: ["TactileReading", "TactileScreens"]),
        // Tactile's updater: asking tactilemac.com, checking an update, replacing the app. No interface.
        .target(name: "TactileUpdates"),
        // The touchscreen check's report: its files, the zip, and sending it to tactilemac.com. No interface.
        .target(name: "TactileSupport", dependencies: ["TactileDevices", "TactileReading", "TactileUpdates"]),
        .target(
            name: "TactileApp",
            dependencies: [
                "TactileGestures", "TactileReading", "TactileScreens", "TactileOutput", "TactileDevices",
                "TactileUpdates", "TactileSupport",
            ]
        ),
        .executableTarget(name: "tactile-devices-check", dependencies: ["TactileDevices"]),
        // Loads the panel survey recordings for tests. Only test targets depend on it.
        .target(name: "TactileTestSupport", path: "Tests/TactileTestSupport"),
        .testTarget(name: "TactileGesturesTests", dependencies: ["TactileGestures"]),
        .testTarget(name: "TactileOutputTests", dependencies: ["TactileOutput"]),
        .testTarget(name: "TactileReadingTests", dependencies: ["TactileReading", "TactileTestSupport"]),
        .testTarget(name: "TactileScreensTests", dependencies: ["TactileScreens", "TactileTestSupport"]),
        .testTarget(
            name: "TactileDevicesTests",
            dependencies: ["TactileDevices", "TactileReading", "TactileScreens", "TactileTestSupport"]
        ),
        .testTarget(
            name: "TactileAppTests",
            dependencies: [
                "TactileApp", "TactileGestures", "TactileReading", "TactileScreens", "TactileOutput",
                "TactileDevices", "TactileUpdates", "TactileSupport", "TactileTestSupport",
            ]
        ),
        .testTarget(name: "TactileUpdatesTests", dependencies: ["TactileUpdates"]),
        .testTarget(
            name: "TactileSupportTests",
            dependencies: ["TactileSupport", "TactileDevices", "TactileReading", "TactileUpdates", "TactileTestSupport"]
        ),
        // The survey's takes, replayed through reader, mapping, contact filter and engine together.
        .testTarget(
            name: "TactileReplayTests",
            dependencies: ["TactileReading", "TactileScreens", "TactileGestures", "TactileTestSupport"]),
    ]
)
