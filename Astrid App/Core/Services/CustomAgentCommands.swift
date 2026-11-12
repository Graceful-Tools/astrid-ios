import AstridCore
import Foundation

/// The astrid-core commands behind the agents page's Custom Agents section (AITD-620): the agents
/// an account registered of its own, registering one (whose OAuth secret is shown once), deleting
/// one, and setting its photo.
///
/// The paths and the wire names are the core's (`services/agents.rs`); this only spells the
/// commands, so `RemoteResourceService` stays a face and the spelling is testable without a server.
enum CustomAgentCommands {
    /// The core unwraps the server's `{ agents: [...] }` and answers with the array.
    static func list() -> CoreCommand {
        CoreCommand(kind: "customAgents")
    }

    /// The core calls the name `name` and renames it to the wire's `agentName` itself. No lists
    /// leaves `listIds` absent, so the server's own default applies.
    static func register(name: String, listIds: [String]?) -> CoreCommand {
        var command = CoreCommand(kind: "registerCustomAgent")
        command.set("name", name)
        command.set("listIds", listIds)
        return command
    }

    static func delete(id: String) -> CoreCommand {
        var command = CoreCommand(kind: "deleteCustomAgent")
        command.set("agentId", id)
        return command
    }

    /// A URL, not an upload: the photo is uploaded first and lives wherever that put it. The core
    /// answers with the image the server settled on.
    static func setPhoto(id: String, image: String?) -> CoreCommand {
        var command = CoreCommand(kind: "setCustomAgentPhoto")
        command.set("agentId", id)
        command.set("image", image)
        return command
    }
}
