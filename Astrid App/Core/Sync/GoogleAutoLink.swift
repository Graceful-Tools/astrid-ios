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
    /// Both directions: every Google tasklist mirrors in AND every Astrid
    /// list mirrors out — same-name pairs adopt each other, never duplicate.
    case allBidirectional = "all_bidirectional"
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

    /// My Tasks ↔ Google default tasklist phase: active in any all-lists mode
    /// unless a legacy setup already list-linked the default tasklist (then the
    /// list link stays authoritative and the phase must not double-sync).
    static func myTasksPhaseActive(
        mode: GoogleSyncMode, defaultTasklistId: String?, linkedTasklistIds: Set<String>
    ) -> Bool {
        guard mode != .manual, let id = defaultTasklistId else { return false }
        return !linkedTasklistIds.contains(id)
    }

    /// Auto-link candidate filter: Google-down modes can materialize the
    /// default tasklist as a visible Astrid list; Google-up-only mode keeps it
    /// reserved for the My Tasks phase unless a legacy link already exists.
    static func autoLinkCandidates(
        tasklists: [ListRef],
        defaultTasklistId: String?,
        linkedTasklistIds: Set<String>,
        includeUnlinkedDefaultTasklist: Bool
    ) -> [ListRef] {
        tasklists.filter {
            includeUnlinkedDefaultTasklist || $0.id != defaultTasklistId || linkedTasklistIds.contains($0.id)
        }
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

    /// Both directions in one pass. Phase 1 (google→astrid) runs first; phase 2
    /// (astrid→google) sees its consumption — adopted lists count as linked,
    /// and every unlinked tasklist was consumed by phase 1, so nothing is
    /// created twice for a same-name pair.
    static func bidirectionalActions(
        tasklists: [ListRef],
        lists: [ListRef],
        linkedTasklistIds: Set<String>,
        linkedListIds: Set<String>,
        suffix: String
    ) -> (googleToAstrid: [GoogleToAstridAction], astridToGoogle: [AstridToGoogleAction]) {
        let unlinkedLists = lists.filter { !linkedListIds.contains($0.id) }
        let g2a = googleToAstridActions(
            tasklists: tasklists, linkedTasklistIds: linkedTasklistIds,
            unlinkedLists: unlinkedLists, suffix: suffix)
        let consumed = Set(g2a.compactMap { $0.adoptListId })
        let a2g = astridToGoogleActions(
            lists: lists,
            linkedListIds: linkedListIds.union(consumed),
            unlinkedTasklists: [])
        return (g2a, a2g)
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
