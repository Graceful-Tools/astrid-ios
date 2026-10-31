//  MacViewRefreshTests.swift
//  Regression tests for AITD-570 — "[mac] make sure we refresh list when viewing. but do so
//  efficiently!"
//
//  Opening a list called `fetchTasksForListFromServer` and threw the answer away: a paginated
//  fetch of the WHOLE list on every click that never reached the store, so nothing on screen
//  changed. Coming back to the app refreshed nothing at all. Viewing now asks for one delta sync
//  pass — throttled, so clicking through the sidebar costs one request, not one per click.

import XCTest
@testable import Astrid_Mac

final class MacViewRefreshTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testViewingAListRefreshesIt() {
        var gate = MacViewRefreshGate()
        XCTAssertTrue(gate.admit(isOnline: true, isSyncing: false, lastSync: nil, now: t0))
    }

    /// Offline there is nothing to fetch; a pass already running is doing this work.
    func testNoRefreshOfflineOrMidSync() {
        var gate = MacViewRefreshGate()
        XCTAssertFalse(gate.admit(isOnline: false, isSyncing: false, lastSync: nil, now: t0))
        XCTAssertFalse(gate.admit(isOnline: true, isSyncing: true, lastSync: nil, now: t0))
    }

    /// The "efficiently" half: switching list to list inside the window is one pass, not many.
    func testClickingThroughListsIsThrottled() {
        var gate = MacViewRefreshGate()
        XCTAssertTrue(gate.admit(isOnline: true, isSyncing: false, lastSync: nil, now: t0))
        XCTAssertFalse(gate.admit(isOnline: true, isSyncing: false, lastSync: nil, now: t0 + 2))
        XCTAssertFalse(gate.admit(isOnline: true, isSyncing: false, lastSync: nil,
                                  now: t0 + MacViewRefreshGate.minInterval - 1))
        XCTAssertTrue(gate.admit(isOnline: true, isSyncing: false, lastSync: nil,
                                 now: t0 + MacViewRefreshGate.minInterval))
    }

    /// A pass that just ran for any other reason (⌘R, sign-in) already answered the question.
    func testARecentSyncCountsAsFresh() {
        var gate = MacViewRefreshGate()
        XCTAssertFalse(gate.admit(isOnline: true, isSyncing: false, lastSync: t0 - 5, now: t0))
        XCTAssertTrue(gate.admit(isOnline: true, isSyncing: false,
                                 lastSync: t0 - MacViewRefreshGate.minInterval, now: t0))
    }

    /// A refused view is not an attempt: coming back online must refresh at once, not after the
    /// throttle window an offline click started.
    func testARefusedViewDoesNotStartTheThrottle() {
        var gate = MacViewRefreshGate()
        XCTAssertFalse(gate.admit(isOnline: false, isSyncing: false, lastSync: nil, now: t0))
        XCTAssertTrue(gate.admit(isOnline: true, isSyncing: false, lastSync: nil, now: t0 + 1))
    }
}
