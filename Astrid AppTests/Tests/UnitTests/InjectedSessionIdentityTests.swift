//  InjectedSessionIdentityTests.swift
//  AITD-576: a UI-test run handed a session is that session's account, never the cached one.
//
//  The Mac UI-test app has a container of its own (AITD-529), and it keeps UserDefaults between
//  runs. Each run mints a new account, but launch restored the previous run's user from
//  UserDefaults offline-first and skipped the server check because the network was not up yet.
//  Every sync pass then failed SyncManager's isolation check ("tasks that don't belong to user
//  …") and the signed-in shell never showed a task or a list.
//
//  ADEV-213: but refusing the cache outright also signed out a relaunch with the SAME session.
//  The Outbox journey (E2EJourneyUITests.test11) relaunches offline, so the server check could
//  not answer and the app fell through to the welcome screen. The cache is trusted again when
//  the session that wrote it is the session this run was handed.

import XCTest
@testable import Astrid_App

final class InjectedSessionIdentityTests: XCTestCase {

    private let cookie = "__Secure-next-auth.session-token=abc"

    func testAITD576_aRunHandedASessionDoesNotTrustAnUnmarkedCachedUser() {
        XCTAssertFalse(AuthManager.trustsCachedIdentity(injectedCookie: cookie, cachedSessionFingerprint: nil))
    }

    func testAITD576_aRunHandedANewSessionDoesNotTrustThePreviousRunsUser() {
        let previous = AuthManager.sessionFingerprint("__Secure-next-auth.session-token=older")
        XCTAssertFalse(AuthManager.trustsCachedIdentity(injectedCookie: cookie, cachedSessionFingerprint: previous))
    }

    func testAITD576_anOrdinaryLaunchStillRestoresTheCachedUserOfflineFirst() {
        XCTAssertTrue(AuthManager.trustsCachedIdentity(injectedCookie: nil, cachedSessionFingerprint: nil))
    }

    func testADEV213_aRelaunchWithTheSameSessionRestoresTheCachedUserOfflineFirst() {
        let written = AuthManager.sessionFingerprint(cookie)
        XCTAssertTrue(AuthManager.trustsCachedIdentity(injectedCookie: cookie, cachedSessionFingerprint: written))
    }

    func testADEV213_theFingerprintIsNotTheCookie() {
        let fingerprint = AuthManager.sessionFingerprint(cookie)
        XCTAssertFalse(fingerprint.contains("abc"), "UserDefaults is a plist on disk; the credential must not be in it")
        XCTAssertEqual(fingerprint, AuthManager.sessionFingerprint(cookie))
        XCTAssertNotEqual(fingerprint, AuthManager.sessionFingerprint(cookie + "d"))
    }
}
