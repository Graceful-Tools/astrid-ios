import XCTest
@testable import Astrid_App

final class FeatureFlagLifecycleTests: XCTestCase {
    func testSettingsForcesFeatureRefreshWhenOpened() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent() // FeatureFlagLifecycleTests.swift
            .deletingLastPathComponent() // UnitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Astrid AppTests
        let settingsURL = repositoryRoot
            .appendingPathComponent("Astrid App/Views/Settings/SettingsView.swift")
        let source = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("await featureFlags.refreshIfStale(force: true)"),
            "Opening Settings must bypass a stale disabled entitlement without adding a startup request"
        )
    }

    func testFirstEverLaunchNeverRefreshes() {
        let decision = FeatureFlagLaunchPolicy.decision(
            previousLaunchCount: 0,
            cacheUpdatedAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertFalse(decision.shouldRefresh)
        XCTAssertEqual(decision.nextLaunchCount, 1)
    }

    func testSecondLaunchRefreshesMissingCache() {
        let decision = FeatureFlagLaunchPolicy.decision(
            previousLaunchCount: 1,
            cacheUpdatedAt: nil,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(decision.shouldRefresh)
    }

    func testFreshCacheDoesNotRefresh() {
        let decision = FeatureFlagLaunchPolicy.decision(
            previousLaunchCount: 2,
            cacheUpdatedAt: Date(timeIntervalSince1970: 950),
            now: Date(timeIntervalSince1970: 1_000),
            ttl: 100
        )
        XCTAssertFalse(decision.shouldRefresh)
    }

    func testUnknownFeaturesDefaultOff() {
        XCTAssertFalse(FeatureFlagSnapshot.defaultValue(for: .googleTasks))
    }

    func testForcedLiveUpdateRefreshesDuringFirstSession() {
        XCTAssertTrue(FeatureFlagRefreshPolicy.shouldRefresh(refreshEligibleThisLaunch: false, force: true))
    }

    func testBackgroundRefreshStillWaitsUntilSecondLaunch() {
        XCTAssertFalse(FeatureFlagRefreshPolicy.shouldRefresh(refreshEligibleThisLaunch: false, force: false))
    }
}
