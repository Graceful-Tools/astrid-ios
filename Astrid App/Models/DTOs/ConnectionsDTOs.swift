//  ConnectionsDTOs.swift
//  GET/DELETE /api/v1/users/me/connections — everything that can act as the account.
//
//  Mirrors astrid-web lib/api-contracts/v1-ios-shapes.ts (V1Connection). Decoded leniently on
//  purpose: a `kind` this build has never heard of is a row it cannot revoke, not a decode
//  failure that blanks the whole list — the server may add a sixth source before the App Store
//  ships the build that knows it.
//
//  A row also carries two facets (AWTD-981 / AITD-420): `category` — what it actually IS, and
//  what the screen groups by — and `owner`, whose app it is. `kind` is untouched by that: it is
//  the path segment of DELETE .../connections/{kind}/{id}, so the facets group and the kind
//  revokes. A client that adopted the facets and dropped the kind would group beautifully and
//  revoke nothing.

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

/// What a row IS, once `oauthClient`, `authorizedApp` and `customAgent` are seen for what they
/// are: one `OAuthClient` row holding one credential, read by three queries that differ only in
/// what `userId` equals. That is an owner, not a type — so there are three categories, not five.
///
/// Mirrors astrid-web lib/connections/connection-taxonomy.ts, where the mapping from kind is
/// total and lives in one place.
enum ConnectionCategory: String, Codable, CaseIterable {
    /// A client id + secret, whoever owns it.
    case app
    /// A bearer string, pasted.
    case token
    /// The server Astrid calls OUT to, rather than one calling in.
    case webhook
    /// A category added server-side after this build shipped.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConnectionCategory(rawValue: raw) ?? .unknown
    }

    var localizedLabel: String {
        NSLocalizedString("settings.connections.category.\(rawValue)", comment: "")
    }

    /// What acts as you, then how, then what points out. The unknown trails, as with kinds.
    static let displayOrder: [ConnectionCategory] = [.app, .token, .webhook, .unknown]
}

/// For an app, whose it is. Absent for a token or a webhook, which have no owner to draw.
///
/// Unlike `ConnectionKind` and `ConnectionCategory` there is no `unknown` case: an owner this
/// build cannot name is a badge it cannot write, and no badge is the honest answer. So the
/// decode maps an unrecognised string to nil rather than to a case.
enum ConnectionOwner: String, Codable, CaseIterable {
    /// Made in the developer console.
    case you
    /// Approved on the consent page.
    case thirdParty
    /// Belongs to a Custom Agent the user registered.
    case agent

    var localizedLabel: String {
        NSLocalizedString("settings.connections.owner.\(rawValue)", comment: "")
    }
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
    /// Which of the three real types this is, and what the screen groups by. `nil` means the
    /// server predates AWTD-981 — not that the row is uncategorised.
    let category: ConnectionCategory?
    /// Whose app it is; `nil` for a token, a webhook, or an owner this build cannot name.
    let owner: ConnectionOwner?
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
        // Absent stays absent: it is how this build tells an old deployment from a new one.
        category = try c.decodeIfPresent(ConnectionCategory.self, forKey: .category)
        owner = ConnectionOwner(rawValue: try c.decodeIfPresent(String.self, forKey: .owner) ?? "")
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

    init(id: String, kind: ConnectionKind, category: ConnectionCategory? = nil,
         owner: ConnectionOwner? = nil, name: String, actsAs: String? = nil, scopes: [String] = [],
         createdAt: String = "", lastUsedAt: String? = nil, expiresAt: String? = nil,
         status: ConnectionStatus = .active, revocable: Bool = true, manageIn: String? = nil,
         detail: ConnectionDetail? = nil) {
        self.id = id; self.kind = kind; self.category = category; self.owner = owner
        self.name = name; self.actsAs = actsAs; self.scopes = scopes
        self.createdAt = createdAt; self.lastUsedAt = lastUsedAt; self.expiresAt = expiresAt
        self.status = status; self.revocable = revocable && kind != .unknown; self.manageIn = manageIn
        self.detail = detail
    }

    var managedOnAgentsPage: Bool { manageIn == "agents" }

    /// The badge an app row wears in place of the kind label — "Yours", "Third-party", "Agent".
    /// `nil` where there is no owner distinction to draw, which is every token and webhook.
    var ownerLabel: String? { owner?.localizedLabel }
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

// MARK: - OAuth clients (GET/POST /api/v1/oauth/clients, GET/PUT /api/v1/oauth/clients/{id})

/// One OAuth client as the server describes it — the fields an editor needs, which is more than
/// the connections list carries (a `Connection` knows the client id but not its redirect URIs).
///
/// Decoded leniently for the same reason as `Connection`: this build must survive a server that
/// has learned a new field, and an absent field is a default, not a decode failure.
struct OAuthClientSummary: Codable, Equatable, Identifiable {
    let clientId: String
    let name: String
    let description: String?
    let redirectUris: [String]
    let grantTypes: [String]
    let scopes: [String]
    let isActive: Bool

    var id: String { clientId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try c.decode(String.self, forKey: .clientId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        redirectUris = try c.decodeIfPresent([String].self, forKey: .redirectUris) ?? []
        grantTypes = try c.decodeIfPresent([String].self, forKey: .grantTypes) ?? []
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        // Absent reads as active: the screen only ever asks for a client it just saw listed.
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    init(clientId: String, name: String, description: String? = nil, redirectUris: [String] = [],
         grantTypes: [String] = [], scopes: [String] = [], isActive: Bool = true) {
        self.clientId = clientId; self.name = name; self.description = description
        self.redirectUris = redirectUris; self.grantTypes = grantTypes; self.scopes = scopes
        self.isActive = isActive
    }
}

struct OAuthClientResponse: Codable {
    let client: OAuthClientSummary
}

/// The developer-console shape of a create: the caller chose everything, as opposed to
/// `OAuthClientPresetRequest` where the preset did.
struct CreateOAuthClientRequest: Codable, Equatable {
    let name: String
    let description: String?
    let scopes: [String]
    let grantTypes: [String]
    let redirectUris: [String]?
}

/// What an edit writes. Only the redirect URIs, matching astrid-web's edit dialog — the PUT
/// accepts name, description, scopes and isActive too, and the two consoles deliberately offer
/// the same narrow thing rather than each inventing its own idea of an edit.
struct UpdateOAuthClientRequest: Codable, Equatable {
    let redirectUris: [String]
}
