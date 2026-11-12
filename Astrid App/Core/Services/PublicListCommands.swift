import AstridCore
import Foundation

/// The astrid-core commands behind public-list browsing (AITD-620): the catalogue anybody may
/// browse, and copying one of its lists into this account.
///
/// Both are online-only in the core (`services/list.rs`): the server keeps the catalogue and does
/// the copying. This only spells the commands, so `RemoteResourceService` stays a face and the
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
}
