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
    func getOAuthClient(clientId: String) async throws -> OAuthClientSummary
    func createOAuthClient(_ body: CreateOAuthClientRequest) async throws -> MintedOAuthClient
    func updateOAuthClient(clientId: String, body: UpdateOAuthClientRequest) async throws -> OAuthClientSummary
}

extension RemoteResourceService: ConnectionsServicing {}

// MARK: - One heading, and the rows under it

/// A section of the Connections screen — two flavours, because the server has two vintages.
///
/// A deployment carrying AWTD-981 stamps every row with a `category`, and the screen draws the
/// three sections that are actually types (AITD-420). An older one sends none, and the screen
/// falls back to the per-kind sections it always drew: the facets are additive, so a build in
/// the wild has to keep working against both.
struct ConnectionSection: Identifiable, Equatable {
    enum Heading: Equatable {
        case category(ConnectionCategory)
        case kind(ConnectionKind)
    }

    let heading: Heading
    let rows: [Connection]

    var id: String {
        switch heading {
        case .category(let category): return "category:\(category.rawValue)"
        case .kind(let kind): return "kind:\(kind.rawValue)"
        }
    }

    var localizedTitle: String {
        switch heading {
        case .category(let category): return category.localizedLabel
        case .kind(let kind): return kind.localizedLabel
        }
    }

    /// Owner badges belong to the category grouping only. Under a kind heading the row's owner
    /// is already what the heading says, and the badge would say it twice.
    var showsOwnerBadges: Bool {
        if case .category = heading { return true }
        return false
    }
}

// MARK: - The list

@MainActor
final class ConnectionsModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var requiresWebSession = false
    @Published var revokingIDs: Set<String> = []

    private let service: ConnectionsServicing

    init(service: ConnectionsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    /// Rows grouped in display order, empty groups omitted.
    ///
    /// By category when the server stamped every row with one, which collapses the three
    /// `OAuthClient`-backed kinds into a single Apps section (AITD-420). By kind when any row
    /// lacks one: `category` is emitted by every build carrying AWTD-981, so a gap means this
    /// app is talking to a deployment that predates it — all-or-nothing per response, not a
    /// row-by-row decision, or one old row would strand the rest under a heading of its own.
    var sections: [ConnectionSection] {
        guard connections.allSatisfy({ $0.category != nil }) else {
            return ConnectionKind.displayOrder.compactMap { kind in
                let rows = connections.filter { $0.kind == kind }
                return rows.isEmpty ? nil : ConnectionSection(heading: .kind(kind), rows: rows)
            }
        }
        return ConnectionCategory.displayOrder.compactMap { category in
            let rows = connections.filter { $0.category == category }
            return rows.isEmpty ? nil : ConnectionSection(heading: .category(category), rows: rows)
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
    ///
    /// Only *this* row comes back. Revokes can overlap — every other row's button stays live
    /// while one is in flight — and a refresh can land mid-request, so restoring a snapshot of
    /// the whole list would resurrect a row another revoke had just removed for good.
    func revoke(_ connection: Connection) async {
        guard connection.revocable else { return }
        let isSameRow: (Connection) -> Bool = { $0.id == connection.id && $0.kind == connection.kind }
        let predecessors = connections.prefix { !isSameRow($0) }
        revokingIDs.insert(connection.id)
        errorMessage = nil
        requiresWebSession = false
        connections.removeAll(where: isSameRow)
        defer { revokingIDs.remove(connection.id) }
        do {
            _ = try await service.revokeConnection(connection)
        } catch {
            if !connections.contains(where: isSameRow) {
                // Right after the nearest row that preceded it and is still here; the front if none is.
                let after = connections.lastIndex { row in
                    predecessors.contains { $0.id == row.id && $0.kind == row.kind }
                }
                connections.insert(connection, at: after.map { $0 + 1 } ?? 0)
            }
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

// MARK: - Making and changing a client (AITD-419)

/// The state behind the new/edit sheet. The view is thin, as with `ConnectionsModel`: what can be
/// sent is `OAuthClientDraft`'s answer, and everything here is about the round trip.
@MainActor
final class OAuthClientEditorModel: ObservableObject {
    /// Making one, or changing one that exists. An edit names the client because the redirect
    /// URIs it starts from have to be fetched — the connections list does not carry them.
    enum Mode: Equatable, Identifiable {
        case create
        case edit(clientId: String)

        /// What `sheet(item:)` keys on — distinct per client, so tapping Edit on a second row
        /// while the first sheet is closing opens the second client and not the first again.
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let clientId): return "edit:\(clientId)"
            }
        }
    }

    @Published var draft = OAuthClientDraft()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var requiresWebSession = false
    /// Set once, on a successful create: the secret the server will never show again.
    @Published var minted: MintedOAuthClient?

    let mode: Mode
    private let service: ConnectionsServicing

    init(mode: Mode, service: ConnectionsServicing = RemoteResourceService.shared) {
        self.mode = mode
        self.service = service
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// Fill the draft from the server. Create mode has nothing to fetch.
    func load() async {
        guard case .edit(let clientId) = mode else { return }
        isLoading = true
        errorMessage = nil
        requiresWebSession = false
        defer { isLoading = false }
        do {
            draft = OAuthClientDraft(try await service.getOAuthClient(clientId: clientId))
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }

    /// Returns true when the sheet should close. A validation problem is reported in the same
    /// place a server error is, so a person is not hunting two kinds of message.
    func save() async -> Bool {
        if let problem = draft.problem {
            errorMessage = problem.localizedMessage
            return false
        }
        isSaving = true
        errorMessage = nil
        requiresWebSession = false
        defer { isSaving = false }
        do {
            switch mode {
            case .create:
                // Held, not dismissed: the secret is shown once and closing on top of it would
                // lose the only copy that will ever exist.
                minted = try await service.createOAuthClient(draft.createRequest())
                return false
            case .edit(let clientId):
                _ = try await service.updateOAuthClient(clientId: clientId, body: draft.updateRequest())
                return true
            }
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
            return false
        }
    }
}
