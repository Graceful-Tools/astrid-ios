//  SettingsDeepLinkTests.swift
//  AITD-458 — settings deep links opened nothing. DeepLinkManager set
//  `SettingsPresenter.isSettingsPresented` and pushed onto its path, and the only reader of that
//  flag (a sheet modifier) had no caller since settings moved into the main panel. So
//  `astrid://settings/<page>` and `https://astrid.cc/settings/<page>` — the Connections and Agent
//  Hub links the web's emails send among them — changed nothing on screen.
//
//  Now a link is a request the main panel takes: it switches the panel to Settings and the
//  settings stack pushes the page.

import XCTest
@testable import Astrid_App

@MainActor
final class SettingsDeepLinkTests: XCTestCase {

    override func setUp() async throws {
        SettingsPresenter.shared.reset()
    }

    override func tearDown() async throws {
        SettingsPresenter.shared.reset()
    }

    private func source(_ relativePath: String) throws -> String {
        try RepositoryLocator.source(at: relativePath)
    }

    /// AITD-458: the web's Connections link lands on the Connections screen, inside Settings.
    func testAITD458_webConnectionsLinkShowsConnectionsInTheSettingsPanel() throws {
        let url = try XCTUnwrap(URL(string: "\(Brand.productionBaseURL)/settings/connections"))
        DeepLinkManager.shared.handleURL(url)

        let panel = SettingsPresenter.shared.takeRequest()
        XCTAssertEqual(panel, SettingsPresenter.panelId, "the main panel switches to Settings")
        XCTAssertEqual(SettingsPresenter.shared.page, .connections, "and Settings pushes the page")
    }

    /// AITD-458: the Agent Hub link, in the custom-scheme form.
    func testAITD458_customSchemeAgentsLinkShowsTheAgentHub() throws {
        DeepLinkManager.shared.handleURL(try XCTUnwrap(URL(string: "astrid://settings/agents")))

        XCTAssertEqual(SettingsPresenter.shared.takeRequest(), SettingsPresenter.panelId)
        XCTAssertEqual(SettingsPresenter.shared.page, .agents)
    }

    /// AITD-458: a bare settings link opens Settings itself, with nothing pushed.
    func testAITD458_bareSettingsLinkOpensSettings() throws {
        DeepLinkManager.shared.handleURL(try XCTUnwrap(URL(string: "astrid://settings")))

        XCTAssertEqual(SettingsPresenter.shared.takeRequest(), SettingsPresenter.panelId)
        XCTAssertNil(SettingsPresenter.shared.page)
    }

    /// A request is taken once — a panel that re-appears later does not replay it.
    func testAITD458_aRequestIsTakenOnce() throws {
        DeepLinkManager.shared.handleURL(try XCTUnwrap(URL(string: "astrid://settings/reminders")))
        XCTAssertNotNil(SettingsPresenter.shared.takeRequest())
        XCTAssertNil(SettingsPresenter.shared.takeRequest())
    }

    /// The bug was a flag with no reader. Every layout that can show the Settings panel takes the
    /// request, and the settings stack pushes the presenter's page.
    func testAITD458_theMainPanelAndTheSettingsStackReadThePresenter() throws {
        let main = try source("Astrid App/Views/MainTabView.swift")
        XCTAssertTrue(main.contains("SettingsPresenter.shared.$request"),
                      "MainTabView (iPhone and iPad layouts) must take settings deep-link requests")
        XCTAssertTrue(main.contains("takeRequest()"))

        let settings = try source("Astrid App/Views/Settings/SettingsView.swift")
        XCTAssertTrue(settings.contains("navigationDestination(item: $presenter.page"),
                      "SettingsView must push the page a link asked for")

        let presenter = try source("Astrid App/Core/Services/SettingsPresenter.swift")
        XCTAssertFalse(presenter.contains("SettingsPresentationModifier"), "the dead sheet path is gone")
        XCTAssertFalse(presenter.contains("isSettingsPresented"), "no flag without a reader")
    }
}
