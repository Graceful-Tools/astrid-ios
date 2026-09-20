//  ConnectionsDTOs.swift
//  GET/DELETE /api/v1/users/me/connections — everything that can act as the account.
//
//  Mirrors astrid-web lib/api-contracts/v1-ios-shapes.ts (V1Connection). Decoded leniently on
//  purpose: a `kind` this build has never heard of is a row it cannot revoke, not a decode
//  failure that blanks the whole list — the server may add a sixth source before the App Store
//  ships the build that knows it.

import Foundation

/// The five credential sources the server lists, plus the one this build does not know yet.
enum ConnectionKind: String, Codable, CaseIterable {
    /// An OAuth client the user created (the developer console, or a transport preset).
    case oauthClient
    /// A dynamically registered client approved on the consent page (Claude Code, VS Code…).
    case authorizedApp
    /// A Custom Agent the user registered; its client belongs to the agent's bot user.
    case customAgent
    /// A user-level access token, e.g. the GitHub.com Copilot cloud agent's.
    case accessToken
    /// The user's webhook server.
    case webhook
    /// A kind added server-side after this build shipped.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConnectionKind(rawValue: raw) ?? .unknown
    }

    var localizedLabel: String {
        NSLocalizedString("settings.connections.kind.\(rawValue)", comment: "")
    }

    /// Display order: the things a reader made or approved first, the plumbing last.
    static let displayOrder: [ConnectionKind] = [.authorizedApp, .oauthClient, .customAgent, .accessToken, .webhook, .unknown]
}

enum ConnectionStatus: String, Codable {
    case active, expired, disabled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConnectionStatus(rawValue: raw) ?? .unknown
    }

    var localizedLabel: String {
        NSLocalizedString("settings.connections.status.\(rawValue)", comment: "")
    }
}

struct ConnectionDetail: Codable, Equatable {
    var clientId: String?
    var grantTypes: [String]?
    var activeTokens: Int?
    var permissions: [String]?
    var agentId: String?
    var webhookUrl: String?
    var description: String?
}

struct Connection: Codable, Equatable, Identifiable {
    let id: String
    let kind: ConnectionKind
    let name: String
    /// The email this credential authors as; nil means the user themself.
    let actsAs: String?
    let scopes: [String]
    let createdAt: String
    let lastUsedAt: String?
    let expiresAt: String?
    let status: ConnectionStatus
    let revocable: Bool
    /// Which settings page owns further management: "agents" or "connections".
    let manageIn: String?
    let detail: ConnectionDetail?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(ConnectionKind.self, forKey: .kind) ?? .unknown
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        actsAs = try c.decodeIfPresent(String.self, forKey: .actsAs)
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        status = try c.decodeIfPresent(ConnectionStatus.self, forKey: .status) ?? .unknown
        // An unknown kind cannot be revoked from here whatever the server says: the path
        // segment would be one this build cannot name.
        let serverRevocable = try c.decodeIfPresent(Bool.self, forKey: .revocable) ?? false
        revocable = serverRevocable && kind != .unknown
        manageIn = try c.decodeIfPresent(String.self, forKey: .manageIn)
        detail = try c.decodeIfPresent(ConnectionDetail.self, forKey: .detail)
    }

    init(id: String, kind: ConnectionKind, name: String, actsAs: String? = nil, scopes: [String] = [],
         createdAt: String = "", lastUsedAt: String? = nil, expiresAt: String? = nil,
         status: ConnectionStatus = .active, revocable: Bool = true, manageIn: String? = nil,
         detail: ConnectionDetail? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.actsAs = actsAs; self.scopes = scopes
        self.createdAt = createdAt; self.lastUsedAt = lastUsedAt; self.expiresAt = expiresAt
        self.status = status; self.revocable = revocable && kind != .unknown; self.manageIn = manageIn
        self.detail = detail
    }

    /// Both halves of the revoke path, so a caller cannot pair the wrong two.
    var revokePath: String { "/api/v1/users/me/connections/\(kind.rawValue)/\(id)" }

    var managedOnAgentsPage: Bool { manageIn == "agents" }
}

struct ConnectionsResponse: Codable {
    let connections: [Connection]
}

struct ConnectionRevokeResponse: Codable {
    let success: Bool
    let kind: ConnectionKind?
    let id: String?
    let revokedTokens: Int?
}

// MARK: - Transport credential presets (POST /api/v1/oauth/clients { preset, agent })

/// The client shapes the agents page mints for its own transports — see astrid-web
/// lib/oauth/oauth-client-presets.ts. The server decides scopes and grant types from the preset.
enum OAuthClientPreset: String, Codable {
    case githubActions
    case webhookServer
}

struct OAuthClientPresetRequest: Codable, Equatable {
    let preset: OAuthClientPreset
    let agent: String
}

struct MintedOAuthClient: Codable, Equatable {
    let clientId: String
    let clientSecret: String
}

struct MintedOAuthClientResponse: Codable {
    let client: MintedOAuthClient
}
