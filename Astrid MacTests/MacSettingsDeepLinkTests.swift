//  MacSettingsDeepLinkTests.swift
//  AITD-452 — the Mac half of AITD-451: Astrid's "set up a model" chat reply links to
//  `/settings/agents`, and on Mac that tap did nothing. MacDeepLink only knew tasks and lists,
//  the link is root-relative (no scheme, no host), and nothing routed to a settings page.

import XCTest
@testable import Astrid_Mac

final class MacSettingsDeepLinkTests: XCTestCase {

    /// AITD-452: the server's setup prompt link, exactly as it arrives in the chat message.
    func testTheModelSetupChatLinkOpensAgentsSettings() {
        XCTAssertEqual(MacDeepLink.parse(chatLink: URL(string: "/settings/agents")!), .settings(.agents))
    }

    func testTheWebAndCustomSchemeFormsRouteToo() {
        XCTAssertEqual(MacDeepLink.parse(URL(string: "\(Brand.productionBaseURL)/settings/agents")!),
                       .settings(.agents))
        XCTAssertEqual(MacDeepLink.parse(URL(string: "astrid://settings/agents")!), .settings(.agents))
    }

    /// The Agents page is the Settings window's AI tab.
    func testAgentsSettingsIsTheAITab() {
        XCTAssertEqual(MacSettingsTab(page: .agents), .ai)
    }

    func testAnUnknownSettingsPageIsNotRouted() {
        XCTAssertNil(MacDeepLink.parse(chatLink: URL(string: "/settings/nonsense")!))
        XCTAssertNil(MacDeepLink.parse(URL(string: "astrid://settings")!))
    }

    /// `//evil.example/…` has no scheme but names a HOST; it must not be trusted as an app link.
    func testAProtocolRelativeChatLinkIsNotRouted() {
        XCTAssertNil(MacDeepLink.parse(chatLink: URL(string: "//evil.example/settings/agents")!))
    }

    /// Ordinary links in a chat still parse as before — tasks keep routing, foreign sites don't.
    func testChatLinksToTasksAndForeignSitesAreUnchanged() {
        XCTAssertEqual(MacDeepLink.parse(chatLink: URL(string: "/tasks/t-42")!), .task("t-42"))
        XCTAssertNil(MacDeepLink.parse(chatLink: URL(string: "https://example.com/settings/agents")!))
    }

    // MARK: AITD-458 — every settings page a link can name, not only Agents

    /// AITD-458: the Connections link the web's emails send opens the AI tab and its
    /// Connections sheet (the Mac's Connections live under the Agent Hub).
    func testAITD458_connectionsLinkOpensConnections() {
        XCTAssertEqual(MacDeepLink.parse(URL(string: "\(Brand.productionBaseURL)/settings/connections")!),
                       .settings(.connections))
        XCTAssertEqual(MacSettingsTab(page: .connections), .ai)
        XCTAssertTrue(MacSettingsTab.opensConnections(.connections))
        XCTAssertTrue(MacSettingsTab.opensConnections(.apiAccess), "old api-access links keep working")
        XCTAssertFalse(MacSettingsTab.opensConnections(.agents))
    }

    /// AITD-458: the pages iOS routes route on the Mac too, to the tab that holds them.
    func testAITD458_settingsPagesMapToTheirTab() {
        XCTAssertEqual(MacDeepLink.parse(URL(string: "astrid://settings/reminders")!), .settings(.reminders))
        XCTAssertEqual(MacSettingsTab(page: .reminders), .reminders)
        XCTAssertEqual(MacSettingsTab(page: .account), .account)
        XCTAssertEqual(MacSettingsTab(page: .profile), .account)
        XCTAssertEqual(MacSettingsTab(page: .language), .language)
        XCTAssertEqual(MacSettingsTab(page: .appearance), .general)
        XCTAssertEqual(MacSettingsTab(page: .chatgpt), .ai)
    }

    /// AITD-458: routing a Connections link asks the Agent Hub for its Connections sheet.
    @MainActor
    func testAITD458_routingConnectionsRequestsTheSheet() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: MacSettingsTab.connectionsRequestKey)
        defer { defaults.removeObject(forKey: MacSettingsTab.connectionsRequestKey)
                defaults.removeObject(forKey: MacSettingsTab.defaultsKey) }

        MacDeepLinkRouter.select(.connections)
        XCTAssertEqual(defaults.string(forKey: MacSettingsTab.defaultsKey), MacSettingsTab.ai.rawValue)
        XCTAssertTrue(defaults.bool(forKey: MacSettingsTab.connectionsRequestKey))

        MacDeepLinkRouter.select(.agents)
        XCTAssertFalse(defaults.bool(forKey: MacSettingsTab.connectionsRequestKey))
    }
}
