import Foundation

/// Whether a list splices its subtasks inline (Task ba1deb9d).
///
/// The Swift twin of astrid-web's `lib/list-subtask-visibility.ts` — the canonical module, in the
/// same role `RecentlyCompletedWindow` plays for the completed filter. Changing one without the
/// other is a cross-platform bug on whichever side moved.
///
/// Two controls answer different questions:
///
///   - the USER setting `subtaskDisplay` — WHERE subtasks appear at all: `indented` (inline under
///     their parent) or `under_parent` (detail view only). The broader of the two.
///   - the LIST setting `showSubtasks` — whether THIS list shows them inline.
///
/// A list can opt OUT; it cannot opt back IN over a user who has chosen detail-only, because that
/// choice is about the whole product rather than one list. The more restrictive wins, and the
/// user's is the one that cannot be overridden.
///
/// **Absent means SHOW.** Every list decoded by a build that predates the field reads back nil,
/// as does any response that omits it. Defaulting to hide would silently empty all of them.
enum ListSubtaskVisibility {

    /// The user-level display mode that means "detail view only".
    static let detailOnlyDisplay = "under_parent"

    /// True unless the list has explicitly turned subtasks off.
    static func listShowsSubtasks(_ showSubtasks: Bool?) -> Bool {
        showSubtasks != false
    }

    /// Whether the task list should splice subtasks in under their parents.
    ///
    /// Anything other than `under_parent` — including nil, and a mode a future build introduces
    /// that this one has never heard of — means inline display is wanted. Treating an unknown
    /// mode as "hide" would blank out every list on the older client.
    static func shouldSplice(listShowSubtasks: Bool?, subtaskDisplay: String?) -> Bool {
        guard subtaskDisplay != detailOnlyDisplay else { return false }
        return listShowsSubtasks(listShowSubtasks)
    }

    /// What to PUT for `showSubtasks`, or nil to leave the key out of the payload entirely.
    ///
    /// Only an actual change is sent. The web handler writes the column only when the caller
    /// sends a real boolean, precisely so a client PUTing a whole list object cannot reset
    /// someone's toggle; this is the same guard from the other side. Sending `false` merely
    /// because a decoded model defaulted would turn every unrelated list edit — a rename, a
    /// colour change — into a silent "hide the subtasks".
    static func payloadValue(original: Bool?, edited: Bool?) -> Bool? {
        guard original != edited else { return nil }
        // An edit back to "no opinion" still has to say something on the wire, and the value
        // that means no opinion is `true` — absent means show.
        return edited ?? true
    }
}
