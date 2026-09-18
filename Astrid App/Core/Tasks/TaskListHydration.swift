import Foundation

/// Rebuild a task's `lists` from its `listIds` against the lists we have cached (AITD-415).
///
/// THE ROOT OF THE OFFLINE BUGS. `CDTask.toDomainModel()` restores `listIds` and sets
/// `lists: nil` — "Populate from separate fetch if needed" — so after a cold launch with no
/// network every cached task knows which lists it belongs to but carries none of the list
/// objects. `listIds` is ids only: it can answer *membership*, but it cannot answer name, colour,
/// privacy or members, which is what the UI actually reads.
///
/// So every surface reading `task.lists` for DISPLAY came up empty offline — the list chips on
/// task rows, the list section in task detail, the compact row's subtitle, the reminder's shared
/// faces, the mention list in comments — and the membership tests that only asked `lists` gave
/// wrong answers (AITD-414's sidebar counts, AITD-413's assignee picker, by way of the lists it
/// could not resolve).
///
/// FOUR CALL SITES HAD ALREADY WRITTEN THIS JOIN BY HAND — `TaskService.createTask`,
/// `AutocompleteSupport`, and `CommentSectionViewEnhanced` twice — each slightly differently, and
/// everything that had not written the workaround was simply broken. This is that join, once,
/// applied where tasks come OUT of the cache so nothing downstream has to know.
///
/// It is deliberately NOT a fetch. The lists are already cached; this is the join between two
/// things we hold, which is why it can be a pure function and why it works offline at all.
enum TaskListHydration {

    /// Build the lookup once per batch — hydrating N tasks against M lists is otherwise N×M.
    static func index(_ lists: [TaskList]) -> [String: TaskList] {
        Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// SERVER DATA WINS. A task that arrived from the API already carries its lists, hydrated
    /// deeper than the cache may be; re-joining it against a stale cached copy would be a
    /// downgrade. Only a task whose `lists` is missing or empty is filled in.
    static func hydrated(_ task: Task, using index: [String: TaskList]) -> Task {
        guard task.lists?.isEmpty ?? true else { return task }
        guard let listIds = task.listIds, !listIds.isEmpty else { return task }

        guard let resolved = lists(forListIds: listIds, using: index) else { return task }

        var hydrated = task
        hydrated.lists = resolved
        return hydrated
    }

    /// The join on its own, for a caller holding ids but not yet a task — `TaskService.createTask`
    /// building its optimistic row.
    ///
    /// Order follows `listIds`, so the first chip on a row is stable across launches. Nothing
    /// resolvable answers nil rather than `[]`: a task in a list we have not cached is "we don't
    /// know", and callers like `CompactTaskRow` read empty as "no lists" and would confidently
    /// draw nothing over missing data.
    static func lists(forListIds listIds: [String], using index: [String: TaskList]) -> [TaskList]? {
        let resolved = listIds.compactMap { index[$0] }
        return resolved.isEmpty ? nil : resolved
    }

    static func hydrated(_ tasks: [Task], using lists: [TaskList]) -> [Task] {
        guard !lists.isEmpty else { return tasks }
        let index = index(lists)
        return tasks.map { hydrated($0, using: index) }
    }
}
