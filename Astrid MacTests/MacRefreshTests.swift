//  MacRefreshTests.swift
//  Regression tests for Task 0f525a89 — "no easy way to refresh list or app in mac app".
//
//  The capability existed and the affordance did not: a palette command you had to know to type,
//  which called ListService.fetchLists() and so refreshed the SIDEBAR while stale tasks stayed on
//  screen. There was no button, no menu item and no shortcut.

import XCTest
@testable import Astrid_Mac

final class MacRefreshTests: XCTestCase {

    func testRefreshIsOfferedWhenOnlineAndIdle() {
        XCTAssertTrue(MacRefresh.isEnabled(isOnline: true, isSyncing: false))
    }

    /// Offline there is nothing to fetch — an enabled button that cannot work is worse than a
    /// disabled one, because it looks like the refresh happened.
    func testRefreshIsUnavailableOffline() {
        XCTAssertFalse(MacRefresh.isEnabled(isOnline: false, isSyncing: false))
        XCTAssertFalse(MacRefresh.isEnabled(isOnline: false, isSyncing: true))
    }

    /// A second press while one is running would sit behind SyncManager's own `isSyncing` guard
    /// and do nothing, while the control still looked live.
    func testRefreshCannotBeDoubleFired() {
        XCTAssertFalse(MacRefresh.isEnabled(isOnline: true, isSyncing: true))
    }

    /// The spinner tracks the real sync, so "did it do anything?" is answerable.
    func testProgressTracksTheSync() {
        XCTAssertTrue(MacRefresh.showsProgress(isSyncing: true))
        XCTAssertFalse(MacRefresh.showsProgress(isSyncing: false))
    }

    /// Enabled and spinning are mutually exclusive: whenever the spinner shows, the control is
    /// disabled, so the two states can never contradict each other on screen.
    func testTheControlIsNeverBothSpinningAndPressable() {
        for isOnline in [true, false] {
            for isSyncing in [true, false] {
                let enabled = MacRefresh.isEnabled(isOnline: isOnline, isSyncing: isSyncing)
                let spinning = MacRefresh.showsProgress(isSyncing: isSyncing)
                XCTAssertFalse(enabled && spinning,
                               "online=\(isOnline) syncing=\(isSyncing): pressable while spinning")
            }
        }
    }
}
