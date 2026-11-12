import AstridCore
import Foundation

/// The astrid-core commands behind the Connections screen and the agents page's transport
/// credentials (AITD-620) — everything that can act as the account, and the OAuth clients a person
/// makes by hand.
///
/// The paths, the revoke-kind check and the draft rules are the core's (`app/dispatch/connections.rs`);
/// this only spells the commands, so `RemoteResourceService` stays a face and the spelling is testable
/// without a server.
enum ConnectionCommands {
    static func list() -> CoreCommand {
        CoreCommand(kind: "connections")
    }

    /// The row's kind and id together, since ids repeat across kinds. A kind this build cannot name
    /// is refused by the core rather than sent.
    static func revoke(_ connection: Connection) -> CoreCommand {
        CoreCommand(kind: "revokeConnection", [
            "connectionKind": .value(connection.kind.rawValue),
            "id": .value(connection.id),
        ])
    }

    /// Client credentials for a transport the agents page configures; the server picks the scopes.
    static func mint(preset: OAuthClientPreset, agent: String) -> CoreCommand {
        CoreCommand(kind: "mintTransportCredentials", [
            "preset": .value(preset.rawValue),
            "agent": .value(agent),
        ])
    }

    static func load(clientId: String) -> CoreCommand {
        CoreCommand(kind: "loadOAuthClient", ["clientId": .value(clientId)])
    }

    /// A client the person shaped. The core judges the draft again and refuses one with a problem
    /// before anything is sent.
    static func create(_ request: CreateOAuthClientRequest) -> CoreCommand {
        var command = CoreCommand(kind: "createOAuthClient")
        addDraft(to: &command, name: request.name, description: request.description ?? "",
                 scopes: request.scopes, grantTypes: request.grantTypes,
                 redirectURIs: request.redirectUris ?? [])
        return command
    }

    /// An edit writes the redirect URIs, but carries the whole draft: the core applies the create
    /// rules to an edit too, so a body of URIs alone would read as a client with no name or grant.
    static func update(clientId: String, draft: OAuthClientDraft) -> CoreCommand {
        var command = CoreCommand(kind: "updateOAuthClient", ["clientId": .value(clientId)])
        addDraft(to: &command, name: draft.trimmedName, description: draft.descriptionText,
                 scopes: draft.scopes.sorted(), grantTypes: draft.wireGrantTypes,
                 redirectURIs: draft.redirectURIs)
        return command
    }

    private static func addDraft(to command: inout CoreCommand, name: String, description: String,
                                 scopes: [String], grantTypes: [String], redirectURIs: [String]) {
        command.set("name", name)
        command.set("description", description)
        command.set("scopes", scopes)
        command.set("grantTypes", grantTypes)
        // One URI per line, the shape the core's draft holds.
        command.set("redirectUriText", redirectURIs.joined(separator: "\n"))
    }
}
