//  UITestOfflineTests.swift
//  The Outbox journey's two launch flags (AITD-528): `-uiTestOffline`, which points every request
//  at an address nothing answers, and `-uiTestCacheName`, which lets a relaunch reopen the
//  journal the offline launch queued into.

import XCTest
@testable import Astrid_App

final class UITestOfflineTests: XCTestCase {

    private let production = "https://www.astrid.cc"
    private let localhost = "http://localhost:3000"

    func testOfflineNeedsTheUITestFlag_AITD528() {
        XCTAssertTrue(UITestSession.isOffline(arguments: ["-uiTesting", "-uiTestOffline"]))
        XCTAssertFalse(UITestSession.isOffline(arguments: ["-uiTestOffline"]),
                       "a stray argument must never take the real app offline")
        XCTAssertFalse(UITestSession.isOffline(arguments: ["-uiTesting"]))
    }

    func testAnOfflineRunTalksToNothing_AITD528() {
        let offline = UITestSession.resolvedBaseURL(isUITesting: true, isOffline: true,
                                                    uiTestBaseURL: "https://staging.astrid.cc",
                                                    debugPreference: nil,
                                                    defaultURL: localhost, productionURL: production)
        XCTAssertEqual(offline, UITestSession.unreachableBaseURL,
                       "offline wins over a staging override: the journey needs every request to fail")
        let url = URL(string: offline)
        XCTAssertEqual(url?.host, "127.0.0.1", "loopback, so the run cannot reach anyone else")
        XCTAssertEqual(url?.port, 9, "the discard port refuses at once rather than timing out")
    }

    func testOfflineOutsideATestRunChangesNothing_AITD528() {
        XCTAssertEqual(UITestSession.resolvedBaseURL(isUITesting: false, isOffline: true,
                                                     debugPreference: nil,
                                                     defaultURL: localhost, productionURL: production),
                       localhost)
    }

    func testACacheNameIsOnlyReadUnderTheFlag_AITD528() {
        XCTAssertEqual(UITestSession.cacheName(arguments: ["-uiTesting", "-uiTestCacheName", "outbox-1"]),
                       "outbox-1")
        XCTAssertNil(UITestSession.cacheName(arguments: ["-uiTestCacheName", "outbox-1"]))
        XCTAssertNil(UITestSession.cacheName(arguments: ["-uiTesting", "-uiTestCacheName"]),
                     "a trailing flag with no value must not read past the end")
    }

    func testACacheNameCannotLeaveTheTempDirectory_AITD528() {
        for bad in ["../real", "a/b", "", "name with space", "é", String(repeating: "a", count: 65)] {
            XCTAssertNil(UITestSession.cacheName(arguments: ["-uiTesting", "-uiTestCacheName", bad]),
                         "\"\(bad)\" becomes a directory name, so it must be refused")
        }
    }

    func testANamedCacheIsTheSameFileOnEveryLaunch_AITD528() {
        let first = AppCore.uiTestCacheURL(named: "outbox-1")
        XCTAssertEqual(first, AppCore.uiTestCacheURL(named: "outbox-1"))
        XCTAssertTrue(first.path.hasPrefix(FileManager.default.temporaryDirectory.path),
                      "a UI-test cache never lives beside the user's")
        XCTAssertNotEqual(AppCore.uiTestCacheURL(named: nil), AppCore.uiTestCacheURL(named: nil),
                          "an unnamed run still gets a fresh cache per launch")
    }
}
