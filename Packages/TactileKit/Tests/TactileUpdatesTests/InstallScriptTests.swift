import Foundation
import XCTest

@testable import TactileUpdates

/// The helper script: its steps and what each does when it fails, as data; its text, every path
/// quoted; and the script itself, run in a temporary folder against stand-in bundles, with an opener
/// that opens nothing but a stand-in process. It never runs against a real app.
final class InstallScriptTests: XCTestCase {

    // MARK: - The plan

    func testTheStepsInOrderAndWhatEachDoesWhenItFails() {
        let plan = Self.plan(root: URL(fileURLWithPath: "/tmp/x"))!
        XCTAssertEqual(plan.steps, [.waitForQuit, .stageNewApp, .moveOldAside, .moveNewIntoPlace, .openNewApp,
                                    .waitForNewApp, .deleteOldApp, .cleanUp])
        XCTAssertEqual(plan.steps.map(\.ifItFails), [.giveUp, .reopenOld, .reopenOld, .putOldBack, .putOldBack,
                                                     .putOldBack, .carryOn, .carryOn])
    }

    func testTheHiddenNamesAreBesideTheApp() {
        let plan = Self.plan(root: URL(fileURLWithPath: "/Volumes/Work"), token: "a1B2")!
        XCTAssertEqual(plan.app.path, "/Volumes/Work/Applications/Tactile.app")
        XCTAssertEqual(plan.staged.path, "/Volumes/Work/Applications/.Tactile.app.new-a1B2")
        XCTAssertEqual(plan.aside.path, "/Volumes/Work/Applications/.Tactile.app.replaced-a1B2")
    }

    func testAPlanTheHelperMayNotActOnIsRefused() {
        let root = URL(fileURLWithPath: "/tmp/x")
        func plan(pid: Int32 = 10, app: String = "/tmp/x/Applications/Tactile.app",
                  newApp: String = "/tmp/x/Updates/Unpacked/Tactile.app", executable: String = "Tactile",
                  log: String = "/tmp/x/Updates/install.log", leftovers: [String] = ["/tmp/x/Updates/Unpacked"],
                  token: String = "abc") -> InstallPlan? {
            InstallPlan(processID: pid, app: URL(fileURLWithPath: app), newApp: URL(fileURLWithPath: newApp),
                        executable: executable, log: URL(fileURLWithPath: log),
                        leftovers: leftovers.map { URL(fileURLWithPath: $0) }, token: token,
                        fromVersion: "0.5.0", toVersion: "0.6.0")
        }
        XCTAssertNotNil(Self.plan(root: root))
        XCTAssertNil(plan(pid: 0))
        XCTAssertNil(plan(app: "/tmp/x/Applications/Tactile"), "not an app")
        XCTAssertNil(plan(app: "/tmp/x/Applications/../Tactile.app"))
        XCTAssertNil(plan(newApp: "/tmp/x/Updates/Unpacked/./Tactile.app"))
        XCTAssertNil(plan(newApp: "/tmp/x/Updates/Unpacked"), "not an app")
        XCTAssertNil(plan(log: "/tmp/x/../install.log"))
        XCTAssertNil(plan(leftovers: ["/tmp/x/Updates/.."]))
        XCTAssertNil(plan(executable: ""))
        XCTAssertNil(plan(executable: "MacOS/Tactile"))
        XCTAssertNil(plan(executable: ".."))
        XCTAssertNil(plan(token: ""))
        XCTAssertNil(plan(token: "a-b"))
        XCTAssertNil(plan(token: "a/b"))
        XCTAssertNil(plan(token: String(repeating: "a", count: 33)))
    }

    // MARK: - The text

    func testAQuotedPathIsOneWordWhateverItHolds() {
        XCTAssertEqual(InstallScript.quoted("/Applications/Tactile.app"), "'/Applications/Tactile.app'")
        XCTAssertEqual(InstallScript.quoted("it's"), #"'it'\''s'"#)
        XCTAssertEqual(InstallScript.quoted(""), "''")
    }

    /// The settings, run by `/bin/sh` and printed back: every value arrives exactly as it was, and
    /// nothing in a path runs.
    func testTheSettingsSurviveTheShellWhateverThePathsHold() throws {
        let root = try makeTemporaryFolder()
        let pwned = root.appendingPathComponent("pwned")
        let nasty = root.appendingPathComponent(
            #"Apps 'n "quotes" $HOME `touch \#(pwned.path)` $(touch \#(pwned.path)); \ * ?"#, isDirectory: true)
        let plan = try XCTUnwrap(Self.plan(root: nasty))
        let script = InstallScript.settings(for: plan) + #"printf '%s\0' "$PID" "$APP" "$NEW" "$STAGED" "$ASIDE" "$EXECUTABLE" "$OPEN" "$LOG" "$LEFTOVER_1" "$LEFTOVER_2""#
        let output = try Self.runShell(script)
        let values = output.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
        XCTAssertEqual(values, [
            "\(plan.processID)", plan.app.path, plan.newApp.path, plan.staged.path, plan.aside.path, "Tactile",
            "/usr/bin/open", plan.log.path, plan.leftovers[0].path, plan.leftovers[1].path,
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: pwned.path), "nothing in a path was run")
    }

    func testEveryPathIsInTheSettingsAndNowhereElse() throws {
        let root = URL(fileURLWithPath: "/private/tmp/Tactile Update Test", isDirectory: true)
        let plan = try XCTUnwrap(Self.plan(root: root))
        let text = InstallScript.text(for: plan)
        let settings = Set(InstallScript.settings(for: plan).split(separator: "\n").map(String.init))
        for line in text.split(separator: "\n").map(String.init) where line.contains(root.path) {
            XCTAssertTrue(settings.contains(line), "a path outside the settings: \(line)")
        }
        for name in ["APP", "NEW", "STAGED", "ASIDE", "LOG", "OPEN", "LEFTOVER_1", "LEFTOVER_2"] {
            XCTAssertTrue(settings.contains { $0.hasPrefix("\(name)='") }, name)
        }
    }

    func testTheTextNamesEveryToolByItsPathAndTakesTheStepsInOrder() throws {
        let plan = try XCTUnwrap(Self.plan(root: URL(fileURLWithPath: "/tmp/x")))
        let text = InstallScript.text(for: plan)
        XCTAssertTrue(text.hasPrefix("#!/bin/sh\n# Tactile's update helper, written by Tactile 0.5.0 to install 0.6.0.\n"))
        for tool in ["/bin/mv -- ", "/bin/rm -rf -- ", "/bin/ps -axo comm=", "/usr/bin/grep -Fxq", "/bin/sleep ",
                     "/bin/date "] {
            XCTAssertTrue(text.contains(tool), tool)
        }
        XCTAssertTrue(text.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin\nexport PATH"))
        XCTAssertTrue(text.hasSuffix("say \"Done.\"\nexit 0\n"))
        var position = text.startIndex
        for step in InstallStep.allCases {
            let range = try XCTUnwrap(text.range(of: "# Step \(step.rawValue): ", range: position..<text.endIndex),
                                      "step \(step.rawValue) in order")
            position = range.upperBound
        }
    }

    func testEachStepRecoversAsItsPlanSays() {
        for step in InstallStep.allCases {
            let block = InstallScript.block(for: step)
            switch step.ifItFails {
            case .giveUp: XCTAssertTrue(block.contains("|| give_up \""), "\(step)")
            case .reopenOld: XCTAssertTrue(block.contains("|| reopen_old \""), "\(step)")
            case .putOldBack: XCTAssertTrue(block.contains("|| put_old_back \""), "\(step)")
            case .carryOn: XCTAssertTrue(block.contains("carrying on.\""), "\(step)")
            }
        }
        XCTAssertTrue(InstallScript.block(for: .stageNewApp).contains(#"move "$NEW" "$STAGED""#))
        XCTAssertTrue(InstallScript.block(for: .moveOldAside).contains(#"move "$APP" "$ASIDE""#))
        XCTAssertTrue(InstallScript.block(for: .moveNewIntoPlace).contains(#"move "$STAGED" "$APP""#))
        XCTAssertTrue(InstallScript.block(for: .deleteOldApp).contains(#"/bin/rm -rf -- "$ASIDE""#))
        XCTAssertEqual(InstallScript.block(for: .waitForNewApp).components(separatedBy: "new_app_runs").count - 1, 2,
                       "it runs, and still runs a moment later")
    }

    // MARK: - The script, run in a temporary folder

    /// Tactile quits; the new app takes the old one's place and runs; the old copy and the leftovers
    /// are deleted.
    func testItReplacesTheAppOnceTactileHasQuit() throws {
        let sandbox = try Sandbox(test: self, newAppRunsFor: 6)
        defer { sandbox.stop() }
        let status = try sandbox.run(quitAfter: 0.3)
        XCTAssertEqual(status, 0, sandbox.log)
        XCTAssertEqual(marker(of: sandbox.plan.app), "new")
        XCTAssertEqual(sandbox.opened, [sandbox.plan.app.path])
        sandbox.assertNothingElseLeft()
        XCTAssertTrue(sandbox.log.contains("Waiting for Tactile (pid \(sandbox.plan.processID)) to quit."))
        XCTAssertTrue(sandbox.log.contains("The new app runs."))
        XCTAssertTrue(sandbox.log.hasSuffix("Done.\n"), sandbox.log)
    }

    /// The new app never starts: the old one goes back and is opened again.
    func testANewAppThatDoesntStartPutsTheOldOneBack() throws {
        let sandbox = try Sandbox(test: self, newAppRunsFor: nil)
        defer { sandbox.stop() }
        let status = try sandbox.run(quitAfter: 0.2)
        XCTAssertEqual(status, 1, sandbox.log)
        XCTAssertEqual(marker(of: sandbox.plan.app), "old")
        XCTAssertEqual(sandbox.opened, [sandbox.plan.app.path, sandbox.plan.app.path], "the new one, then the old one")
        sandbox.assertNothingElseLeft()
        XCTAssertTrue(sandbox.log.contains("Putting the old app back."), sandbox.log)
    }

    /// The new app starts and quits at once: the old one goes back.
    func testANewAppThatQuitsAsItStartsPutsTheOldOneBack() throws {
        let sandbox = try Sandbox(test: self, newAppRunsFor: 0.4)
        defer { sandbox.stop() }
        let status = try sandbox.run(quitAfter: 0.2)
        XCTAssertEqual(status, 1, sandbox.log)
        XCTAssertEqual(marker(of: sandbox.plan.app), "old")
        XCTAssertTrue(sandbox.log.contains("the new app quit as it started"), sandbox.log)
        sandbox.assertNothingElseLeft()
    }

    /// The new app can't be moved beside the old one: the old one stays and is opened again.
    func testANewAppThatCantBeMovedLeavesTheOldOne() throws {
        let sandbox = try Sandbox(test: self, newAppRunsFor: 6)
        defer { sandbox.stop() }
        try FileManager.default.removeItem(at: sandbox.plan.newApp)
        let status = try sandbox.run(quitAfter: 0.2)
        XCTAssertEqual(status, 1, sandbox.log)
        XCTAssertEqual(marker(of: sandbox.plan.app), "old")
        XCTAssertEqual(sandbox.opened, [sandbox.plan.app.path])
        sandbox.assertNothingElseLeft()
    }

    /// Tactile never quits: the helper gives up, changes nothing and opens nothing.
    func testTheHelperGivesUpWhenTactileDoesntQuit() throws {
        let sandbox = try Sandbox(test: self, newAppRunsFor: 6)
        defer { sandbox.stop() }
        let status = try sandbox.run(quitAfter: nil)
        XCTAssertEqual(status, 1, sandbox.log)
        XCTAssertEqual(marker(of: sandbox.plan.app), "old")
        XCTAssertEqual(sandbox.opened, [])
        sandbox.assertNothingElseLeft()
        XCTAssertTrue(sandbox.log.contains("Tactile didn't quit within 1 seconds. Nothing was changed."), sandbox.log)
    }

    // MARK: -

    static func plan(root: URL, token: String = "test1") -> InstallPlan? {
        let updates = root.appendingPathComponent("Updates", isDirectory: true)
        return InstallPlan(
            processID: 4242, app: root.appendingPathComponent("Applications/Tactile.app", isDirectory: true),
            newApp: updates.appendingPathComponent("Unpacked/Tactile.app", isDirectory: true), executable: "Tactile",
            log: updates.appendingPathComponent("install.log"),
            leftovers: [updates.appendingPathComponent("Tactile-0.6.0.zip"), updates.appendingPathComponent("Unpacked")],
            token: token, fromVersion: "0.5.0", toVersion: "0.6.0")
    }

    /// Runs `script` with `/bin/sh -c` and returns what it printed.
    static func runShell(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// A temporary folder holding an old Tactile.app and a new one in an update folder, a stand-in for
/// Tactile's process (`sleep`), and an opener that records what it is asked to open and, when told,
/// starts a stand-in for the new app: `sleep` started with the app's executable path as its name,
/// which is how the helper sees an app run. Everything the script touches is inside the folder.
private final class Sandbox {
    let root: URL
    let plan: InstallPlan
    let opener: URL
    private let tactile = Process()

    init(test: XCTestCase, newAppRunsFor seconds: Double?) throws {
        root = try test.makeTemporaryFolder()
        // A folder name with a space, quotes and a dollar sign, as a person's folder might have.
        let place = root.appendingPathComponent(#"Apps 'n "Things" $HOME"#, isDirectory: true)
        let updates = root.appendingPathComponent("Updates", isDirectory: true)
        try test.makeBundle(at: place.appendingPathComponent("Tactile.app"), version: "0.5.0", build: "300", marker: "old")
        try test.makeBundle(at: updates.appendingPathComponent("Unpacked/Tactile.app"), version: "0.6.0", build: "412",
                            marker: "new")
        try Data("zip".utf8).write(to: updates.appendingPathComponent("Tactile-0.6.0.zip"))

        opener = root.appendingPathComponent("open")
        let opened = InstallScript.quoted(root.appendingPathComponent("opened").path)
        let pids = InstallScript.quoted(root.appendingPathComponent("pids").path)
        var openerText = "#!/bin/bash\nprintf '%s\\n' \"$1\" >> \(opened)\n"
        if let seconds {
            openerText += """
            /bin/bash -c 'exec -a "$0/Contents/MacOS/Tactile" /bin/sleep "$1"' "$1" \(seconds) </dev/null >/dev/null 2>&1 &
            echo $! >> \(pids)

            """
        }
        openerText += "exit 0\n"
        try Data(openerText.utf8).write(to: opener)
        chmod(opener.path, 0o755)

        tactile.executableURL = URL(fileURLWithPath: "/bin/sleep")
        tactile.arguments = ["30"]
        try tactile.run()

        var plan = try XCTUnwrap(InstallPlan(
            processID: tactile.processIdentifier, app: place.appendingPathComponent("Tactile.app", isDirectory: true),
            newApp: updates.appendingPathComponent("Unpacked/Tactile.app", isDirectory: true), executable: "Tactile",
            log: updates.appendingPathComponent("install.log"),
            leftovers: [updates.appendingPathComponent("Tactile-0.6.0.zip"), updates.appendingPathComponent("Unpacked")],
            token: "test1", fromVersion: "0.5.0", toVersion: "0.6.0"))
        plan.opener = opener.path
        plan.quitWait = 1
        plan.launchWait = 1
        plan.steadyWait = 1
        self.plan = plan
        for url in [plan.app, plan.newApp, plan.staged, plan.aside, plan.log] + plan.leftovers {
            XCTAssertTrue(url.path.hasPrefix(root.path + "/"), "the script touches only the sandbox: \(url.path)")
        }
    }

    /// Writes and runs the script, ends the stand-in Tactile after `quitAfter` seconds (never, when
    /// nil), and returns the script's exit status.
    func run(quitAfter: Double?) throws -> Int32 {
        let script = root.appendingPathComponent("install.sh")
        try Data(InstallScript.text(for: plan).utf8).write(to: script)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [script.path]
        helper.standardInput = FileHandle.nullDevice
        try helper.run()
        if let quitAfter {
            Thread.sleep(forTimeInterval: quitAfter)
            tactile.terminate()
        }
        helper.waitUntilExit()
        return helper.terminationStatus
    }

    var opened: [String] {
        let text = (try? String(contentsOf: root.appendingPathComponent("opened"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    var log: String {
        (try? String(contentsOf: plan.log, encoding: .utf8)) ?? ""
    }

    func assertNothingElseLeft(file: StaticString = #filePath, line: UInt = #line) {
        let files = FileManager.default
        XCTAssertTrue(files.fileExists(atPath: plan.app.path), "the app is in its place", file: file, line: line)
        for url in [plan.staged, plan.aside] + plan.leftovers {
            XCTAssertFalse(files.fileExists(atPath: url.path), url.lastPathComponent, file: file, line: line)
        }
        let folder = (try? files.contentsOfDirectory(atPath: plan.app.deletingLastPathComponent().path)) ?? []
        XCTAssertEqual(folder, ["Tactile.app"], "nothing hidden left beside it", file: file, line: line)
    }

    /// Ends the stand-ins still running.
    func stop() {
        if tactile.isRunning { tactile.terminate() }
        let text = (try? String(contentsOf: root.appendingPathComponent("pids"), encoding: .utf8)) ?? ""
        for pid in text.split(separator: "\n").compactMap({ Int32($0) }) {
            kill(pid, SIGTERM)
        }
    }
}
