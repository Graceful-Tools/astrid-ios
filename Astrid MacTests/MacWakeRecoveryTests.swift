//  MacWakeRecoveryTests.swift
//  Regression for task de2764fb — "make sure SSE and notifications all work".
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

    // MARK: - The policy that made the stream stay dead

    /// Recovery RESETS the count. Without this the exhausted attempts from the sleep window keep
    /// the stream permanently dead.
    func testRecoveryResetsTheAttemptCount() {
        XCTAssertEqual(SSEReconnectPolicy.attemptsAfterRecovery(), 0)
        XCTAssertTrue(SSEReconnectPolicy.shouldRetry(attempt: SSEReconnectPolicy.attemptsAfterRecovery()),
                      "After a wake the stream must be willing to try again")
    }

    func testGivesUpAfterTheBoundedAttempts() {
        XCTAssertTrue(SSEReconnectPolicy.shouldRetry(attempt: SSEReconnectPolicy.maxAttempts - 1))
        XCTAssertFalse(SSEReconnectPolicy.shouldRetry(attempt: SSEReconnectPolicy.maxAttempts))
    }

    /// Backoff grows but stays capped, so a long outage doesn't push the next try minutes out.
    func testBackoffGrowsAndIsCapped() {
        XCTAssertLessThan(SSEReconnectPolicy.delay(attempt: 1), SSEReconnectPolicy.delay(attempt: 3))
        XCTAssertLessThanOrEqual(SSEReconnectPolicy.delay(attempt: 99), 60)
    }

    /// A 401 is not a transient failure — retrying cannot fix a missing session.
    func testDoesNotRetryOnAuthFailure() {
        XCTAssertFalse(SSEReconnectPolicy.shouldRetry(afterStatusCode: 401))
        XCTAssertTrue(SSEReconnectPolicy.shouldRetry(afterStatusCode: 500))
    }
}
#endif
