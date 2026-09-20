//  ConnectionsModel.swift
//  State and writes behind the Connections screen, shared by iOS and Mac.
//
//  Same shape as AgentHubModel: the view is thin, the rules live here where a test can pin them —
//  a revoke is optimistic and rolls back, the revoke path comes from the row, and a session-only
//  refusal from the server is surfaced as "open this on the web" rather than a bare error.

import Foundation
import Combine

// MARK: - Service boundary

protocol ConnectionsServicing: AnyObject {
    func getConnections() async throws -> ConnectionsResponse
    func revokeConnection(_ connection: Connection) async throws -> ConnectionRevokeResponse
    func createOAuthClient(preset: OAuthClientPreset, agent: String) async throws -> MintedOAuthClient
}

extension RemoteResourceService: ConnectionsServicing {}

// MARK: - The list

@MainActor
final class ConnectionsModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var requiresWebSession = false
    @Published var revokingID: String?

    private let service: ConnectionsServicing

    init(service: ConnectionsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    /// Rows grouped in display order, empty kinds omitted.
    var sections: [(kind: ConnectionKind, rows: [Connection])] {
        ConnectionKind.displayOrder.compactMap { kind in
            let rows = connections.filter { $0.kind == kind }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            connections = try await service.getConnections().connections
        } catch {
            errorMessage = AgentHubErrors.message(error)
        }
    }

    /// Optimistic: the row disappears at once and comes back, in place, if the server refuses.
    func revoke(_ connection: Connection) async {
        guard connection.revocable else { return }
        let previous = connections
        revokingID = connection.id
        errorMessage = nil
        requiresWebSession = false
        connections.removeAll { $0.id == connection.id && $0.kind == connection.kind }
        defer { revokingID = nil }
        do {
            _ = try await service.revokeConnection(connection)
        } catch {
            connections = previous
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }
}

// MARK: - Minting transport credentials

/// Client credentials for a transport the agents page configures (the webhook server today).
/// Shown once, like Custom Agent registration.
@MainActor
final class TransportCredentialsModel: ObservableObject {
    @Published var minted: MintedOAuthClient?
    @Published var isMinting = false
    @Published var errorMessage: String?
    @Published var requiresWebSession = false

    private let service: ConnectionsServicing

    init(service: ConnectionsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    func mint(preset: OAuthClientPreset, agent: String) async {
        isMinting = true
        errorMessage = nil
        requiresWebSession = false
        defer { isMinting = false }
        do {
            minted = try await service.createOAuthClient(preset: preset, agent: agent)
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }
}
