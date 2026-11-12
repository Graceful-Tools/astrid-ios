import AstridCore
import Foundation

/// The astrid-core commands behind contacts sync and the people search (AITD-620): the synced
/// count on the settings row, uploading the address book, the search the assignee, mention
/// and member pickers run, and contact autocomplete and recommended collaborators when adding a
/// member.
///
/// The paths, the batching and the wire names are the core's (`services/account.rs`); this only
/// spells the commands, so the services stay faces and the spelling is testable without a server.
enum ContactCommands {
    /// Answers `{ contacts, total }`; `total` is the account's whole count.
    static func status() -> CoreCommand {
        CoreCommand(kind: "contacts")
    }

    /// The whole address book. The core sends it 500 at a time, the first request replacing what
    /// the server had, and still sends one replacing request for an empty book. Answers the last
    /// batch's stats.
    static func upload(_ contacts: [DeviceContact]) -> CoreCommand {
        var command = CoreCommand(kind: "uploadContacts")
        command.set("contacts", contacts)
        return command
    }

    /// People to assign, mention or invite, with the assignable AI agents included as the pickers
    /// always asked. A task or lists scope the search to the people who share them.
    static func searchUsers(query: String, taskId: String?, listIds: [String]?) -> CoreCommand {
        var command = CoreCommand(kind: "searchUsers")
        command.set("query", query)
        command.set("taskId", taskId)
        if let listIds, !listIds.isEmpty {
            command.set("listIds", listIds)
        }
        command.set("includeAgents", true)
        return command
    }

    /// Autocomplete over the imported contacts, for adding a member. The core refuses a query
    /// under two characters without sending it, as the route would; the callers already stop
    /// short of that. `excludeListId` leaves out that list's members.
    static func searchContacts(query: String, excludeListId: String?, limit: Int = 10) -> CoreCommand {
        var command = CoreCommand(kind: "searchContacts")
        command.set("query", query)
        command.set("excludeListId", excludeListId)
        command.set("limit", limit)
        return command
    }

    /// The Astrid users in this account's contacts, mutual ones first.
    static func recommendedCollaborators(excludeListId: String?, limit: Int = 20) -> CoreCommand {
        var command = CoreCommand(kind: "recommendedCollaborators")
        command.set("excludeListId", excludeListId)
        command.set("limit", limit)
        return command
    }
}

/// The core's `contacts` answer, read for the count alone.
nonisolated struct ContactStatus: Decodable, Sendable {
    let total: Int
}

/// The core's `searchContacts` answer: `{ results }`, each row as the route sends it.
nonisolated struct ContactSearchAnswer: Decodable, Sendable {
    let results: [ContactSearchResult]
}

/// The core's `recommendedCollaborators` answer, read for the rows alone. `stats` and `message`
/// arrive as null when no contacts are uploaded, and nothing on screen shows them.
nonisolated struct RecommendedCollaboratorsAnswer: Decodable, Sendable {
    let recommended: [RecommendedCollaborator]
}
