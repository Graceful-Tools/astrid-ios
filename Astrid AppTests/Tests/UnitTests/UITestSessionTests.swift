//  UITestSessionTests.swift
//  What credential a UI-test run uses (tasks 44a9cea5, b7fd8f70).
//
//  Two bugs meet here, and the fix for one would have broken the other if they had been
//  fixed separately.
//
//  1. Every iOS UI test launched the app with `--uitesting`, and every guard in the app
//     checked `-uiTesting`. Different string. So none of the six protections engaged: the
//     throwaway Core Data store, the blanked keychain, cookie isolation, the outbox store,
//     connection-mode persistence. The comments on those guards describe the incident they
//     exist to prevent — a UI test once created lists in Jon's real account.
//
//  2. Every test needing a signed-in app skipped itself, so the suite asserted almost
//     nothing while reporting success.
//
//  Fixing (1) alone makes (2) permanent: a blanked keychain means the app can NEVER be
//  signed in under test. So the isolation has to distinguish "the user's real credential",
//  which stays unreachable, from "a credential this test run was explicitly handed", which
//  is the dedicated uitest@astrid.cc account on astrid.cc.
//
//  These pin that distinction, because getting it wrong in the permissive direction hands
//  a test suite the real account back.

import XCTest
@testable import Astrid_App

final class UITestSessionTests: XCTestCase {

    private let cookie = "__Secure-next-auth.session-token=abc.def.ghi"

    // MARK: - Recognising a UI-test run

    /// One spelling. Six call sites each re-derived this literal, which is how they drifted
    /// apart from the tests in the first place.
    func testTheFlagIsRecognised() {
        XCTAssertTrue(UITestSession.isUITesting(arguments: ["Astrid", "-uiTesting"]))
        XCTAssertFalse(UITestSession.isUITesting(arguments: ["Astrid"]))
    }

    /// The spelling the tests actually used for months. Accepting it is not sloppiness —
    /// it is the difference between the guards working and silently not working, and the
    /// cost of rejecting it is a suite that runs against a real account.
    func testTheOldMisspellingStillCounts() {
        XCTAssertTrue(UITestSession.isUITesting(arguments: ["Astrid", "--uitesting"]))
        XCTAssertTrue(UITestSession.isUITesting(arguments: ["Astrid", "--uiTesting"]))
    }

    /// A substring is not the flag. `-uiTestingSomethingElse` must not switch the app into
    /// test mode on a real device.
    func testASimilarArgumentIsNotTheFlag() {
        XCTAssertFalse(UITestSession.isUITesting(arguments: ["Astrid", "-uiTestingHarness"]))
        XCTAssertFalse(UITestSession.isUITesting(arguments: ["Astrid", "uitesting"]))
    }

    // MARK: - The injected credential

    /// Handed a cookie, a test run uses it. This is what lets the suite be signed in at all.
    func testAnInjectedCookieIsUsed() {
        XCTAssertEqual(
            UITestSession.injectedCookie(arguments: ["-uiTesting", "-uiTestSessionCookie", cookie],
                                         environment: [:]),
            cookie)
    }

    /// The environment works too — a cookie is a credential, and an argument list shows up in
    /// `ps` output while an environment variable does not.
    func testTheEnvironmentIsAlsoRead() {
        XCTAssertEqual(
            UITestSession.injectedCookie(arguments: ["-uiTesting"],
                                         environment: ["ASTRID_UITEST_COOKIE": cookie]),
            cookie)
    }

    /// THE IMPORTANT ONE. Without the flag there is no injection, so a stray environment
    /// variable on a developer's machine cannot quietly point the real app at a test account.
    func testNothingIsInjectedWithoutTheFlag() {
        XCTAssertNil(
            UITestSession.injectedCookie(arguments: ["Astrid"],
                                         environment: ["ASTRID_UITEST_COOKIE": cookie]))
    }

    /// A test run with no cookie stays signed out rather than falling back to the keychain.
    /// That is the pre-existing safety property and it must survive this change.
    func testATestRunWithNoCookieGetsNothing() {
        XCTAssertNil(UITestSession.injectedCookie(arguments: ["-uiTesting"], environment: [:]))
    }

    /// Empty or whitespace is not a credential. An unset shell variable expands to "", and
    /// treating that as a session produces a confusing 401 rather than an obvious signed-out
    /// app.
    func testAnEmptyCookieIsNotACredential() {
        XCTAssertNil(UITestSession.injectedCookie(arguments: ["-uiTesting", "-uiTestSessionCookie", ""],
                                                  environment: [:]))
        XCTAssertNil(UITestSession.injectedCookie(arguments: ["-uiTesting"],
                                                  environment: ["ASTRID_UITEST_COOKIE": "   "]))
    }

    /// A trailing flag with no value must not read past the end of the arguments.
    func testAMissingValueDoesNotCrash() {
        XCTAssertNil(UITestSession.injectedCookie(arguments: ["-uiTesting", "-uiTestSessionCookie"],
                                                  environment: [:]))
    }

    /// The argument wins over the environment, so a single run can be overridden without
    /// unsetting anything.
    func testTheArgumentBeatsTheEnvironment() {
        XCTAssertEqual(
            UITestSession.injectedCookie(arguments: ["-uiTesting", "-uiTestSessionCookie", cookie],
                                         environment: ["ASTRID_UITEST_COOKIE": "other"]),
            cookie)
    }
}
