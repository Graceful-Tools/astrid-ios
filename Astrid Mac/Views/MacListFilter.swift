//  MacListFilter.swift
//  Astrid for Mac — pure option model for the list filter editor (Task a2bf6ccb).
//
//  The option VALUES are the exact strings the SHARED reader (Core/Filters/ListTaskFiltering +
//  RecentlyCompletedPresets) understands, so editing them on Mac produces the same filtered set
//  as iOS/web. Pure + testable; the sheet is just presentation over this.

#if os(macOS)
import Foundation

enum MacListFilter {
    struct Option: Identifiable, Equatable {
        let value: String
        let label: String
        var id: String { value }
        init(_ value: String, _ label: String) { self.value = value; self.label = label }
    }

    /// Completion — matches applyCompletionFilterWithWindow ("default"/"all"/"completed"/"incomplete").
    static let completion: [Option] = [
        .init("default", "Default"), .init("all", "All"),
        .init("incomplete", "Active only"), .init("completed", "Completed only"),
    ]
    /// Priority — "all" or the raw priority int, matching filterTasksForList.
    static let priority: [Option] = [
        .init("all", "Any priority"), .init("3", "!!! High"), .init("2", "!! Medium"),
        .init("1", "! Low"), .init("0", "○ None"),
    ]
    /// Due date — matches applyListDueDateFilter cases.
    static let dueDate: [Option] = [
        .init("all", "Any time"), .init("overdue", "Overdue"), .init("today", "Today"),
        .init("this_week", "This week"), .init("this_month", "This month"), .init("no_date", "No date"),
    ]
    /// Assignee — matches the assignee switch in filterTasksForList.
    static let assignee: [Option] = [
        .init("all", "Anyone"), .init("current_user", "Me"),
        .init("not_current_user", "Someone else"), .init("unassigned", "Unassigned"),
    ]

    /// Default (inactive) sentinel for each dimension.
    static func isDefault(_ value: String?, dimension: Dimension) -> Bool {
        let v = value ?? dimension.defaultValue
        return v.isEmpty || v == dimension.defaultValue
    }

    enum Dimension { case completion, priority, dueDate, assignee
        var defaultValue: String { self == .completion ? "default" : "all" }
    }

    /// How many dimensions are set to a non-default value (drives the toolbar's active badge).
    static func activeCount(completion: String?, priority: String?, dueDate: String?, assignee: String?) -> Int {
        var n = 0
        if !isDefault(completion, dimension: .completion) { n += 1 }
        if !isDefault(priority, dimension: .priority) { n += 1 }
        if !isDefault(dueDate, dimension: .dueDate) { n += 1 }
        if !isDefault(assignee, dimension: .assignee) { n += 1 }
        return n
    }

    /// The `updateListAdvanced` payload that turns a freshly-created list into a saved-filter (Smart)
    /// list carrying the current filters — mirrors iOS SaveFilterDialog (Task efd05e56).
    static func smartListUpdates(completion: String, priority: String, dueDate: String,
                                 assignee: String, sortBy: String) -> [String: Any] {
        [
            "isVirtual": true,
            "sortBy": sortBy,
            "filterCompletion": completion,
            "filterPriority": priority,
            "filterDueDate": dueDate,
            "filterAssignee": assignee,
        ]
    }
}
#endif
