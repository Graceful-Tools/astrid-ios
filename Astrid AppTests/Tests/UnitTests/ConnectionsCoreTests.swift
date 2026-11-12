//  ConnectionsCoreTests.swift
//  The Connections screen's service goes through astrid-core (AITD-620): the commands it sends,
//  the refusals the core makes before anything reaches a server, and the agent hub's error helper
//  reading a core failure the way it read an `AstridAPIError`.
//
//  The unit host runs an in-memory core with no network, so the round trips themselves are the
//  core's own tests (`dispatch/tests/connections.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

final class ConnectionsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func failure(_ json: String) throws -> CoreFailure {
        try JSONDecoder().decode(CoreFailure.self, from: Data(json.utf8))
    }

    // MARK: The commands

    func testTheListIsTheCoresConnectionsCommand_AITD620() throws {
        XCTAssertEqual(try json(ConnectionCommands.list())["kind"] as? String, "connections")
    }

    func testARevokeNamesTheRowsKindAndIdTogether_AITD620() throws {
        let row = Connection(id: "dcr-1", kind: .authorizedApp, name: "Claude Code")
        let sent = try json(ConnectionCommands.revoke(row))
        XCTAssertEqual(sent["kind"] as? String, "revokeConnection")
        XCTAssertEqual(sent["connectionKind"] as? String, "authorizedApp")
        XCTAssertEqual(sent["id"] as? String, "dcr-1")
    }

    func testAPresetMintIsTheCoresTransportCredentialsCommand_AITD620() throws {
        let sent = try json(ConnectionCommands.mint(preset: .webhookServer, agent: "claude"))
        XCTAssertEqual(sent["kind"] as? String, "mintTransportCredentials")
        XCTAssertEqual(sent["preset"] as? String, "webhookServer")
        XCTAssertEqual(sent["agent"] as? String, "claude")
    }

    func testLoadingAClientNamesItsId_AITD620() throws {
        let sent = try json(ConnectionCommands.load(clientId: "astrid_client_abc"))
        XCTAssertEqual(sent["kind"] as? String, "loadOAuthClient")
        XCTAssertEqual(sent["clientId"] as? String, "astrid_client_abc")
    }

    /// The core takes the draft as the editor holds it — URIs one per line — and judges it itself.
    func testACreateSendsTheDraftInTheCoresShape_AITD620() throws {
        var draft = OAuthClientDraft()
        draft.name = "  Windows fixall  "
        draft.descriptionText = "nightly"
        draft.scopes = ["tasks:read"]
        draft.grantTypes = [.authorizationCode, .refreshToken]
        draft.redirectURIText = "https://a.test/cb\n\n  https://b.test/cb"

        let sent = try json(ConnectionCommands.create(draft.createRequest()))
        XCTAssertEqual(sent["kind"] as? String, "createOAuthClient")
        XCTAssertEqual(sent["name"] as? String, "Windows fixall")
        XCTAssertEqual(sent["description"] as? String, "nightly")
        XCTAssertEqual(sent["scopes"] as? [String], ["tasks:read"])
        XCTAssertEqual(sent["grantTypes"] as? [String], ["authorization_code", "refresh_token"])
        XCTAssertEqual(sent["redirectUriText"] as? String, "https://a.test/cb\nhttps://b.test/cb")
    }

    /// An edit carries the whole draft: the core applies the create rules to it (an
    /// authorization-code client keeps a callback), so a body of URIs alone would read as nameless.
    func testAnUpdateCarriesTheWholeDraftBesideTheClientId_AITD620() throws {
        var draft = OAuthClientDraft()
        draft.name = "Mine"
        draft.grantTypes = [.clientCredentials]
        draft.redirectURIText = "https://new.test/cb"

        let sent = try json(ConnectionCommands.update(clientId: "astrid_client_abc", draft: draft))
        XCTAssertEqual(sent["kind"] as? String, "updateOAuthClient")
        XCTAssertEqual(sent["clientId"] as? String, "astrid_client_abc")
        XCTAssertEqual(sent["name"] as? String, "Mine")
        XCTAssertEqual(sent["grantTypes"] as? [String], ["client_credentials"])
        XCTAssertEqual(sent["redirectUriText"] as? String, "https://new.test/cb")
    }

    // MARK: Through the unit host's core — refused before any request

    func testAnUnknownKindIsRefusedByTheCoreNotSent_AITD620() async throws {
        let row = Connection(id: "future-1", kind: .unknown, name: "Something new")
        do {
            try await RemoteResourceService.shared.revokeConnection(row)
            XCTFail("an unknown kind has no path segment to revoke by")
        } catch let failure as CoreFailure {
            XCTAssertEqual(failure.kind, .badRequest)
        }
    }

    func testANamelessClientIsRefusedByTheCoreNotSent_AITD620() async throws {
        let blank = CreateOAuthClientRequest(name: "   ", description: nil, scopes: [],
                                             grantTypes: ["client_credentials"], redirectUris: nil)
        do {
            _ = try await RemoteResourceService.shared.createOAuthClient(blank)
            XCTFail("a draft the core can reject never reaches the server")
        } catch let failure as CoreFailure {
            XCTAssertEqual(failure.kind, .badRequest)
        }
    }

    // MARK: Errors, as the agent hub reads them

    func testACoreRefusalOfTheSessionStillAsksForTheWeb_AITD620() throws {
        XCTAssertTrue(AgentHubErrors.requiresWebSession(
            try failure(#"{"kind":"unauthorized","message":"signed out"}"#)))
        XCTAssertTrue(AgentHubErrors.requiresWebSession(
            try failure(#"{"kind":"refused","message":"{\"error\":\"session only\"}","status":403}"#)))
        XCTAssertFalse(AgentHubErrors.requiresWebSession(
            try failure(#"{"kind":"refused","message":"boom","status":500}"#)))
        XCTAssertFalse(AgentHubErrors.requiresWebSession(
            try failure(#"{"kind":"offline","message":"no route"}"#)))
    }

    func testACoreRefusalShowsTheServersOwnSentence_AITD620() throws {
        let refused = try failure(#"{"kind":"refused","message":"{\"error\":\"Client not found\"}","status":404}"#)
        XCTAssertEqual(AgentHubErrors.message(refused), "Client not found")
        let plain = try failure(#"{"kind":"badRequest","message":"a client needs a name"}"#)
        XCTAssertEqual(AgentHubErrors.message(plain), "a client needs a name")
    }
}
