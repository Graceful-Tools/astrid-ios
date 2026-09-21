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

    /// Both halves of the revoke path from the row itself, so a caller cannot pair the wrong two.
    /// Lives here, not on the DTO: APIEndpointInventoryTests only scans the client files, and a
    /// path built elsewhere is a path docs/API_ENDPOINTS.md never hears about.
    static func revokeConnectionPath(_ connection: Connection) -> String {
        "/api/v1/users/me/connections/\(connection.kind.rawValue)/\(connection.id)"
    }

    /// Revoke one connection. The path pairs the row's own kind and id; session-only server-side.
    func revokeConnection(_ connection: Connection) async throws -> ConnectionRevokeResponse {
        try await request(method: "DELETE", path: Self.revokeConnectionPath(connection))
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

    // MARK: - The developer console's half, on the phone (AITD-419)

    /// Where one client lives. Built here, not at the call site, for the same reason as
    /// `revokeConnectionPath`: `APIEndpointInventoryTests` only scans the client files, and a path
    /// assembled elsewhere is a path `docs/API_ENDPOINTS.md` never hears about.
    static func oauthClientPath(_ clientId: String) -> String {
        "/api/v1/oauth/clients/\(clientId)"
    }

    /// One client with the fields an editor needs — the connections list carries the client id
    /// but not its redirect URIs, so an edit has to ask.
    func getOAuthClient(clientId: String) async throws -> OAuthClientSummary {
        let response: OAuthClientResponse = try await request(
            method: "GET", path: Self.oauthClientPath(clientId)
        )
        return response.client
    }

    /// Register a client the user configured themselves. The secret comes back once and is never
    /// retrievable again, which is why the caller shows it rather than storing it.
    ///
    /// Session-only server-side: registration from a delegated OAuth token would let a leaked
    /// narrow-scope token mint itself a wider one. iOS sends the account's session cookie, so this
    /// works from the app — a build that ever stops doing so gets `requiresWebSession` handling
    /// rather than a bare 403.
    func createOAuthClient(_ body: CreateOAuthClientRequest) async throws -> MintedOAuthClient {
        let response: MintedOAuthClientResponse = try await request(
            method: "POST", path: "/api/v1/oauth/clients", body: body
        )
        return response.client
    }

    /// Change an existing client's redirect URIs.
    func updateOAuthClient(clientId: String, body: UpdateOAuthClientRequest) async throws -> OAuthClientSummary {
        let response: OAuthClientResponse = try await request(
            method: "PUT", path: Self.oauthClientPath(clientId), body: body
        )
        return response.client
    }
}
