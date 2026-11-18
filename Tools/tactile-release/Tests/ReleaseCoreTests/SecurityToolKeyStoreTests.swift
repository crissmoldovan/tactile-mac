import Foundation
@testable import ReleaseCore
import XCTest

/// What the real key store would ask `/usr/bin/security` to do, seen through a fake runner: nothing here
/// runs `security` or touches a Keychain.
final class SecurityToolKeyStoreTests: XCTestCase {
    private let runner = FakeRunner()
    private lazy var store = SecurityToolKeyStore(runner: runner)

    func testAddingPassesTheKeyOnStandardInputOnly() throws {
        runner.answers["login-keychain"] = ProcessResult(status: 0, output: Data("    \"/Volumes/Home/someone/Library/Keychains/login.keychain-db\"\n".utf8))
        let key = UpdateKey.encode(UpdateKey.newPrivateKey())
        try store.add(keyID: "k1", privateKey: key)

        let add = try XCTUnwrap(runner.calls.last)
        XCTAssertEqual(add.executable, "/usr/bin/security")
        XCTAssertEqual(add.arguments, ["-i"], "the key is never an argument, so never in a process list")
        let line = String(decoding: try XCTUnwrap(add.input), as: UTF8.self)
        XCTAssertEqual(line, """
        add-generic-password -s "Tactile update signing key" -a "k1" -T "/usr/bin/security" -w "\(key)" \
        "/Volumes/Home/someone/Library/Keychains/login.keychain-db"\n
        """)
        for call in runner.calls { XCTAssertFalse(call.arguments.joined(separator: " ").contains(key)) }
    }

    func testTheAddLineRefusesValuesThatWouldBreakItsQuoting() {
        for bad in ["a\"b", "a\\b", "a\nb"] {
            XCTAssertThrowsError(try SecurityToolKeyStore.addCommand(service: "s", keyID: "k1", privateKey: bad, keychain: "/k"))
            XCTAssertThrowsError(try SecurityToolKeyStore.addCommand(service: "s", keyID: "k1", privateKey: "x", keychain: bad))
        }
    }

    func testLookingForTheItemNeverAsksForItsData() throws {
        runner.answers["find-generic-password"] = ProcessResult(status: 0)
        XCTAssertTrue(try store.contains(keyID: "k1"))
        let call = try XCTUnwrap(runner.calls.last)
        XCTAssertEqual(call.arguments, ["find-generic-password", "-s", "Tactile update signing key", "-a", "k1"])
        XCTAssertFalse(call.arguments.contains("-w") || call.arguments.contains("-g"))

        runner.answers["find-generic-password"] = ProcessResult(status: 44)
        XCTAssertFalse(try store.contains(keyID: "k1"))
        runner.answers["find-generic-password"] = ProcessResult(status: 51, errorOutput: Data("security: locked\n".utf8))
        XCTAssertThrowsError(try store.contains(keyID: "k1"))
    }

    func testReadingTrimsTheLineAndMapsNotFoundToNothing() throws {
        runner.answers["find-generic-password"] = ProcessResult(status: 0, output: Data("c2VjcmV0\n".utf8))
        XCTAssertEqual(try store.privateKey(keyID: "k1"), "c2VjcmV0")
        XCTAssertEqual(runner.calls.last?.arguments, ["find-generic-password", "-s", "Tactile update signing key", "-a", "k1", "-w"])
        runner.answers["find-generic-password"] = ProcessResult(status: 44)
        XCTAssertNil(try store.privateKey(keyID: "k1"))
    }

    func testAReadErrorDoesNotRepeatWhatSecurityPrinted() {
        runner.answers["find-generic-password"] = ProcessResult(status: 36, output: Data("c2VjcmV0".utf8), errorOutput: Data("c2VjcmV0".utf8))
        XCTAssertThrowsError(try store.privateKey(keyID: "k1")) { error in
            XCTAssertFalse("\(error)".contains("c2VjcmV0"))
        }
    }

    func testABadKeyIDIsRefusedBeforeSecurityRuns() {
        XCTAssertThrowsError(try store.contains(keyID: "k 1"))
        XCTAssertThrowsError(try store.add(keyID: "k\"1", privateKey: "x"))
        XCTAssertTrue(runner.calls.isEmpty)
    }
}
