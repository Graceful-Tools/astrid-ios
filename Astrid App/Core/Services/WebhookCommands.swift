import AstridCore
import Foundation

/// The astrid-core commands behind the agents page's webhook transport (AITD-620): where an
/// account's own agent is told about work, and the test-fire that proves the URL is reachable.
///
/// The path and the wire names are the core's (`services/agents.rs`); this only spells the
/// commands, so `RemoteResourceService` stays a face and the spelling is testable without a server.
enum WebhookCommands {
    static func settings() -> CoreCommand {
        CoreCommand(kind: "webhookSettings")
    }

    /// The editor's five fields. The core calls the URL `url` and renames it to the wire's
    /// `webhookUrl` itself.
    static func save(_ request: UpdateWebhookSettingsRequest) -> CoreCommand {
        var command = CoreCommand(kind: "saveWebhook")
        command.set("url", request.webhookUrl)
        command.set("enabled", request.enabled)
        command.set("regenerateSecret", request.regenerateSecret)
        command.set("events", request.events)
        command.set("agents", request.agents)
        return command
    }

    static func delete() -> CoreCommand {
        CoreCommand(kind: "deleteWebhook")
    }

    static func test() -> CoreCommand {
        CoreCommand(kind: "testWebhook")
    }
}
