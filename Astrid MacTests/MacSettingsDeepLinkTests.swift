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
}
