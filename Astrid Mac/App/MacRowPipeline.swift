//  MacRowPipeline.swift
//  Astrid for Mac — the PURE row glue extracted from MacRootView (Task 0b1ee8f7) so the
//  previously-untested parts (sort-override fallback, keyboard-navigation index math) have direct
//  regression tests. The rows themselves — filter, sort, splice — are astrid-core's `rowsForList`
//  since AITD-460, asked through `ListRowsModel` exactly as iOS asks.

#if os(macOS)
import Foundation

enum MacRowPipeline {

    /// Which sort key applies.
    ///
    /// A REAL LIST'S OWN SORT ALWAYS WINS (AITD-389). `sortBy` is a column on the shared list
    /// row: every member sees the same order, and a device-local override quietly reordering it
    /// for one person on one Mac is not a preference, it is the list lying about itself. Worse,
    /// the toolbar menu reads `list.sortBy`, so the control showed one sort while the rows were
    /// in another.
    ///
    /// The override exists for selections that own no row to write to — Search, a public list you
    /// only view. That is the whole of its job, and what `sortMenu` has always claimed it did.
    ///
    /// IT TAKES THE LIST, NOT ITS `sortBy`. The old signature took `listSortBy: String?`, where
    /// nil meant both "no list" and "a list that has never set a sort" — so the rule could not
    /// tell them apart and the ambiguity is what hid the bug. The list itself is the
    /// discriminator, so the two cases cannot be confused again.
    ///
    /// My Tasks is the same rule one step over (AITD-467): its sort is synced in
    /// `MyTasksPreferences`, written by its sheet and read by iOS, so it outranks the override
    /// just as a list's does. Pass `myTasks` only when My Tasks is the selection.
    static func effectiveSortKey(override: String, list: TaskList?,
                                 myTasks: MyTasksPreferences? = nil) -> String {
        if let list { return list.sortBy ?? "auto" }
        if let myTasks { return myTasks.sortBy ?? "auto" }
        return override.isEmpty ? "auto" : override
    }

    /// What the core is asked for a selection's rows (AITD-460): the same `rowsForList` iOS
    /// asks, with the selection's inputs as this window holds them. nil for no selection and for
    /// Search, whose rows are `TaskSearchModel`'s.
    @MainActor
    static func rowsQuery(selection id: String?, myTasksId: String, searchId: String, lists: [TaskList],
                          myTasks: MyTasksPreferences, override: String, userId: String?,
                          tasksInList: (String) -> [Task], publicListTasks: [String: [Task]]) -> ListRowsModel.Query? {
        guard let id, id != searchId else { return nil }
        let display = UserSettingsService.shared.settings.subtaskDisplay ?? "indented"
        // The window's own sort, for the selections that have no list row to save one on.
        let override = override.isEmpty ? nil : override
        // My Tasks sorts by its synced preference, as iOS asks (AITD-467) — no window override.
        if id == myTasksId {
            return .init(listId: ListRowsModel.myTasksId, myTasks: myTasks, subtaskDisplay: display,
                         currentUserId: userId)
        }
        // A list of yours — real or saved filter: its own filters and sort, always (AITD-389).
        if let list = lists.first(where: { $0.id == id }) {
            return .init(listId: id, list: list, subtaskDisplay: display, currentUserId: userId)
        }
        // A public list you only view (dfb037c7): no filters of yours to apply, the window's sort,
        // and its tasks from the on-demand fetch, which the cache does not hold.
        var shape = TaskList(id: id, name: "")
        shape.filterCompletion = "all"
        shape.sortBy = override ?? "auto"
        let mine = tasksInList(id)
        return .init(listId: id, list: shape, tasks: mine.isEmpty ? publicListTasks[id] : nil,
                     subtaskDisplay: display, currentUserId: userId)
    }

    /// The sidebar's numbers (AITD-460): a list's own from membership, a saved filter's and My
    /// Tasks' from astrid-core — two calls, `listCounts` and one `rowsForList` — by the rules their
    /// rows are drawn with. `myTasks` is nil when the core could not answer.
    @MainActor
    static func counts(_ tasks: [Task], lists: [TaskList], myTasks: MyTasksPreferences,
                       userId: String?) async -> (lists: [String: Int], myTasks: Int?) {
        let session = AppCore.shared.session
        let virtual = await ListTaskCount.virtualCounts(lists: lists, currentUserId: userId, session: session)
        let mine = await ListRowsModel.matched(
            for: .init(listId: ListRowsModel.myTasksId, myTasks: myTasks, currentUserId: userId), session: session)
        return (MacListCount.counts(tasks, lists: lists, virtualCounts: virtual), mine)
    }

    /// j/k / ↑↓ selection movement over the rendered order: clamped at the ends; with no current
    /// selection, down selects the first row and up selects the last.
    static func nextSelection(orderedIds: [String], current: String?, direction: Int) -> String? {
        guard !orderedIds.isEmpty else { return nil }
        if let current, let idx = orderedIds.firstIndex(of: current) {
            return orderedIds[max(0, min(orderedIds.count - 1, idx + direction))]
        }
        return direction >= 0 ? orderedIds.first : orderedIds.last
    }
}
#endif
