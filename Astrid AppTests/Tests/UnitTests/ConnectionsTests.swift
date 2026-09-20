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

    private let fixture = """
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

    private func decodeFixture() throws -> [Connection] {
        try JSONDecoder().decode(ConnectionsResponse.self, from: Data(fixture.utf8)).connections
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
        XCTAssertEqual(rows[1].revokePath, "/api/v1/users/me/connections/authorizedApp/dcr-1")
        XCTAssertEqual(rows[4].revokePath, "/api/v1/users/me/connections/webhook/webhook")
    }

    func testSectionsFollowDisplayOrderAndSkipEmptyKinds() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture().filter { $0.kind != .webhook }
        let model = await ConnectionsModel(service: service)
        await model.load()
        let kinds = await model.sections.map(\.kind)
        XCTAssertEqual(kinds, [.authorizedApp, .oauthClient, .customAgent, .accessToken, .unknown])
    }

    // MARK: Revoke

    func testRevokeIsOptimisticAndDropsTheRow() async throws {
        let service = FakeConnectionsService()
        service.rows = try decodeFixture()
        let model = await ConnectionsModel(service: service)
        await model.load()
        let claude = try XCTUnwrap(service.rows.first { $0.id == "dcr-1" })

        await model.revoke(claude)

        XCTAssertEqual(service.revoked.map(\.revokePath), ["/api/v1/users/me/connections/authorizedApp/dcr-1"])
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

// MARK: - Fake service

private final class FakeConnectionsService: ConnectionsServicing {
    var rows: [Connection] = []
    var revoked: [Connection] = []
    var revokeError: Error?
    var mints: [OAuthClientPresetRequest] = []

    func getConnections() async throws -> ConnectionsResponse {
        ConnectionsResponse(connections: rows)
    }

    func revokeConnection(_ connection: Connection) async throws -> ConnectionRevokeResponse {
        if let revokeError { throw revokeError }
        revoked.append(connection)
        return ConnectionRevokeResponse(success: true, kind: connection.kind, id: connection.id, revokedTokens: 1)
    }

    func createOAuthClient(preset: OAuthClientPreset, agent: String) async throws -> MintedOAuthClient {
        mints.append(OAuthClientPresetRequest(preset: preset, agent: agent))
        return MintedOAuthClient(clientId: "astrid_client_minted", clientSecret: "shh")
    }
}
