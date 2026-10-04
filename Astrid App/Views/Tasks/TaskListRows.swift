//  TaskListRows.swift
//  The parts of TaskListView's row pipeline that do not need the view (AITD-455).

import Foundation

/// Everything TaskListView's row pipeline reads. A body is re-evaluated on every selection, drag
/// hover and sheet; the pipeline filters, sorts and splices EVERY task, so it runs only when one
/// of these changes. The minute is in the key because the due-date and recently-completed
/// filters read the clock.
struct TaskListRowsKey: Equatable {
    let tasks: [Task]
    let featuredListTasks: [Task]
    let selectedListId: String?
    let selectedList: TaskList?
    let isViewingFromFeatured: Bool
    let searchText: String
    /// What the core found for `searchText` (AITD-459); rows follow it when it lands.
    var searchResultIds: [String] = []
    let myTasksPreferences: MyTasksPreferences
    var subtaskDisplay: String? = UserSettingsService.shared.settings.subtaskDisplay
    var userId: String? = AuthManager.shared.userId
    var minute = Int(Date().timeIntervalSince1970 / 60)
}

enum TaskListRows {
    /// A featured public list: your own tasks in it (the source of truth — optimistic tasks,
    /// edits) plus other people's public tasks from the list fetch, yours winning on a clash.
    static func mergeFeatured(tasks: [Task], featuredListTasks: [Task], listId: String,
                              currentUserId: String?) -> [Task] {
        var merged = tasks.filter { $0.listIds?.contains(listId) == true }
        var seen = Set(merged.map(\.id))
        for task in featuredListTasks
        where task.creatorId != currentUserId && task.assigneeId != currentUserId && !seen.contains(task.id) {
            merged.append(task)
            seen.insert(task.id)
        }
        return merged
    }
}
