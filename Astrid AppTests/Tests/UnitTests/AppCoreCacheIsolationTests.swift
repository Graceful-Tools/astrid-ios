//  AppCoreCacheIsolationTests.swift
//  A UI-test run must never open the user's astrid-core cache (AITD-448).
//
//  The Core Data store and the Swift Outbox each gave a `-uiTesting` run a throwaway store. When
//  the data layer moved to astrid-core (2026-09-28) that isolation did not come with it: the run
//  opened the REAL `AstridCore/cache.sqlite`, journal and all. The Mac UI suite works offline, so
//  its list creates waited in that journal — and the next time the real app launched signed in,
//  it delivered them. Ten "UITest List / Focus / Undo" lists reached Jon's account on 2026-09-30,
//  all inside 1.6 seconds: a journal draining, not a suite running.

import XCTest
@testable import Astrid_App

final class AppCoreCacheIsolationTests: XCTestCase {

    /// AITD-448: the run that leaked. Anything but the real file.
    func testAUITestRunNeverOpensTheRealCache() {
        let path = AppCore.cachePath(unitTesting: false, uiTesting: true)
        XCTAssertNotEqual(path, AppCore.cacheURL.path)
        XCTAssertNotEqual(path, ":memory:", "the UI suite needs a real file: the core runs its loops")
        XCTAssertTrue(path.hasPrefix(FileManager.default.temporaryDirectory.path),
                      "a UI-test cache is scratch, not Application Support: \(path)")
    }

    /// One scratch cache per process, so every service reaches the same one and a crash fallback
    /// deletes the scratch file rather than the user's.
    func testTheUITestCacheIsStableWithinARun() {
        XCTAssertEqual(AppCore.cachePath(unitTesting: false, uiTesting: true),
                       AppCore.cachePath(unitTesting: false, uiTesting: true))
    }

    func testUnitTestsStayInMemory() {
        XCTAssertEqual(AppCore.cachePath(unitTesting: true, uiTesting: false), ":memory:")
    }

    func testTheAppItselfKeepsItsCache() {
        XCTAssertEqual(AppCore.cachePath(unitTesting: false, uiTesting: false), AppCore.cacheURL.path)
    }

    /// The upgrade reads the (ephemeral, under test) Core Data store and then writes its done flag
    /// into the REAL UserDefaults — so a UI-test run could mark the user's own upgrade finished.
    func testTheUpgradeRunsOnlyForTheApp() {
        XCTAssertTrue(AppCore.runsUpgrade(unitTesting: false, uiTesting: false))
        XCTAssertFalse(AppCore.runsUpgrade(unitTesting: false, uiTesting: true))
        XCTAssertFalse(AppCore.runsUpgrade(unitTesting: true, uiTesting: false))
    }
}
