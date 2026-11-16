import AstridCore
import Foundation

/// The astrid-core commands behind public-list browsing (AITD-620): the catalogue anybody may
/// browse, a featured list's tasks (AITD-634), and copying one of its lists into this account.
///
/// All three are online-only in the core (`services/list.rs`): the server keeps the catalogue and the
/// lists' tasks, and does the copying. This only spells the commands, so `RemoteResourceService` stays a face and the
/// spelling is testable without a server.
enum PublicListCommands {
    /// The core asks for the 50 most-copied lists and answers with the rows (`PublicListSummary`),
    /// unwrapped from the server's `{ lists: [...] }`.
    static func catalogue() -> CoreCommand {
        CoreCommand(kind: "publicLists")
    }

    /// The core always copies with the tasks, caches the new list (and its tasks when the answer
    /// carries them), and answers with the list.
    static func copy(listId: String) -> CoreCommand {
        var command = CoreCommand(kind: "copyList")
        command.set("listId", listId)
        return command
    }

    /// A featured public list's tasks (AITD-634): the core fetches them from the server without
    /// caching them, adds this account's unsent ones for the list, and answers the rows with the
    /// tasks behind them. `list` is the public list as the app holds it, when this account does
    /// not — the core reads it for the reader's role.
    static func featuredRows(listId: String, list: TaskList?) -> CoreCommand {
        var command = CoreCommand(kind: "featuredRows")
        command.set("listId", listId)
        command.set("list", list)
        return command
    }

    /// The part of `featuredRows`'s answer the views read: the tasks, whole, in the core's order.
    /// The rows beside them are the projection, which the views do not draw yet.
    struct FeaturedRowsAnswer: Decodable {
        let tasks: [Task]
    }
}
