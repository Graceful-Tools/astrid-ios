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
    // Every option below mirrors iOS's ListSortFiltersTab EXACTLY — same values (the
    // cross-platform contract) AND the same localized keys, so both apps read identically in every
    // language. Mac previously invented its own wording ("Show", "Active only", "Any priority")
    // and even disagreed about what priority 0 means.
    private static func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    static let completion: [Option] = [
        .init("default", L("lists.incomplete_completed_recently")), .init("all", L("lists.all")),
        .init("completed", L("tasks.completed")), .init("incomplete", L("tasks.incomplete")),
    ]
    /// Priority — iOS labels: 3 = Highest, 2 = High, 1 = Medium, 0 = Low.
    static let priority: [Option] = [
        .init("all", L("lists.all_priorities")), .init("3", L("lists.highest_priority")),
        .init("2", L("lists.high_priority")), .init("1", L("lists.medium_priority")),
        .init("0", L("lists.low_priority")),
    ]
    static let dueDate: [Option] = [
        .init("all", L("lists.all")), .init("overdue", L("lists.overdue")),
        .init("today", L("time.today")), .init("this_week", L("lists.this_week")),
        .init("this_month", L("lists.this_month")), .init("no_date", L("lists.no_date")),
    ]
    static let assignee: [Option] = [
        .init("all", L("lists.all")), .init("current_user", L("lists.me")),
        .init("not_current_user", L("lists.not_me")), .init("unassigned", L("assignee.unassigned")),
    ]
    /// Sort — iOS tags: "when" is Due Date.
    static let sort: [Option] = [
        .init("auto", L("lists.auto")), .init("manual", L("lists.manual")),
        .init("when", L("lists.due_date")), .init("priority", L("tasks.priority")),
        .init("createdAt", L("lists.created_date")),
        .init("completedAt", L("lists.recently_completed")),
    ]
    static let assignedBy: [Option] = [
        .init("all", L("lists.all")), .init("current_user", L("lists.me")),
        .init("not_current_user", L("lists.not_me")),
    ]
    /// Repeating — iOS offers the specific cadences, not just a yes/no.
    static let repeating: [Option] = [
        .init("all", L("lists.all")), .init("not_repeating", L("lists.not_repeating")),
        .init("daily", L("lists.daily")), .init("weekly", L("lists.weekly")),
        .init("monthly", L("lists.monthly")), .init("yearly", L("lists.yearly")),
        .init("custom", L("lists.custom")),
    ]

    /// Default (inactive) sentinel for each dimension.
    static func isDefault(_ value: String?, dimension: Dimension) -> Bool {
        let v = value ?? dimension.defaultValue
        return v.isEmpty || v == dimension.defaultValue
    }

    enum Dimension { case completion, priority, dueDate, assignee, repeating
        // Only completion has ever had a non-"all" default; the rest, repeating included, are "all".
        var defaultValue: String { self == .completion ? "default" : "all" }
    }

    /// How many dimensions are set to a non-default value (drives the toolbar's active badge).
    static func activeCount(completion: String?, priority: String?, dueDate: String?, assignee: String?,
                            repeating: String? = nil, assignedBy: String? = nil) -> Int {
        var n = 0
        if !isDefault(completion, dimension: .completion) { n += 1 }
        if !isDefault(priority, dimension: .priority) { n += 1 }
        if !isDefault(dueDate, dimension: .dueDate) { n += 1 }
        if !isDefault(assignee, dimension: .assignee) { n += 1 }
        // Repeating and assigned-by are two of the six controls the sheet offers, and they were
        // missing here (task 70d849f8): a repeating-only filter counted as zero, which left the
        // "Save as Smart List" link disabled, the toolbar badge unlit and Clear greyed out. They
        // default to nil so callers that predate them keep their old answer.
        if !isDefault(repeating, dimension: .repeating) { n += 1 }
        if !isDefault(assignedBy, dimension: .assignee) { n += 1 }
        return n
    }

    /// The `updateListAdvanced` payload that turns a freshly-created list into a saved-filter (Smart)
    /// list carrying the current filters — mirrors iOS SaveFilterDialog (Task efd05e56).
    static func smartListUpdates(completion: String, priority: String, dueDate: String,
                                 assignee: String, sortBy: String,
                                 repeating: String = "all", assignedBy: String = "all") -> [String: Any] {
        [
            "isVirtual": true,
            "sortBy": sortBy,
            "filterCompletion": completion,
            "filterPriority": priority,
            "filterDueDate": dueDate,
            "filterAssignee": assignee,
            // Both were dropped before (task 70d849f8), so a Smart List saved from a repeating or
            // assigned-by filter silently showed different tasks than the filter it was saved from.
            "filterRepeating": repeating,
            "filterAssignedBy": assignedBy,
        ]
    }

    /// Turn a saved-filter list back into a normal one (task 0e09b224).
    ///
    /// Deliberately ONLY the flag. The filters stay on the list — they simply stop deciding
    /// membership — because clearing them here would destroy a setup the user may have spent
    /// real time on, for a toggle they might flip straight back.
    static func revertToNormalListUpdates() -> [String: Any] {
        ["isVirtual": false]
    }
}
#endif
