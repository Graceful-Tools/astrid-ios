//  UITestIsolationTests.swift
//  UI tests run against the SHIPPING bundle id, so every ambient credential the app can reach is a
//  route into the user's real account. This happened for real: a UI test created 48 lists and 74
//  tasks in the owner's account, because blanking the keychain still left the SHARED, PERSISTENT
//  HTTPCookieStorage attached to every request.
//
//  These pin each isolation seam so a future change cannot quietly reopen one.

import XCTest
@testable import Astrid_Mac

final class UITestIsolationTests: XCTestCase {

    /// A hardened configuration must carry NO cookie jar — that jar is what authenticated the app
    /// as the real user with no credential of its own.
    func testHardenedSessionHasNoCookieJar() throws {
        try XCTSkipUnless(UITestNetworkIsolation.isUITesting,
                          "Hardening only applies under -uiTesting; this asserts the flag's effect")
        let hardened = UITestNetworkIsolation.harden(URLSessionConfiguration.default)
        XCTAssertNil(hardened.httpCookieStorage)
        XCTAssertFalse(hardened.httpShouldSetCookies)
        XCTAssertEqual(hardened.httpCookieAcceptPolicy, .never)
        XCTAssertNil(hardened.urlCredentialStorage)
    }

    /// In a NORMAL run nothing is hardened — the app must still authenticate for real users.
    func testNormalRunKeepsCookiesWorking() {
        guard !UITestNetworkIsolation.isUITesting else { return }
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        let result = UITestNetworkIsolation.harden(config)
        XCTAssertTrue(result.httpShouldSetCookies, "Hardening must not affect real users")
    }

    /// The flag is read from the launch arguments, so a normal launch is never hardened.
    func testIsolationIsOffWithoutTheLaunchArgument() {
        XCTAssertEqual(UITestNetworkIsolation.isUITesting,
                       ProcessInfo.processInfo.arguments.contains("-uiTesting"))
    }
}
