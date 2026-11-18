import Darwin
import Foundation
import ReleaseCore

// tactile-release: the update key's tool. `tactile-release --help` lists the commands; the work is in
// ReleaseCore, and the private key goes only through /usr/bin/security (SecurityToolKeyStore).

let console = Console(
    out: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
    err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
    readInput: { FileHandle.standardInput.readDataToEndOfFile() },
    inputIsTerminal: isatty(STDIN_FILENO) == 1)

exit(Tool.run(Array(CommandLine.arguments.dropFirst()), store: SecurityToolKeyStore(), console: console))
