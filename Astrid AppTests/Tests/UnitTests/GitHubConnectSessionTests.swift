//  GitHubConnectSessionTests.swift
//  Regression cover for AITD-362.
//
//  The web OAuth callback can now interrupt a connect with an astrid.cc sign-in page
//  (web task 842601f2). That is survivable only while the connect runs in an
//  ASWebAuthenticationSession, which shares Safari's cookie jar and hands control back to
//  the app when it closes. GitHub Issues was the one provider that instead handed the
//  authorize URL to the system browser: the app was backgrounded, and on return nothing
//  re-read the connection status — `GitHubSyncService.scheduleSync()` guards on
//  `isConnected`, which is exactly what a first connect has not set yet. The screen sat on
//  "not connected" until the user thought to pull-to-refresh.

import XCTest
@testable import Astrid_App

final class GitHubConnectSessionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - The poll that stands in for the app-scheme redirect GitHub/Copilot never send

    func testPollStopsAsSoonAsTheConnectionLands() {
        XCTAssertFalse(ConnectionPoll.shouldContinue(attempt: 0, connected: true))
        XCTAssertFalse(ConnectionPoll.shouldContinue(attempt: 5, connected: true))
    }

    func testPollKeepsGoingWhileDisconnectedAndUnderTheCap() {
        XCTAssertTrue(ConnectionPoll.shouldContinue(attempt: 0, connected: false, maxAttempts: 3))
        XCTAssertTrue(ConnectionPoll.shouldContinue(attempt: 2, connected: false, maxAttempts: 3))
    }

    /// A user who cancels at the sign-in page never connects; the poll must give up rather than
    /// spin forever (item 4 of the task: cancelling leaves no half-connected integration).
    func testPollGivesUpAtTheCap() {
        XCTAssertFalse(ConnectionPoll.shouldContinue(attempt: 3, connected: false, maxAttempts: 3))
        XCTAssertFalse(ConnectionPoll.shouldContinue(attempt: 4, connected: false, maxAttempts: 3))
    }
}
