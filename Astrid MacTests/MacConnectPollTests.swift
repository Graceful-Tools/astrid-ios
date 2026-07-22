//  MacConnectPollTests.swift
//  Astrid for Mac — OAuth connect polling: keep checking until connected or the attempt cap.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacConnectPollTests: XCTestCase {

    func testStopsOnceConnected() {
        XCTAssertFalse(MacConnectPoll.shouldContinue(attempt: 0, connected: true))
        XCTAssertFalse(MacConnectPoll.shouldContinue(attempt: 5, connected: true))
    }

    func testContinuesWhileNotConnectedUnderCap() {
        XCTAssertTrue(MacConnectPoll.shouldContinue(attempt: 0, connected: false, maxAttempts: 3))
        XCTAssertTrue(MacConnectPoll.shouldContinue(attempt: 2, connected: false, maxAttempts: 3))
    }

    func testStopsAtCap() {
        XCTAssertFalse(MacConnectPoll.shouldContinue(attempt: 3, connected: false, maxAttempts: 3))
        XCTAssertFalse(MacConnectPoll.shouldContinue(attempt: 4, connected: false, maxAttempts: 3))
    }
}
#endif
