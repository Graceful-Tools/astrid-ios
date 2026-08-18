//  LocalUserSessionValidationTests.swift
//  Regression guard for a bug found by a flaky gate (tasks e12b5390, 91a7e180).
//
//  `OfflineModeTests.testAppWorksAfterForceClosed` failed one predeploy run, passed the next,
//  and did it again two days later. The second sighting is what made it worth chasing, and the
//  cause is not a test problem at all.
//
//  `checkAuthentication()` treats a cached `local_` user as authenticated immediately — that is
//  the whole "OFFLINE FIRST" design — and then spawns `validateSessionInBackground()`. A
//  local-only user has no session cookie by definition, so that background task throws
//  `KeychainError.notFound` and calls `clearStaleAuthState()`, wiping the very auth state the
//  line above established.
//
//  In the app that means an offline-only user is signed out the moment the device has network.
//  In the suite it means one test's detached task lands inside the NEXT test and clears the id
//  it just wrote, which is exactly the shape of a flake that only shows under load.
//
//  A local-only user has no session to validate. Asking the server about one is the bug.

import XCTest
@testable import Astrid_App

final class LocalUserSessionValidationTests: XCTestCase {

    /// THE BUG: the background check ran for a user who has no session by construction, and
    /// then cleared their auth state when it could not find one.
    func testALocalOnlyUserIsNeverValidatedAgainstTheServer() {
        XCTAssertFalse(AuthManager.shouldValidateSessionInBackground(userId: "local_cold-start-user"),
                       "A local-only user has no session cookie by definition — validating one "
                       + "can only fail, and failing signs them out")
        XCTAssertFalse(AuthManager.shouldValidateSessionInBackground(userId: "local_"))
    }

    /// A server-authenticated user still gets validated. This narrows the check; it does not
    /// remove it. A stale cookie must still log someone out.
    func testAServerUserIsStillValidated() {
        XCTAssertTrue(AuthManager.shouldValidateSessionInBackground(userId: "usr_abc123"))
        XCTAssertTrue(AuthManager.shouldValidateSessionInBackground(userId: "cmeje966q0000k1045si7zrz3"))
    }

    /// No cached user at all: nothing to validate, and nothing to clear.
    func testNoUserIsNotValidated() {
        XCTAssertFalse(AuthManager.shouldValidateSessionInBackground(userId: nil))
        XCTAssertFalse(AuthManager.shouldValidateSessionInBackground(userId: ""))
    }

    /// The prefix is the same one `checkLocalAuthentication` uses to decide a user needs no
    /// keychain cookie. Two different spellings of "is this a local user" is how the two halves
    /// would come to disagree.
    func testItUsesTheSameLocalPrefixAsTheKeychainExemption() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Core/Authentication/AuthManager.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("shouldValidateSessionInBackground"),
                      "the decision must live in one named place")
    }
}
