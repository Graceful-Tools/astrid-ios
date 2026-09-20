//  AstridAPIClient+Connections.swift
//  GET/DELETE /api/v1/users/me/connections and the transport-credential preset on
//  POST /api/v1/oauth/clients — everything that can act as the account, and the one way the
//  agents page mints a client pair for a transport it configures.
//
//  An extension rather than more lines in AstridAPIClient.swift: the client sits on the source
//  file size ceiling (SourceFileSizeGuardTests), and the precedent from AITD-388 is to move a
//  cohesive group of endpoints out, not to raise the number. APIEndpointInventoryTests scans
//  this file too, so docs/API_ENDPOINTS.md stays honest about the paths it adds.

import Foundation

extension AstridAPIClient {
    func getConnections() async throws -> ConnectionsResponse {
        try await request(method: "GET", path: "/api/v1/users/me/connections")
    }

    /// Revoke one connection. The path pairs the row's own kind and id; session-only server-side.
    func revokeConnection(_ connection: Connection) async throws -> ConnectionRevokeResponse {
        try await request(method: "DELETE", path: connection.revokePath)
    }

    /// Mint client credentials for a transport from its preset — the server picks the scopes.
    func createOAuthClient(preset: OAuthClientPreset, agent: String) async throws -> MintedOAuthClient {
        let response: MintedOAuthClientResponse = try await request(
            method: "POST",
            path: "/api/v1/oauth/clients",
            body: OAuthClientPresetRequest(preset: preset, agent: agent)
        )
        return response.client
    }

}
