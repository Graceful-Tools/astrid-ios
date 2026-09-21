//  ConnectionsTests.swift
//  The Connections screen: everything that can act as the account, revocable from the phone
//  and the Mac. Twin of astrid-web tests/components/connections-list.test.tsx.
//
//  Also the regression for the stale deep-link map: `astrid://settings/api-access` opened the
//  AI-provider key manager and `astrid://settings/agents` a screen the Agent Hub had replaced.

import XCTest
@testable import Astrid_App

final class ConnectionsTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        try RepositoryLocator.source(at: relativePath)
    }

    /// A server that predates AWTD-981: `kind` only, no `category`/`owner`.
    private let legacyFixture = """
    {"connections":[
      {"id":"c1","kind":"oauthClient","name":"My script","actsAs":null,"scopes":["tasks:read"],
       "createdAt":"2026-09-01T10:00:00.000Z","lastUsedAt":null,"expiresAt":null,
       "status":"active","revocable":true,"manageIn":"connections","detail":{"clientId":"astrid_client_1"}},
      {"id":"dcr-1","kind":"authorizedApp","name":"Claude Code","actsAs":"claude@example.test",
       "scopes":["tasks:read","tasks:write"],"createdAt":"2026-09-01T10:00:00Z","lastUsedAt":"2026-09-19T10:00:00Z",
       "expiresAt":"2026-10-19T10:00:00Z","status":"active","revocable":true,"manageIn":"connections",
       "detail":{"activeTokens":2}},
      {"id":"agent-1","kind":"customAgent","name":"nightly","actsAs":"nightly.oc@example.test","scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":null,"status":"active","revocable":true,"manageIn":"agents"},
      {"id":"tok-1","kind":"accessToken","name":"GitHub Copilot cloud agent","actsAs":"copilot@example.test","scopes":["*"],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":"2027-09-01T10:00:00Z","status":"active","revocable":true,"manageIn":"agents"},
      {"id":"webhook","kind":"webhook","name":"hooks.example.test","actsAs":null,"scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":null,"status":"active","revocable":true,"manageIn":"agents"},
      {"id":"future-1","kind":"quantumLink","name":"Something new","scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","status":"active","revocable":true}
    ],"meta":{"apiVersion":"v1","authSource":"session","total":6}}
    """

    /// A server carrying AWTD-981: every row stamped with its `category`, and an app row with
    /// its `owner`. Same six rows, so the two fixtures differ in exactly the thing under test.
    private let facetFixture = """
    {"connections":[
      {"id":"c1","kind":"oauthClient","category":"app","owner":"you","name":"My script","actsAs":null,"scopes":["tasks:read"],
       "createdAt":"2026-09-01T10:00:00.000Z","lastUsedAt":null,"expiresAt":null,
       "status":"active","revocable":true,"manageIn":"connections","detail":{"clientId":"astrid_client_1"}},
      {"id":"dcr-1","kind":"authorizedApp","category":"app","owner":"thirdParty","name":"Claude Code","actsAs":"claude@example.test",
       "scopes":["tasks:read","tasks:write"],"createdAt":"2026-09-01T10:00:00Z","lastUsedAt":"2026-09-19T10:00:00Z",
       "expiresAt":"2026-10-19T10:00:00Z","status":"active","revocable":true,"manageIn":"connections",
       "detail":{"activeTokens":2}},
      {"id":"agent-1","kind":"customAgent","category":"app","owner":"agent","name":"nightly","actsAs":"nightly.oc@example.test","scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":null,"status":"active","revocable":true,"manageIn":"agents"},
      {"id":"tok-1","kind":"accessToken","category":"token","owner":null,"name":"GitHub Copilot cloud agent","actsAs":"copilot@example.test","scopes":["*"],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":"2027-09-01T10:00:00Z","status":"active","revocable":true,"manageIn":"agents"},
      {"id":"webhook","kind":"webhook","category":"webhook","owner":null,"name":"hooks.example.test","actsAs":null,"scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","lastUsedAt":null,"expiresAt":null,"status":"active","revocable":true,"manageIn":"agents"},
      {"id":"future-1","kind":"quantumLink","category":"teleport","owner":"nobody","name":"Something new","scopes":[],
       "createdAt":"2026-09-01T10:00:00Z","status":"active","revocable":true}
    ],"meta":{"apiVersion":"v1","authSource":"session","total":6}}
    """

    private func decodeFixture() throws -> [Connection] {
        try JSONDecoder().decode(ConnectionsResponse.self, from: Data(legacyFixture.utf8)).connections
    }

    private func decodeFacetFixture() throws -> [Connection] {
        try JSONDecoder().decode(ConnectionsResponse.self, from: Data(facetFixture.utf8)).connections
    }

    private func loadedModel(_ rows: [Connection]) async -> ConnectionsModel {
        let service = FakeConnectionsService()
        service.rows = rows
        let model = await ConnectionsModel(service: service)
        await model.load()
        return model
    }

    // MARK: Decoding

    func testDecodesEveryKindTheServerListsAndSurvivesOneItDoesNot() throws {
        let rows = try decodeFixture()
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.map(\.kind), [.oauthClient, .authorizedApp, .customAgent, .accessToken, .webhook, .unknown])
        XCTAssertEqual(rows[1].actsAs, "claude@example.test")
        XCTAssertEqual(rows[1].detail?.activeTokens, 2)
        XCTAssertNil(rows[0].actsAs, "no actsAs means the user themself")
        XCTAssertTrue(rows[2].managedOnAgentsPage)
        XCTAssertFalse(rows[0].managedOnAgentsPage)
    }

    func testAnUnknownKindIsARowThisBuildCannotRevoke() throws {
        let unknown = try XCTUnwrap(decodeFixture().last)
        XCTAssertEqual(unknown.kind, .unknown)
        XCTAssertFalse(unknown.revocable, "the server said revocable, but the path segment would be one we cannot name")
        XCTAssertEqual(unknown.name, "Something new")
    }

    func testTheRevokePathPairsTheRowsOwnKindAndId() throws {
        let rows = try decodeFixture()
        XCTAssertEqual(AstridAPIClient.revokeConnectionPath(rows[1]), "/api/v1/users/me/connections/authorizedApp/dcr-1")
        XCTAssertEqual(AstridAPIClient.revokeConnectionPath(rows[4]), "/api/v1/users/me/connections/webhook/webhook")
    }

    // MARK: Sections (AITD-420 / AWTD-981)

    /// The old server sends no `category`, so the page draws what it always drew.
    func testSectionsFallBackToKindsWhenTheServerPredatesTheFacets() async throws {
        let model = await loadedModel(try decodeFixture().filter { $0.kind != .webhook })
        let headings = await model.sections.map(\.heading)
        XCTAssertEqual(headings, [.kind(.authorizedApp), .kind(.oauthClient), .kind(.customAgent),
                                  .kind(.accessToken), .kind(.unknown)])
        let badges = await model.sections.map(\.showsOwnerBadges)
        XCTAssertEqual(badges, [false, false, false, false, false],
                       "the kind heading already names the row; a badge would say it twice")
    }

    /// AITD-420: three sections, not five. `oauthClient`, `authorizedApp` and `customAgent` are
    /// one credential with three owners, so they collapse into Apps.
    func testAITD420GroupsByCategoryIntoAppsTokensAndWebhook() async throws {
        let model = await loadedModel(try decodeFacetFixture().filter { $0.kind != .unknown })
        let sections = await model.sections
        XCTAssertEqual(sections.map(\.heading),
                       [.category(.app), .category(.token), .category(.webhook)],
                       "five peer sections collapse to three, in app/token/webhook order")
        XCTAssertEqual(sections.map { $0.rows.map(\.id) },
                       [["c1", "dcr-1", "agent-1"], ["tok-1"], ["webhook"]])
        XCTAssertEqual(sections.map(\.showsOwnerBadges), [true, true, true])
    }

    /// The webhook keeps its own section: it is the one row we call OUT to.
    func testAITD420TheWebhookIsNotFoldedInWithTheApps() async throws {
        let model = await loadedModel(try decodeFacetFixture().filter { $0.kind != .unknown })
        let sections = await model.sections
        let webhookSection = try XCTUnwrap(sections.last)
        XCTAssertEqual(webhookSection.heading, .category(.webhook))
        let webhook = try XCTUnwrap(webhookSection.rows.first)
        XCTAssertNil(webhook.actsAs, "it does not act as the account — it is the reverse direction")
        XCTAssertTrue(webhook.scopes.isEmpty)
    }

    func testAITD420EmptyCategoriesAreOmitted() async throws {
        let onlyApps = try decodeFacetFixture().filter { $0.category == .app }
        let model = await loadedModel(onlyApps)
        let headings = await model.sections.map(\.heading)
        XCTAssertEqual(headings, [.category(.app)], "a heading over nothing is a category to rule out for no reason")
    }

    /// An app row wears whose it is; a token or a webhook has no owner distinction to draw.
    func testAITD420OwnerIsTheRowBadgeAndOnlyForApps() throws {
        let rows = try decodeFacetFixture()
        XCTAssertEqual(rows.map(\.owner), [.you, .thirdParty, .agent, nil, nil, nil])
        XCTAssertEqual(rows[0].ownerLabel, "Yours")
        XCTAssertEqual(rows[1].ownerLabel, "Third-party")
        XCTAssertEqual(rows[2].ownerLabel, "Agent")
        XCTAssertNil(rows[3].ownerLabel, "a token's heading already names it")
        XCTAssertNil(rows[4].ownerLabel, "nor does a webhook have an owner to draw")
        XCTAssertNil(rows[5].ownerLabel, "an owner string this build never heard of draws nothing")
    }

    /// The facets group; `kind` still revokes. A client that adopted one and dropped the other
    /// would group beautifully and revoke nothing.
    func testAITD420KindStaysTheRevokePathAndTheAgentWording() throws {
        let rows = try decodeFacetFixture()
        XCTAssertEqual(rows.map(\.kind), [.oauthClient, .authorizedApp, .customAgent, .accessToken, .webhook, .unknown])
        XCTAssertEqual(AstridAPIClient.revokeConnectionPath(rows[2]), "/api/v1/users/me/connections/customAgent/agent-1")
        XCTAssertEqual(AstridAPIClient.revokeConnectionPath(rows[4]), "/api/v1/users/me/connections/webhook/webhook")
        let screen = try source("Astrid App/Core/Platform/ConnectionsScreen.swift")
        XCTAssertTrue(screen.contains("remove_agent_confirm"), "the Custom-Agent wording is still chosen by kind")
    }

    /// A category this build has never heard of is a row it still shows, in its own section —
    /// not a reason to drop back to kind sections for the whole page.
    func testAITD420AnUnknownCategoryGetsItsOwnSectionRatherThanCollapsingThePage() async throws {
        let rows = try decodeFacetFixture()
        XCTAssertEqual(rows[5].category, .unknown, "an unrecognised string is unknown, not absent")
        let model = await loadedModel(rows)
        let headings = await model.sections.map(\.heading)
        XCTAssertEqual(headings, [.category(.app), .category(.token), .category(.webhook), .category(.unknown)])
    }

    /// One row without a `category` means the whole response came from an old deployment.
    func testAITD420AMissingCategoryIsAnOldServerNotAnUncategorisedRow() async throws {
        let mixed = try decodeFixture().prefix(1) + (try decodeFacetFixture().dropFirst())
        let model = await loadedModel(Array(mixed))
        let headings = await model.sections.map(\.heading)
        XCTAssertEqual(headings.first, .kind(.authorizedApp),
                       "the facets are all-or-nothing per response; a gap means a server that predates them")
    }

    func testAITD420TheSectionAndBadgeCopyIsTranslatedEverywhere() throws {
        let keys = ["settings.connections.category.app", "settings.connections.category.token",
                    "settings.connections.category.webhook", "settings.connections.category.unknown",
                    "settings.connections.owner.you", "settings.connections.owner.thirdParty",
                    "settings.connections.owner.agent"]
        for language in ["en", "de", "es", "fr", "it", "nl", "pt", "ru", "ja", "ko", "zh-Hans", "zh-Hant"] {
            let text = try source("Astrid App/Resources/Localizations/\(language).lproj/Localizable.strings")
            for key in keys {
                XCTAssertTrue(text.contains("\"\(key)\""), "\(language) is missing \(key)")
            }
        }
    }

    /// The screen reads the grouping off the section, not off `kind`.
    func testAITD420TheScreenNoLongerHeadsItsSectionsWithTheKind() throws {
        let screen = try source("Astrid App/Core/Platform/ConnectionsScreen.swift")
        XCTAssertFalse(screen.contains("Section(section.kind.localizedLabel)"),
                       "the heading comes from the section's own title now")
        XCTAssertTrue(screen.contains("section.localizedTitle"))
    }

    // MARK: Revoke

    func testRevokeIsOptimisticAndDropsTheRow() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture()
        let model = await ConnectionsModel(service: service)
        await model.load()
        let claude = try XCTUnwrap(service.rows.first { $0.id == "dcr-1" })

        await model.revoke(claude)

        XCTAssertEqual(service.revoked.map(\.id), ["dcr-1"])
        let remaining = await model.connections.map(\.id)
        XCTAssertFalse(remaining.contains("dcr-1"))
        XCTAssertEqual(remaining.count, 5)
    }

    func testRevokeRollsBackWhenTheServerRefuses() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture()
        service.revokeError = URLError(.badServerResponse)
        let model = await ConnectionsModel(service: service)
        await model.load()
        let claude = try XCTUnwrap(service.rows.first { $0.id == "dcr-1" })

        await model.revoke(claude)

        let remaining = await model.connections.map(\.id)
        XCTAssertTrue(remaining.contains("dcr-1"), "a refused revoke puts the row back")
        XCTAssertEqual(remaining.count, 6)
        let message = await model.errorMessage
        XCTAssertNotNil(message)
    }

    /// Two revokes overlap; the second succeeds and the first is refused. Rolling back a
    /// whole-list snapshot would bring the revoked second row back as "Active".
    func testARefusedRevokePutsBackOnlyItsOwnRow() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture()
        service.holdRevokes = true
        service.revokeErrors["dcr-1"] = URLError(.badServerResponse)
        let model = await ConnectionsModel(service: service)
        await model.load()
        let claude = try XCTUnwrap(service.rows.first { $0.id == "dcr-1" })
        let script = try XCTUnwrap(service.rows.first { $0.id == "c1" })

        let first = _Concurrency.Task { await model.revoke(claude) }
        let second = _Concurrency.Task { await model.revoke(script) }
        while await MainActor.run(body: { service.heldIDs.count }) < 2 { await _Concurrency.Task.yield() }
        let inFlight = await model.revokingIDs
        XCTAssertEqual(inFlight, ["dcr-1", "c1"], "both rows show as revoking while both are in flight")

        await MainActor.run { service.release("c1") }
        await second.value
        await MainActor.run { service.release("dcr-1") }
        await first.value

        let remaining = await model.connections.map(\.id)
        XCTAssertTrue(remaining.contains("dcr-1"), "the refused revoke puts its own row back")
        XCTAssertFalse(remaining.contains("c1"), "the revoke that succeeded stays revoked")
        XCTAssertEqual(remaining, ["dcr-1", "agent-1", "tok-1", "webhook", "future-1"], "and it comes back in place")
        let stillRevoking = await model.revokingIDs
        XCTAssertTrue(stillRevoking.isEmpty)
    }

    func testAnUnrevocableRowNeverReachesTheServer() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture()
        let model = await ConnectionsModel(service: service)
        await model.load()
        let unknown = try XCTUnwrap(service.rows.last)

        await model.revoke(unknown)

        XCTAssertTrue(service.revoked.isEmpty)
    }

    // MARK: Transport credentials

    func testThePresetRequestCarriesOnlyPresetAndAgent() throws {
        let data = try JSONEncoder().encode(OAuthClientPresetRequest(preset: .webhookServer, agent: "claude"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["preset"] as? String, "webhookServer")
        XCTAssertEqual(json["agent"] as? String, "claude")
        XCTAssertEqual(json.count, 2, "scopes and grant types are the server's decision, never the client's")
    }

    func testMintingSurfacesTheCredentialsOnce() async {
        let service = FakeConnectionsService()
        let model = await TransportCredentialsModel(service: service)
        await model.mint(preset: .webhookServer, agent: "claude")
        let minted = await model.minted
        XCTAssertEqual(minted?.clientId, "astrid_client_minted")
        XCTAssertEqual(service.mints, [OAuthClientPresetRequest(preset: .webhookServer, agent: "claude")])
    }

    // MARK: Deep links and the web link

    func testDeepLinksOpenTheScreensThatExistNow() throws {
        let presenter = try source("Astrid App/Core/Services/SettingsPresenter.swift")
        XCTAssertFalse(presenter.contains("AIAPIKeyManagerView()"),
                       "api-access must open Connections, not the AI-provider key manager")
        XCTAssertFalse(presenter.contains("AIAssistantSettingsView()"),
                       "agents must open the Agent Hub, which replaced AIAssistantSettingsView")
        XCTAssertTrue(presenter.contains("case connections"))
        XCTAssertNotNil(SettingsPresenter.SettingsPage(rawValue: "connections"))
        XCTAssertNotNil(SettingsPresenter.SettingsPage(rawValue: "api-access"), "old links keep working")
    }

    func testNativeNoLongerSendsAnyoneToTheRetiredAPIAccessPage() throws {
        for path in [
            "Astrid App/Models/AgentHub.swift",
            "Astrid App/Core/Platform/AgentHubScreens.swift",
            "Astrid App/Core/Platform/ConnectionsScreen.swift",
        ] {
            let src = try source(path)
            XCTAssertFalse(src.contains("/settings/api-access"), "\(path) still links to the retired page")
            XCTAssertFalse(src.contains("webAPIAccess"), "\(path) still uses the retired link")
        }
        XCTAssertEqual(AgentHubLinks.webConnections(origin: "https://example.test/")?.absoluteString,
                       "https://example.test/settings/connections")
    }
}
