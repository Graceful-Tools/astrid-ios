import AstridCore
import Foundation

/// The astrid-core commands behind the Agent Hub's AI keys (AITD-620, on the commands AWTD-1610
/// added at core 084c2c0): which services have a key, and saving, testing and deleting one.
///
/// The paths and the wire names are the core's (`services/agents.rs`); this only spells the
/// commands, so `RemoteResourceService` stays a face and the spelling is testable without a server.
/// The key goes straight to the server and is never cached by the core.
enum AgentCredentialCommands {
    /// Answers `{ keys: { <serviceId>: { hasKey, keyPreview, isValid, lastTested, error } } }`;
    /// a service with no key is absent. Never the key itself.
    static func list() -> CoreCommand {
        CoreCommand(kind: "agentCredentials")
    }

    /// The core calls the key `key` and renames it to the wire's `apiKey` itself. Answers "done".
    static func save(serviceId: String, key: String) -> CoreCommand {
        var command = CoreCommand(kind: "saveAgentCredential")
        command.set("serviceId", serviceId)
        command.set("key", key)
        return command
    }

    /// Answers `{ works, error }`: `error` is the server's reason when the provider refused the key.
    static func test(serviceId: String) -> CoreCommand {
        var command = CoreCommand(kind: "testAgentCredential")
        command.set("serviceId", serviceId)
        return command
    }

    /// Answers "done".
    static func delete(serviceId: String) -> CoreCommand {
        var command = CoreCommand(kind: "deleteAgentCredential")
        command.set("serviceId", serviceId)
        return command
    }
}
