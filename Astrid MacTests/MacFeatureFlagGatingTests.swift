//  MacFeatureFlagGatingTests.swift
//  Regression for task b0048881 — the Mac UI must gate Google Tasks on the remote flag
//  snapshot (visible only when enabled; off by default so the kill switch is honored).

import XCTest
@testable import Astrid_Mac

final class MacFeatureFlagGatingTests: XCTestCase {

    func testGoogleTasksOffByDefault() {
        let snapshot = FeatureFlagSnapshot(version: 0, features: [:], updatedAt: .distantPast)
        XCTAssertFalse(snapshot.isEnabled(.googleTasks),
                       "With no remote state, Google Tasks must default OFF — the Mac row stays hidden.")
    }

    func testGoogleTasksHiddenWhenFlagOff() {
        let snapshot = FeatureFlagSnapshot(version: 3, features: ["google_tasks": false], updatedAt: Date())
        XCTAssertFalse(snapshot.isEnabled(.googleTasks),
                       "Kill switch OFF must hide the Mac Google Tasks row and skip its sync.")
    }

    func testGoogleTasksShownWhenFlagOn() {
        let snapshot = FeatureFlagSnapshot(version: 3, features: ["google_tasks": true], updatedAt: Date())
        XCTAssertTrue(snapshot.isEnabled(.googleTasks),
                      "A remote rollout ON must reveal the Mac Google Tasks row and schedule sync.")
    }
}
