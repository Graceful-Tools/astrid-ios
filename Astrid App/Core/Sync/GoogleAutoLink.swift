import Foundation

/// Google Tasks sync mode: how lists get linked. Stored server-side in
/// Integration.metadata (`googleSyncMode` / `listSuffix`) so the choice
/// follows the account across devices.
enum GoogleSyncMode: String, CaseIterable {
    /// Link lists one at a time (list settings / Settings → Google Tasks).
    case manual
    /// Every Google tasklist mirrors into Astrid; new tasklists are picked up
    /// on each sync and get an Astrid list (with an optional name suffix).
    case allGoogleToAstrid = "all_google_to_astrid"
    /// Every Astrid list mirrors out to Google Tasks (backup); new Astrid
    /// lists are picked up on each sync and get a Google tasklist.
    case allAstridToGoogle = "all_astrid_to_google"
}

/// Pure planning for the auto-link modes: which containers still need a
/// counterpart, and whether an existing unlinked one can be ADOPTED by name
/// instead of creating a duplicate.
enum GoogleAutoLink {
    struct ListRef: Equatable {
        let id: String
        let name: String
    }

    struct GoogleToAstridAction: Equatable {
        let tasklistId: String
        /// Existing unlinked Astrid list to adopt, if any.
        let adoptListId: String?
        /// Name for the Astrid list to create when not adopting.
        let newListName: String
    }

    struct AstridToGoogleAction: Equatable {
        let listId: String
        /// Existing unlinked Google tasklist to adopt, if any.
        let adoptTasklistId: String?
        /// Title for the tasklist to create when not adopting.
        let newTasklistName: String
    }

    static func astridName(for tasklistName: String, suffix: String) -> String {
        let trimmed = suffix.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? tasklistName : "\(tasklistName) \(trimmed)"
    }

    /// Mode 1: every unlinked Google tasklist needs an Astrid counterpart.
    /// Adopts an unlinked local list whose name matches the tasklist's name
    /// (with or without the suffix) — never creates a same-name duplicate.
    static func googleToAstridActions(
        tasklists: [ListRef],
        linkedTasklistIds: Set<String>,
        unlinkedLists: [ListRef],
        suffix: String
    ) -> [GoogleToAstridAction] {
        var adoptable = unlinkedLists
        return tasklists
            .filter { !linkedTasklistIds.contains($0.id) }
            .map { tasklist in
                let target = astridName(for: tasklist.name, suffix: suffix)
                let adoptIndex = adoptable.firstIndex {
                    $0.name == target || $0.name == tasklist.name
                }
                let adopted = adoptIndex.map { adoptable.remove(at: $0) }
                return GoogleToAstridAction(
                    tasklistId: tasklist.id,
                    adoptListId: adopted?.id,
                    newListName: target
                )
            }
    }

    /// Mode 2: every unlinked Astrid list needs a Google counterpart.
    /// Adopts an unlinked tasklist with the same title.
    static func astridToGoogleActions(
        lists: [ListRef],
        linkedListIds: Set<String>,
        unlinkedTasklists: [ListRef]
    ) -> [AstridToGoogleAction] {
        var adoptable = unlinkedTasklists
        return lists
            .filter { !linkedListIds.contains($0.id) && !$0.id.hasPrefix("temp_") }
            .map { list in
                let adoptIndex = adoptable.firstIndex { $0.name == list.name }
                let adopted = adoptIndex.map { adoptable.remove(at: $0) }
                return AstridToGoogleAction(
                    listId: list.id,
                    adoptTasklistId: adopted?.id,
                    newTasklistName: list.name
                )
            }
    }
}
