//  MacWakeRecoveryTests.swift
//  Regression for task de2764fb — "make sure SSE and notifications all work". The stream is
//  astrid-core's; waking asks it to reconnect now (`AppCore.reconnectStream`).
//
//  The failure was silent: a Mac sleeps, the SSE stream dies, its five retries burn against a
//  network that is not there, and once exhausted NOTHING revived it. The app kept running with no
//  live updates until relaunch — which is exactly how "sync doesn't work" gets reported.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacWakeRecoveryTests: XCTestCase {

    func testReconnectsWhenThereIsARealSession() {
        XCTAssertTrue(MacWakeRecovery.shouldReconnect(isAuthenticated: true, isOfflineOnly: false))
    }

    /// Signed out or offline-only, there is nothing to stream — waking must not open a connection.
    func testDoesNotReconnectWithoutASession() {
        XCTAssertFalse(MacWakeRecovery.shouldReconnect(isAuthenticated: false, isOfflineOnly: false))
        XCTAssertFalse(MacWakeRecovery.shouldReconnect(isAuthenticated: true, isOfflineOnly: true))
    }

    // The reconnect policy itself — recovery resets the count, bounded attempts, a capped
    // backoff, no retry on a 401 — is astrid-core's now, with its tests
    // (`realtime::reconnect`, and `a_reconnect_now_cuts_the_backoff_short` for the wake).
}
#endif
