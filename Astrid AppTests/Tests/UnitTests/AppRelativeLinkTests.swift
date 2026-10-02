//  AppRelativeLinkTests.swift
//  The "set up a model" prompt in chat has to lead somewhere (AITD-451).
//
//  When someone chats with Astrid and has no model set, the server answers with a setup prompt:
//  "Head to [Settings > AI Agents](/settings/agents) …". On web that link works. In the app it
//  was a dead tap: a ROOT-RELATIVE link has no scheme and no host, so the chat's link handler
//  passed it to the system, which has nowhere to send it. The prompt existed; it just could not
//  be acted on.

import XCTest
@testable import Astrid_App

final class AppRelativeLinkTests: XCTestCase {

    /// AITD-451: the server's setup prompt link becomes a link the app routes in-app.
    @MainActor
    func testTheModelSetupLinkResolvesToTheBrandOrigin() {
        let resolved = DeepLinkManager.appURL(forRelativeLink: URL(string: "/settings/agents")!)
        XCTAssertEqual(resolved?.absoluteString, "\(Brand.productionBaseURL)/settings/agents")
        XCTAssertTrue(Brand.webHosts.contains(resolved?.host ?? ""),
                      "it must land on a host DeepLinkManager treats as a universal link")
    }

    @MainActor
    func testAbsoluteAndCustomSchemeLinksAreLeftAlone() {
        XCTAssertNil(DeepLinkManager.appURL(forRelativeLink: URL(string: "https://example.com/settings")!))
        XCTAssertNil(DeepLinkManager.appURL(forRelativeLink: URL(string: "astrid://tasks/abc")!))
        XCTAssertNil(DeepLinkManager.appURL(forRelativeLink: URL(string: "mailto:a@b.c")!))
    }

    /// `//evil.example/x` has no scheme either, but it names a HOST — resolving it would hand an
    /// attacker-chosen site the trust of an app link.
    @MainActor
    func testAProtocolRelativeLinkIsNotAnAppLink() {
        XCTAssertNil(DeepLinkManager.appURL(forRelativeLink: URL(string: "//evil.example/settings")!))
    }

    /// Only root-relative paths: a bare word in a message is not a route.
    @MainActor
    func testAPathWithoutALeadingSlashIsNotAnAppLink() {
        XCTAssertNil(DeepLinkManager.appURL(forRelativeLink: URL(string: "settings/agents")!))
    }
}
