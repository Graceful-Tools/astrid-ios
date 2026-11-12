import AstridCore
import Foundation

/// The astrid-core commands behind the Agent Hub's writes (AITD-620): connecting and
/// disconnecting Copilot, and changing how one agent runs.
///
/// The paths and the wire names are the core's (`services/agents.rs`); this only spells the
/// commands, so `RemoteResourceService` stays a face and the spelling is testable without a server.
/// The two reads — the modes and the Copilot status — have no standalone core command (only
/// inside the whole `agents` hub answer), so they stay on the client until the hub moves.
enum CopilotCommands {
    /// Answers `{ authorizeUrl }`: the GitHub page to open in a browser. Empty when the server
    /// named none.
    static func connect() -> CoreCommand {
        CoreCommand(kind: "connectCopilot")
    }

    /// Answers only "done".
    static func disconnect() -> CoreCommand {
        CoreCommand(kind: "disconnectCopilot")
    }

    /// The mode mailbox and the mode, lowercase as the server spells it. Answers the server's
    /// `{ agents, modes, meta }` unchanged.
    static func setMode(_ request: UpdateAgentModeRequest) -> CoreCommand {
        var command = CoreCommand(kind: "setAgentMode")
        command.set("agent", request.agent)
        command.set("mode", request.mode.rawValue)
        return command
    }
}
