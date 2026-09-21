//  OAuthClientDraft.swift
//  The rules behind "new connection" / "edit connection" on the Connections screen (AITD-419).
//
//  The validation lives here rather than in the editor view for the usual reason — a rule inside
//  a `body` cannot be tested and cannot be compared against the other platform. Every rule in
//  this file has a twin in astrid-web `components/oauth-app-manager.tsx` (`handleCreate` and
//  `toggleGrantType`); when one moves the other is wrong, and `OAuthClientEditorTests` is where
//  that shows up.
//
//  What is deliberately NOT here: deciding which scopes are acceptable. The server owns that
//  (`validateRegisterableScopes`), and a phone build that shipped before a scope existed must not
//  be the thing that decides the scope is invalid.

import Foundation

// MARK: - Grant types

/// The grant types a client can be registered with — astrid-web `types/oauth.ts` `GrantType`.
enum OAuthGrantType: String, CaseIterable, Codable {
    case clientCredentials = "client_credentials"
    case authorizationCode = "authorization_code"
    case refreshToken = "refresh_token"

    /// Display and wire order. `allCases` already gives this, but the wire body depends on the
    /// order being stable, so it is named rather than inherited by luck.
    static let displayOrder: [OAuthGrantType] = [.clientCredentials, .authorizationCode, .refreshToken]

    var localizedLabel: String {
        NSLocalizedString("settings.connections.grant.\(rawValue)", comment: "")
    }

    var localizedHint: String {
        NSLocalizedString("settings.connections.grant.\(rawValue)_hint", comment: "")
    }
}

// MARK: - Scopes

/// The scopes the picker offers, mirroring astrid-web `lib/oauth/oauth-scopes.ts` `OAUTH_SCOPES`
/// minus the wildcard.
///
/// A mirrored list goes stale, and the failure mode is worth stating: a scope added server-side
/// after this build shipped is one the phone cannot tick — not one it breaks on. That is the same
/// trade `ConnectionKind` makes for an unknown kind, and the reason the server, not this list,
/// is what validates a create.
enum OAuthScopeCatalog {
    /// `*` is absent on purpose: it grants the whole account and `isRegisterableScope` refuses it
    /// from any request body, so offering it would be a toggle that always fails.
    static let registerable: [String] = [
        "tasks:read", "tasks:write", "tasks:delete",
        "lists:read", "lists:write", "lists:delete", "lists:manage_members",
        "projects:read", "projects:write", "projects:delete",
        "comments:read", "comments:write", "comments:delete",
        "chat:read", "chat:write",
        "user:read", "user:write",
        "attachments:read", "attachments:write", "attachments:delete",
        "contacts:read", "contacts:write",
        "public:read", "public:write",
        "sse:connect",
    ]
}

// MARK: - The draft

/// What the editor holds while a person is typing, and the one place that says whether it can be
/// sent yet.
struct OAuthClientDraft: Equatable {
    var name: String = ""
    var descriptionText: String = ""
    var scopes: Set<String> = []
    var grantTypes: Set<OAuthGrantType> = [.clientCredentials]
    /// One URI per line — the same shape as the web dialog's textarea.
    var redirectURIText: String = ""

    /// Grant types the server has and this build does not. Kept so an edit sends them back
    /// rather than silently narrowing a client that was minted with a newer grant.
    private(set) var unrecognizedGrantTypes: [String] = []

    init() {}

    /// A draft filled from a client being edited.
    init(_ client: OAuthClientSummary) {
        name = client.name
        descriptionText = client.description ?? ""
        scopes = Set(client.scopes)
        grantTypes = Set(client.grantTypes.compactMap(OAuthGrantType.init(rawValue:)))
        unrecognizedGrantTypes = client.grantTypes.filter { OAuthGrantType(rawValue: $0) == nil }
        redirectURIText = client.redirectUris.joined(separator: "\n")
    }

    // MARK: Derived

    /// The lines that are actually URIs. Blank lines and stray indentation are what typing looks
    /// like, not mistakes to report.
    var redirectURIs: [String] {
        redirectURIText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Validation

    /// Why this draft cannot be sent yet, or nil.
    enum Problem: Equatable {
        case nameMissing
        case noGrantType
        case redirectURIRequired
        case invalidRedirectURI(String)

        var localizedMessage: String {
            switch self {
            case .nameMissing:
                return NSLocalizedString("settings.connections.error.name_required", comment: "")
            case .noGrantType:
                return NSLocalizedString("settings.connections.error.grant_required", comment: "")
            case .redirectURIRequired:
                return NSLocalizedString("settings.connections.error.redirect_required", comment: "")
            case .invalidRedirectURI(let uri):
                return String(format: NSLocalizedString("settings.connections.error.redirect_invalid", comment: ""), uri)
            }
        }
    }

    /// The FIRST thing to fix, in the order the fields appear — a list of every problem at once
    /// is a wall to read, and fixing the top one usually reveals whether the rest were real.
    var problem: Problem? {
        if trimmedName.isEmpty { return .nameMissing }
        if grantTypes.isEmpty { return .noGrantType }
        let uris = redirectURIs
        if grantTypes.contains(.authorizationCode) && uris.isEmpty { return .redirectURIRequired }
        if let bad = uris.first(where: { !Self.isAllowedRedirectURI($0) }) { return .invalidRedirectURI(bad) }
        return nil
    }

    var isValid: Bool { problem == nil }

    /// http and https only, and absolute — the same test the web dialog makes with `new URL()`.
    /// A custom scheme is refused here rather than at the server, so the reason arrives next to
    /// the field that caused it.
    static func isAllowedRedirectURI(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    // MARK: Grant-type pairing

    /// Toggling one grant, with the pairing astrid-web's `toggleGrantType` applies.
    ///
    /// `refresh_token` is not a way to get a token — it is how the authorization-code flow keeps
    /// one alive, so the two travel together in both directions. And the last grant cannot be
    /// turned off: a client with none can never authenticate at all.
    static func toggling(_ grant: OAuthGrantType, in current: Set<OAuthGrantType>) -> Set<OAuthGrantType> {
        var next = current
        if current.contains(grant) {
            next.remove(grant)
            if grant == .authorizationCode { next.remove(.refreshToken) }
            return next.isEmpty ? current : next
        }
        next.insert(grant)
        if grant == .authorizationCode { next.insert(.refreshToken) }
        if grant == .refreshToken { next.insert(.authorizationCode) }
        return next
    }

    /// Stable wire order: the grants this build knows in display order, then anything the server
    /// had that it did not.
    var wireGrantTypes: [String] {
        OAuthGrantType.displayOrder.filter(grantTypes.contains).map(\.rawValue) + unrecognizedGrantTypes
    }

    // MARK: Wire bodies

    func createRequest() -> CreateOAuthClientRequest {
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let uris = redirectURIs
        return CreateOAuthClientRequest(
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            scopes: Array(scopes),
            grantTypes: wireGrantTypes,
            // Absent rather than `[]`: the server reads an empty array as "no callbacks", which
            // is the same thing here but says something different in the log.
            redirectUris: uris.isEmpty ? nil : uris
        )
    }

    /// An edit writes the redirect URIs, which is what the web dialog changes too — name and
    /// description are shown but not editable, so the two consoles agree on what an edit means.
    func updateRequest() -> UpdateOAuthClientRequest {
        UpdateOAuthClientRequest(redirectUris: redirectURIs)
    }
}
