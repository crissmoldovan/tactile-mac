// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "tactile-probe",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "tactile-probe", path: "Sources/tactile-probe"),
        // The parts that need no hardware and no window: the command line, which takes run, which
        // display shows the instructions, the state file, the survey file's schema, the layout of
        // the instruction windows. `SurveyFixtures.swift` here is a link to TactileKit's own loader,
        // so a survey file this tool writes is checked against the very code that reads it.
        .testTarget(name: "tactile-probeTests", dependencies: ["tactile-probe"], path: "Tests/tactile-probeTests"),
    ]
)
