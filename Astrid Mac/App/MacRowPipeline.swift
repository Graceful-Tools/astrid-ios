//  MacRowPipeline.swift
//  Astrid for Mac — the PURE row-composition pipeline extracted from MacRootView (Task 0b1ee8f7)
//  so the previously-untested view glue (sort-override fallback, splice completion mapping,
//  keyboard-navigation index math) has direct regression tests. MacRootView delegates here.

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
    /// The override exists for selections that own no list row to write to — My Tasks, Search, a
    /// saved filter. That is the whole of its job, and what `sortMenu` has always claimed it did.
    ///
    /// IT TAKES THE LIST, NOT ITS `sortBy`. The old signature took `listSortBy: String?`, where
    /// nil meant both "no list" and "a list that has never set a sort" — so the rule could not
    /// tell them apart and the ambiguity is what hid the bug. The list itself is the
    /// discriminator, so the two cases cannot be confused again.
    static func effectiveSortKey(override: String, list: TaskList?) -> String {
        if let list { return list.sortBy ?? "auto" }
        return override.isEmpty ? "auto" : override
    }

    /// Filter+sort for the current selection — the exact composition MacRootView renders.
    /// `list` nil = virtual selection (My Tasks / Search / no list): auto/override sort only.
    static func displayed(base: [Task], list: TaskList?, override: String, currentUserId: String?) -> [Task] {
        if let list {
            let filtered = filterTasksForList(base, list: list, currentUserId: currentUserId)
            return sortTasksByListSetting(filtered,
                                          sortBy: effectiveSortKey(override: override, list: list),
                                          manualOrder: list.manualSortOrder)
        }
        return sortTasksByListSetting(base,
                                      sortBy: effectiveSortKey(override: override, list: nil),
                                      manualOrder: nil)
    }

    /// Completed subtasks show only when the list's completion filter includes completed.
    static func showsCompletedSubtasks(filterCompletion: String?) -> Bool {
        ["all", "completed"].contains(filterCompletion ?? "default")
    }

    /// Rows to render: top-level displayed tasks with subtasks spliced under them.
    static func rendered(displayed: [Task], allTasks: [Task], indented: Bool,
                         filterCompletion: String?) -> [Task] {
        let showCompleted = showsCompletedSubtasks(filterCompletion: filterCompletion)
        return spliceSubtasks(topLevel: displayed.filter { $0.parentTaskId == nil },
                              allTasks: allTasks, indented: indented,
                              subtaskVisible: { showCompleted || !$0.completed })
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
