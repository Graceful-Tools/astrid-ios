//  UITestSessionResource.swift
//  The session a UI-test run was handed, for BOTH UI suites (AITD-529).
//
//  `scripts/lib/uitest-session.sh` mints a per-run account and writes `UITestSession.plist` into
//  the suite's folder; the synchronized group copies it into the test bundle, and this reads it
//  back. Not an environment variable: xcodebuild forwards neither the plain variable nor the
//  TEST_RUNNER_-prefixed setting to the xctrunner (measured 2026-08-16) — see `UITestLaunch`.
//
//  It lived inside the iOS suite's `UITestLaunch`, which is why the Mac suite could never be
//  signed in: the Mac target had no way to read a session even once the app accepted one. This
//  file is compiled into each UI target through `UITestSupport`, so `Bundle(for:)` finds the
//  plist in whichever bundle is running.

import Foundation

enum UITestSessionResource {

    static let resourceName = "UITestSession"
    static let cookieResourceKey = "sessionCookie"

    /// Environment variable carrying the cookie — honoured first, so a scheme variable set in
    /// Xcode keeps working.
    static let cookieEnvironmentKey = "ASTRID_UITEST_COOKIE"

    static let productionBaseURL = "https://www.astrid.cc"

    /// The session this run was given, or nil.
    static let sessionCookie: String? = {
        if let fromEnvironment = nonEmpty(ProcessInfo.processInfo.environment[cookieEnvironmentKey]) {
            return fromEnvironment
        }
        return nonEmpty(plist[cookieResourceKey] as? String)
    }()

    /// This run's seeded fixtures by id, or nil on the shared-account path (AITD-527).
    ///
    /// Only when the cookie in use is the one the plist was written with — fixture ids from one
    /// account are meaningless under another's session.
    static let fixtures: UITestFixtures? = {
        guard let cookie = sessionCookie,
              cookie == nonEmpty(plist[cookieResourceKey] as? String),
              let json = plist["fixtures"] as? String
        else { return nil }
        return UITestFixtures.decode(json)
    }()

    /// The server the app under test — and `UITestAPI` — talks to (AITD-527): production unless
    /// the runner wrote a `baseURL` (`ASTRID_UITEST_BASE_URL`).
    static let baseURL: String = {
        var value = nonEmpty(plist["baseURL"] as? String) ?? productionBaseURL
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }()

    private static let plist: [String: Any] = {
        let bundle = Bundle(for: UITestSessionBundleToken.self)
        guard let url = bundle.url(forResource: resourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()

    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Only exists to locate the test bundle.
private final class UITestSessionBundleToken {}

/// A precondition the harness GUARANTEES did not hold — so it is the app's failure, not a reason
/// to skip.
///
/// The suite threw `XCTSkip` for "no task rows", "detail did not open", "quick add never took
/// focus" and the like, from before the seeder guaranteed an account with five fixture tasks.
/// Since then every one of those has been a failure wearing a skip, and the suite reported
/// green while asserting nothing (AITD-525). XCTest records a thrown error as a failure carrying
/// this message, so the reason still reads in the result.
struct UITestFailure: Error, CustomStringConvertible, LocalizedError {
    let description: String
    init(_ description: String) { self.description = description }
    var errorDescription: String? { description }
}
