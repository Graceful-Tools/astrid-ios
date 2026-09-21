//  FakeConnectionsService.swift
//  The stand-in server behind `ConnectionsModel` and `OAuthClientEditorModel`.
//
//  One fake, not one per test file: the two models talk to the same `ConnectionsServicing`
//  boundary, and two fakes of one protocol drift until a test passes against a server neither
//  half of the app would recognise. It started inside ConnectionsTests and moved here when the
//  client editor (AITD-419) needed the same boundary.

import Foundation
@testable import Astrid_App

final class FakeConnectionsService: ConnectionsServicing {
    var rows: [Connection] = []
    var revoked: [Connection] = []
    var revokeError: Error?
    var revokeErrors: [String: Error] = [:]
    var mints: [OAuthClientPresetRequest] = []

    /// When set, each revoke parks until `release(_:)` names it, so a test can overlap two.
    var holdRevokes = false
    private var held: [String: CheckedContinuation<Void, Never>] = [:]
    var heldIDs: [String] { Array(held.keys) }
    func release(_ id: String) { held.removeValue(forKey: id)?.resume() }

    func getConnections() async throws -> ConnectionsResponse {
        ConnectionsResponse(connections: rows)
    }

    func revokeConnection(_ connection: Connection) async throws -> ConnectionRevokeResponse {
        if holdRevokes {
            await withCheckedContinuation { held[connection.id] = $0 }
        }
        if let error = revokeErrors[connection.id] ?? revokeError { throw error }
        revoked.append(connection)
        return ConnectionRevokeResponse(success: true, kind: connection.kind, id: connection.id, revokedTokens: 1)
    }

    func createOAuthClient(preset: OAuthClientPreset, agent: String) async throws -> MintedOAuthClient {
        mints.append(OAuthClientPresetRequest(preset: preset, agent: agent))
        return MintedOAuthClient(clientId: "astrid_client_minted", clientSecret: "shh")
    }

    // MARK: Client editing (AITD-419)

    /// Clients the fake server holds, keyed by client id.
    var clients: [String: OAuthClientSummary] = [:]
    var createdClients: [CreateOAuthClientRequest] = []
    var updatedClients: [(clientId: String, body: UpdateOAuthClientRequest)] = []
    var getClientError: Error?
    var createClientError: Error?
    var updateClientError: Error?

    func getOAuthClient(clientId: String) async throws -> OAuthClientSummary {
        if let getClientError { throw getClientError }
        guard let client = clients[clientId] else { throw AstridAPIError.httpError(statusCode: 404, message: "{\"error\":\"Client not found\"}") }
        return client
    }

    func createOAuthClient(_ body: CreateOAuthClientRequest) async throws -> MintedOAuthClient {
        if let createClientError { throw createClientError }
        createdClients.append(body)
        return MintedOAuthClient(clientId: "astrid_client_new", clientSecret: "shh")
    }

    func updateOAuthClient(clientId: String, body: UpdateOAuthClientRequest) async throws -> OAuthClientSummary {
        if let updateClientError { throw updateClientError }
        updatedClients.append((clientId, body))
        let existing = clients[clientId]
        let updated = OAuthClientSummary(
            clientId: clientId, name: existing?.name ?? "", description: existing?.description,
            redirectUris: body.redirectUris, grantTypes: existing?.grantTypes ?? [],
            scopes: existing?.scopes ?? [], isActive: existing?.isActive ?? true
        )
        clients[clientId] = updated
        return updated
    }
}
