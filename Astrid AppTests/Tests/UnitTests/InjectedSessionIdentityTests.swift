//  InjectedSessionIdentityTests.swift
//  AITD-576: a UI-test run handed a session is that session's account, never the cached one.
//
//  The Mac UI-test app has a container of its own (AITD-529), and it keeps UserDefaults between
//  runs. Each run mints a new account, but launch restored the previous run's user from
//  UserDefaults offline-first and skipped the server check because the network was not up yet.
//  Every sync pass then failed SyncManager's isolation check ("tasks that don't belong to user
//  …") and the signed-in shell never showed a task or a list.

import XCTest
@testable import Astrid_App

final class InjectedSessionIdentityTests: XCTestCase {

    func testAITD576_aRunHandedASessionDoesNotTrustTheCachedUser() {
        XCTAssertFalse(AuthManager.trustsCachedIdentity(injectedCookie: "__Secure-next-auth.session-token=abc"))
    }

    func testAITD576_anOrdinaryLaunchStillRestoresTheCachedUserOfflineFirst() {
        XCTAssertTrue(AuthManager.trustsCachedIdentity(injectedCookie: nil))
    }
}
