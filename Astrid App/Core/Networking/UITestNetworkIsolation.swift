//  UITestNetworkIsolation.swift
//  UI tests must never be able to reach the real account.
//
//  They run against the SHIPPING bundle id, so the app sees the user's own container. Blanking the
//  keychain was not enough: `URLSessionConfiguration.default` uses the SHARED, PERSISTENT
//  HTTPCookieStorage, so a previously-stored session cookie was still attached to every request
//  automatically — the app was authenticated with no credential of its own, and a UI test that
//  created a list created it in the user's account for real.
//
//  Under `-uiTesting` every session is built ephemeral with cookie handling OFF, so no ambient
//  credential can exist.
import Foundation

enum UITestNetworkIsolation {
    static let isUITesting = UITestSession.isUITesting

    /// Apply to any URLSessionConfiguration that would otherwise carry ambient cookies.
    static func harden(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        guard isUITesting else { return configuration }
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil            // no shared, persistent jar
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        return configuration
    }
}
