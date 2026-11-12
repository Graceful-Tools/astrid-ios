import AstridCore
import Foundation

/// The astrid-core commands behind share links (AITD-620): minting a link to a task or a list,
/// and resolving `astrid.cc/s/<code>` back to what it opens.
///
/// All three are online-only in the core (`services/share.rs`): the server owns the codes. This
/// only spells the commands, so `RemoteResourceService` stays a face and the spelling is
/// testable without a server.
enum ShortcodeCommands {
    /// The server mints links for tasks and lists only.
    struct UnknownTarget: LocalizedError {
        let targetType: String
        var errorDescription: String? { "A share link can't be made for a \(targetType)." }
    }

    /// The core answers `{ url }` (`ShortcodeResponse`).
    static func link(targetType: String, targetId: String) throws -> CoreCommand {
        switch targetType {
        case "task":
            var command = CoreCommand(kind: "shareTask")
            command.set("taskId", targetId)
            return command
        case "list":
            var command = CoreCommand(kind: "shareList")
            command.set("listId", targetId)
            return command
        default:
            throw UnknownTarget(targetType: targetType)
        }
    }

    /// The core answers `{ targetType, targetId }` (`ShortcodeResolution`).
    static func resolve(code: String) -> CoreCommand {
        var command = CoreCommand(kind: "resolveShortcode")
        command.set("code", code)
        return command
    }
}

/// A freshly minted share link.
nonisolated struct ShortcodeResponse: Decodable {
    let url: String
}

/// What a share link opens: a `task` or a `list`, by id.
nonisolated struct ShortcodeResolution: Decodable {
    let targetType: String
    let targetId: String
}

/// The astrid-core command behind List Insights (AITD-545, moved in AITD-620). Online-only: the
/// server computes the numbers over its own history. The core answers the route's `insights`
/// object unwrapped, and reads a window it does not offer as 30 rather than sending a 400.
enum ListInsightsCommands {
    static func insights(listId: String, days: Int, timeZone: String) -> CoreCommand {
        var command = CoreCommand(kind: "listInsights")
        command.set("listId", listId)
        command.set("days", days)
        command.set("timeZone", timeZone)
        return command
    }
}
