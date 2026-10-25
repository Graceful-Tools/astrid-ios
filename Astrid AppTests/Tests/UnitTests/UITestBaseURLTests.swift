//  UITestBaseURLTests.swift
//  Which server a UI-test run talks to (task 44a9cea5).
//
//  The bug this pins was invisible from the Swift side. The dedicated `uitest@astrid.cc`
//  account existed, the keychain exception for it existed, the cookie reached the app — and
//  the suite still ran signed out, because a Debug build points at `http://localhost:3000`
//  and the cookie is a PRODUCTION session. The request failed against a dev server that was
//  not running, auth fell through to "not signed in", and every test needing an account
//  skipped itself while `xcodebuild` exited 0.
//
//  So a credential and a host are one decision. These pin that, and pin the second half —
//  that a test run must not inherit the developer's own `debug_server_url`, because UI tests
//  share the shipping bundle id and would otherwise read a setting that is not theirs.

import XCTest
@testable import Astrid_App

final class UITestBaseURLTests: XCTestCase {

    private let production = "https://www.astrid.cc"
    private let localhost = "http://localhost:3000"

    // MARK: - The bug

    /// THE ONE. A test run goes to production, where its account lives.
    func testAUITestRunTalksToProduction() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: true,
                                          debugPreference: nil,
                                          defaultURL: localhost,
                                          productionURL: production),
            production,
            "A UI-test run carries a production session; pointing it at localhost signs it out")
    }

    /// The developer's own server preference lives in the same container the test run uses.
    /// Inheriting it would send the run wherever they last pointed the app.
    func testTheDebugServerPreferenceDoesNotLeakIntoATestRun() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: true,
                                          debugPreference: "http://192.0.2.10:3000",
                                          defaultURL: localhost,
                                          productionURL: production),
            production,
            "A test run must not adopt the developer's debug_server_url")
    }

    // MARK: - Everything else is unchanged

    /// Normal Debug behaviour: the preference wins when someone set one.
    func testANormalRunStillHonoursTheDebugPreference() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: false,
                                          debugPreference: "http://192.0.2.10:3000",
                                          defaultURL: localhost,
                                          productionURL: production),
            "http://192.0.2.10:3000")
    }

    /// And falls back to the build's default when they did not.
    func testANormalRunWithNoPreferenceUsesTheDefault() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: false,
                                          debugPreference: nil,
                                          defaultURL: localhost,
                                          productionURL: production),
            localhost)
    }

    /// An empty preference is not a preference. A cleared text field writes "", and treating
    /// that as a URL points the app at nothing at all.
    func testAnEmptyPreferenceIsIgnored() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: false,
                                          debugPreference: "   ",
                                          defaultURL: localhost,
                                          productionURL: production),
            localhost)
    }

    // MARK: - -uiTestBaseURL (AITD-527)

    /// A run can be pointed at a staging deploy, so a server change is tested before it ships.
    /// The override replaces production; it does not reopen the debug-preference leak above.
    func testAUITestRunCanBePointedAtStaging() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: true,
                                          uiTestBaseURL: "https://staging.astrid.cc",
                                          debugPreference: "http://192.0.2.10:3000",
                                          defaultURL: localhost,
                                          productionURL: production),
            "https://staging.astrid.cc")
    }

    /// Outside a test run the argument means nothing: a launch argument must not be able to
    /// redirect a real user's app.
    func testTheOverrideIsIgnoredOutsideATestRun() {
        XCTAssertEqual(
            UITestSession.resolvedBaseURL(isUITesting: false,
                                          uiTestBaseURL: "https://staging.astrid.cc",
                                          debugPreference: nil,
                                          defaultURL: localhost,
                                          productionURL: production),
            localhost)
    }

    /// Read from the launch arguments, and only under the UI-test flag.
    func testTheOverrideIsReadFromTheLaunchArguments() {
        XCTAssertEqual(
            UITestSession.baseURLOverride(arguments: ["-uiTesting", "-uiTestBaseURL", "https://staging.astrid.cc/"]),
            "https://staging.astrid.cc")
        XCTAssertNil(UITestSession.baseURLOverride(arguments: ["-uiTestBaseURL", "https://staging.astrid.cc"]),
                     "No -uiTesting, no override")
        XCTAssertNil(UITestSession.baseURLOverride(arguments: ["-uiTesting", "-uiTestBaseURL"]),
                     "A trailing flag with no value must not read past the end")
    }

    /// Something that is not an http(s) URL with a host falls back to production rather than
    /// pointing the run at nothing, which would look exactly like being signed out.
    func testAMalformedOverrideIsIgnored() {
        for bad in ["", "   ", "staging.astrid.cc", "ftp://staging.astrid.cc", "https://"] {
            XCTAssertNil(UITestSession.baseURLOverride(arguments: ["-uiTesting", "-uiTestBaseURL", bad]),
                         "'\(bad)' is not a base URL")
        }
    }
}
