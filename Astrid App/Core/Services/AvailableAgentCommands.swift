import AstridCore
import Foundation

/// The astrid-core command behind the agents this account can assign, mention or chat with
/// (AITD-620, on the command AWTD-1610 added at core 084c2c0).
///
/// Answers `{ agents: [{ id, name, email, image, service }] }` — `AvailableAgentsResponse`.
enum AvailableAgentCommands {
    /// `serverRunOnly` narrows to what the server runs itself — what can power the default
    /// assistant. The unfiltered list is for assignee pickers and includes polling agents that
    /// cannot (AITD-297), so it is sent only when asked for.
    static func list(serverRunOnly: Bool = false) -> CoreCommand {
        var command = CoreCommand(kind: "availableAgents")
        if serverRunOnly { command.set("serverRunOnly", true) }
        return command
    }
}
