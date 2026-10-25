//  MacUITestLaunchAuthTests.swift
//  AITD-529: the Mac UI suite had no signed-in path. `-uiTesting` forced `isAuthenticated = false`
//  however the run was launched, so Mac had zero end-to-end coverage against the server.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacUITestLaunchAuthTests: XCTestCase {

    /// A real launch is untouched: the saved session decides.
    func testANormalLaunchChecksTheSavedSession_AITD529() {
        XCTAssertEqual(MacUITestArgs.launchAuth(arguments: ["Astrid"], environment: [:]), .normal)
    }

    /// A UI-test run handed no session stays hermetic: the sign-in screen, deterministically,
    /// whatever the machine has saved (6c30df95). The offline-shell tests depend on it.
    func testAUITestRunWithNoSessionStartsSignedOut_AITD529() {
        XCTAssertEqual(MacUITestArgs.launchAuth(arguments: ["Astrid", "-uiTesting"], environment: [:]),
                       .signedOut)
    }

    /// A UI-test run handed a session signs in with it — the per-run account, never the user's.
    func testAUITestRunWithASessionSignsInWithIt_AITD529() {
        let args = ["Astrid", "-uiTesting", "-uiTestSessionCookie", "abc"]
        XCTAssertEqual(MacUITestArgs.launchAuth(arguments: args, environment: [:]), .injectedSession)
        XCTAssertEqual(MacUITestArgs.launchAuth(arguments: ["Astrid", "-uiTesting"],
                                                environment: ["ASTRID_UITEST_COOKIE": "abc"]),
                       .injectedSession)
    }

    /// A stray cookie without the flag must not point the real app at the test account.
    func testACookieWithoutTheFlagIsIgnored_AITD529() {
        XCTAssertEqual(MacUITestArgs.launchAuth(arguments: ["Astrid", "-uiTestSessionCookie", "abc"],
                                                environment: ["ASTRID_UITEST_COOKIE": "abc"]),
                       .normal)
    }
}
#endif

#if os(macOS)
/// `-uiTestSelectTask=<id>` (AITD-529): a journey names the fixture it means, not a position.
final class MacUITestSelectTaskTests: XCTestCase {

    func testSelectsTheNamedTaskWhereverItSorts_AITD529() {
        let args = ["Astrid", "-uiTesting", "-uiTestSelectTask=t-2"]
        XCTAssertEqual(MacUITestArgs.requestedRow(in: ["t-1", "t-2", "t-3"], arguments: args), "t-2")
        XCTAssertTrue(MacUITestArgs.selectsRow(arguments: args))
    }

    /// Not on screen yet: nothing, so the hook tries again when the rows change.
    func testATaskNotInTheRowsSelectsNothing_AITD529() {
        XCTAssertNil(MacUITestArgs.requestedRow(in: ["t-1"], arguments: ["-uiTestSelectTask=t-9"]))
    }

    /// The positional form still works, and an empty id is no request.
    func testTheRowIndexFormIsUnchanged_AITD529() {
        XCTAssertEqual(MacUITestArgs.requestedRow(in: ["a", "b"], arguments: ["-uiTestSelectRow=1"]), "b")
        XCTAssertNil(MacUITestArgs.selectedTaskId(from: ["-uiTestSelectTask="]))
        XCTAssertFalse(MacUITestArgs.selectsRow(arguments: ["Astrid", "-uiTesting"]))
    }
}
#endif
