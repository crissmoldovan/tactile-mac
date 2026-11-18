// The helper that replaces Tactile once it has quit: planned as data, written as a shell script by a
// pure function, and started detached by `DetachedShellLauncher`.

import Foundation

/// A step of the helper, in the order it takes them.
public enum InstallStep: Int, CaseIterable, Equatable, Sendable {
    /// Wait for Tactile's process to end. Tactile quits through its normal path once the helper has
    /// started, letting the touchscreens go as on every quit.
    case waitForQuit = 1
    /// Move the new app from the update folder next to the old one, under a hidden name.
    case stageNewApp
    /// Move the old app aside, next to it, under a hidden name.
    case moveOldAside
    /// Move the new app into the old one's place.
    case moveNewIntoPlace
    /// Open the new app with `/usr/bin/open`.
    case openNewApp
    /// Wait until the new app runs, and still runs a moment later.
    case waitForNewApp
    /// Delete the old copy: only now that the new one runs.
    case deleteOldApp
    /// Remove the download and the unpacked folder.
    case cleanUp

    /// What the helper does when this step fails.
    public var ifItFails: InstallRecovery {
        switch self {
        case .waitForQuit: return .giveUp
        case .stageNewApp, .moveOldAside: return .reopenOld
        case .moveNewIntoPlace, .openNewApp, .waitForNewApp: return .putOldBack
        case .deleteOldApp, .cleanUp: return .carryOn
        }
    }
}

/// What the helper does when a step fails.
public enum InstallRecovery: Equatable, Sendable {
    /// Tactile may still be running and nothing has changed: change nothing, open nothing.
    case giveUp
    /// The old app is still in its place: remove the new one's staged copy, and open the old app.
    case reopenOld
    /// The old app is aside: move the new one out of its place, put the old one back, and open it.
    case putOldBack
    /// Only tidying is left: say so in the log, and go on.
    case carryOn
}

/// Everything the helper needs, decided by Tactile before it quits.
public struct InstallPlan: Equatable, Sendable {
    /// Tactile's process, to wait for.
    public var processID: Int32
    /// The running app, which the new one replaces: "/Applications/Tactile.app".
    public var app: URL
    /// The new app, unpacked and checked, in the update folder.
    public var newApp: URL
    /// Where the new app waits beside the old one: ".Tactile.app.new-<token>" in the same folder.
    public var staged: URL
    /// Where the old app goes until the new one runs: ".Tactile.app.replaced-<token>" beside it.
    public var aside: URL
    /// The new app's `CFBundleExecutable`, to know it runs.
    public var executable: String
    /// The helper's log.
    public var log: URL
    /// Removed at the end, whatever happened: the download and the unpacked folder.
    public var leftovers: [URL]
    /// The version replaced and the version installed, for the script's first lines.
    public var fromVersion: String
    public var toVersion: String

    /// How the apps are opened. Tests give a stand-in that opens nothing.
    public var opener = "/usr/bin/open"
    /// Seconds to wait for Tactile to quit before giving up.
    public var quitWait = 60
    /// Seconds to wait for the new app to start.
    public var launchWait = 30
    /// Seconds the new app must keep running once started.
    public var steadyWait = 3

    /// The plan, or nil when something in it isn't what the helper may act on: every path absolute
    /// and plain (no "." or ".." in it), the apps' names ending in ".app", the app not at the root,
    /// the executable a plain file name, the token letters and digits.
    public init?(processID: Int32, app: URL, newApp: URL, executable: String, log: URL, leftovers: [URL],
                 token: String, fromVersion: String, toVersion: String) {
        guard processID > 0,
              Self.isPlainAbsolute(app), app.pathExtension == "app", app.deletingLastPathComponent().path != app.path,
              Self.isPlainAbsolute(newApp), newApp.pathExtension == "app",
              Self.isPlainAbsolute(log), leftovers.allSatisfy(Self.isPlainAbsolute),
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != "..",
              (1...32).contains(token.count), token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        let folder = app.deletingLastPathComponent()
        self.processID = processID
        self.app = app
        self.newApp = newApp
        self.staged = folder.appendingPathComponent(".\(app.lastPathComponent).new-\(token)", isDirectory: true)
        self.aside = folder.appendingPathComponent(".\(app.lastPathComponent).replaced-\(token)", isDirectory: true)
        self.executable = executable
        self.log = log
        self.leftovers = leftovers
        self.fromVersion = fromVersion
        self.toVersion = toVersion
    }

    /// The steps, in order.
    public var steps: [InstallStep] { InstallStep.allCases }

    private static func isPlainAbsolute(_ url: URL) -> Bool {
        let path = url.path
        guard url.isFileURL, path.hasPrefix("/"), !path.contains("\0") else { return false }
        return !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }
}

/// The helper as a POSIX shell script, from the plan: pure, so its text and its steps are tested.
///
/// Every path is set once, single-quoted, in the settings at the top, and used only as a
/// double-quoted variable after that. Every tool is named by its full path. Nothing is ever moved
/// onto something that exists (`mv` would move it inside a folder there), and nothing is deleted
/// but the helper's own staged and set-aside copies and the update folder's leftovers.
public enum InstallScript {
    /// `text` in single quotes, safe in any POSIX shell: a single quote inside becomes `'\''`.
    public static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The settings: one assignment a line, every path quoted.
    public static func settings(for plan: InstallPlan) -> String {
        var lines = [
            "PID=\(plan.processID)",
            "APP=\(quoted(plan.app.path))",
            "NEW=\(quoted(plan.newApp.path))",
            "STAGED=\(quoted(plan.staged.path))",
            "ASIDE=\(quoted(plan.aside.path))",
            "EXECUTABLE=\(quoted(plan.executable))",
            "OPEN=\(quoted(plan.opener))",
            "LOG=\(quoted(plan.log.path))",
        ]
        for (index, leftover) in plan.leftovers.enumerated() {
            lines.append("LEFTOVER_\(index + 1)=\(quoted(leftover.path))")
        }
        lines += [
            "QUIT_WAIT=\(max(plan.quitWait, 1))",
            "LAUNCH_WAIT=\(max(plan.launchWait, 1))",
            "STEADY_WAIT=\(max(plan.steadyWait, 0))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The whole script.
    public static func text(for plan: InstallPlan) -> String {
        var script = header(for: plan)
        script += "\n" + settings(for: plan)
        script += "\n" + functions(for: plan)
        for step in plan.steps {
            script += "\n" + block(for: step)
        }
        script += "\nsay \"Done.\"\nexit 0\n"
        return script
    }

    private static func header(for plan: InstallPlan) -> String {
        """
        #!/bin/sh
        # Tactile's update helper, written by Tactile \(oneLine(plan.fromVersion)) to install \(oneLine(plan.toVersion)).
        #
        # Once Tactile has quit: moves the new app next to the old one, moves the old one aside, moves
        # the new one into its place, opens it, and deletes the old copy only once the new one runs.
        # If a step fails, the old app goes back where it was and is opened again.

        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH

        """
    }

    private static func functions(for plan: InstallPlan) -> String {
        let leftovers = plan.leftovers.indices.map { "\"$LEFTOVER_\($0 + 1)\"" }.joined(separator: " ")
        let cleanUp = leftovers.isEmpty ? "  :" : "  /bin/rm -rf -- \(leftovers)"
        return """
        exec </dev/null
        if true >>"$LOG" 2>/dev/null; then exec >>"$LOG" 2>&1; else exec >/dev/null 2>&1; fi

        say() {
          printf '%s %s\\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*"
        }

        exists() {
          [ -e "$1" ] || [ -L "$1" ]
        }

        # Moves $1 to $2 only when nothing is at $2: mv would move $1 into a folder there.
        move() {
          if exists "$2"; then
            say "Not moving $1: something is already at $2."
            return 1
          fi
          /bin/mv -- "$1" "$2"
        }

        # Whether a process runs the app's executable, by the path it was started with.
        new_app_runs() {
          REAL=$(cd -P -- "$APP" 2>/dev/null && pwd -P) || REAL=$APP
          /bin/ps -axo comm= | /usr/bin/grep -Fxq -e "$APP/Contents/MacOS/$EXECUTABLE" -e "$REAL/Contents/MacOS/$EXECUTABLE"
        }

        open_app() {
          "$OPEN" "$APP"
        }

        clean_up() {
        \(cleanUp)
        }

        give_up() {
          say "Stopped: $1. Nothing was changed."
          clean_up
          exit 1
        }

        reopen_old() {
          say "Stopped: $1. The old app stays where it is."
          if exists "$STAGED"; then /bin/rm -rf -- "$STAGED"; fi
          open_app || say "Couldn't open the old app."
          clean_up
          exit 1
        }

        put_old_back() {
          say "Stopped: $1. Putting the old app back."
          if exists "$APP" && ! move "$APP" "$STAGED"; then
            say "Couldn't move the new app out of the way; the old app is at $ASIDE."
            clean_up
            exit 1
          fi
          if move "$ASIDE" "$APP"; then
            open_app || say "Couldn't open the old app."
          else
            say "Couldn't put the old app back; it is at $ASIDE."
          fi
          if exists "$STAGED"; then /bin/rm -rf -- "$STAGED"; fi
          clean_up
          exit 1
        }

        """
    }

    /// The lines of one step, headed "# Step <n>: …", ending in what its recovery says.
    static func block(for step: InstallStep) -> String {
        let heading = "# Step \(step.rawValue): "
        switch step {
        case .waitForQuit:
            return heading + """
            wait for Tactile to quit.
            say "Waiting for Tactile (pid $PID) to quit."
            waited=0
            while kill -0 "$PID" 2>/dev/null; do
              [ "$waited" -lt $((QUIT_WAIT * 5)) ] || \(recover(step, "Tactile didn't quit within $QUIT_WAIT seconds"))
              /bin/sleep 0.2
              waited=$((waited + 1))
            done

            """
        case .stageNewApp:
            return heading + """
            move the new app next to the old one.
            say "Moving the new app next to the old one."
            move "$NEW" "$STAGED" || \(recover(step, "couldn't move the new app next to the old one"))

            """
        case .moveOldAside:
            return heading + """
            move the old app aside.
            say "Moving the old app aside."
            move "$APP" "$ASIDE" || \(recover(step, "couldn't move the old app aside"))

            """
        case .moveNewIntoPlace:
            return heading + """
            move the new app into the old one's place.
            say "Moving the new app into place."
            move "$STAGED" "$APP" || \(recover(step, "couldn't move the new app into place"))

            """
        case .openNewApp:
            return heading + """
            open the new app.
            say "Opening the new app."
            open_app || \(recover(step, "couldn't open the new app"))

            """
        case .waitForNewApp:
            return heading + """
            wait until the new app runs, and still runs a moment later.
            waited=0
            until new_app_runs; do
              [ "$waited" -lt $((LAUNCH_WAIT * 5)) ] || \(recover(step, "the new app didn't start within $LAUNCH_WAIT seconds"))
              /bin/sleep 0.2
              waited=$((waited + 1))
            done
            /bin/sleep "$STEADY_WAIT"
            new_app_runs || \(recover(step, "the new app quit as it started"))
            say "The new app runs."

            """
        case .deleteOldApp:
            return heading + """
            delete the old copy, now that the new one runs.
            say "Deleting the old copy."
            /bin/rm -rf -- "$ASIDE" || \(recover(step, "couldn't delete the old copy at $ASIDE"))

            """
        case .cleanUp:
            return heading + """
            remove the download and the unpacked folder.
            clean_up || \(recover(step, "couldn't remove the download"))

            """
        }
    }

    /// The call that recovers from `step` failing, saying `why`.
    private static func recover(_ step: InstallStep, _ why: String) -> String {
        switch step.ifItFails {
        case .giveUp: return "give_up \"\(why)\""
        case .reopenOld: return "reopen_old \"\(why)\""
        case .putOldBack: return "put_old_back \"\(why)\""
        case .carryOn: return "say \"\(why); carrying on.\""
        }
    }

    /// A version in a comment, on one line.
    private static func oneLine(_ text: String) -> String {
        text.filter { !$0.isNewline }
    }
}
