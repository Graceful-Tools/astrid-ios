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

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - The guard: no platform may open the GitHub authorize URL outside the app

    /// iOS handed it to `openURL`, which is real Safari. AITD-362.
    func testIOSDoesNotOpenTheGitHubAuthorizeURLInTheSystemBrowser() throws {
        let source = try source("Astrid App/Views/Settings/GitHubSyncSettingsView.swift")

        for (index, line) in source.components(separatedBy: .newlines).enumerated() {
            XCTAssertFalse(line.contains("openURL("),
                           "GitHubSyncSettingsView.swift:\(index + 1) sends the connect flow to the "
                           + "system browser. Present it via GitHubSyncService.connect() so the "
                           + "ASWebAuthenticationSession keeps the flow — and the sign-in hop — in the app.")
        }
    }

    /// Mac handed it to the default browser, which need not be Safari at all. AITD-362.
    func testMacDoesNotOpenTheGitHubAuthorizeURLInTheDefaultBrowser() throws {
        let source = try source("Astrid Mac/Views/MacSettingsPanels.swift")

        for (index, line) in source.components(separatedBy: .newlines).enumerated() {
            guard line.contains("PlatformApplication.open(") else { continue }
            XCTAssertFalse(line.contains("authorizeURL"),
                           "MacSettingsPanels.swift:\(index + 1) sends the connect flow to the default "
                           + "browser. Present it via GitHubSyncService.connect().")
        }
    }

    /// The connect belongs to the service, next to Google's, not inline in a view.
    func testGitHubConnectRunsInAnAuthenticationSession() throws {
        let source = try source("Astrid App/Core/Sync/GitHubSyncService.swift")

        XCTAssertTrue(source.contains("func connect()"),
                      "GitHubSyncService must own the connect flow, mirroring GoogleTasksSyncService.connect().")
        XCTAssertTrue(source.contains("OAuthWebConnector"),
                      "GitHubSyncService.connect() must present the authorize URL in an "
                      + "ASWebAuthenticationSession so the callback's sign-in hop shares Safari's cookies.")
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
