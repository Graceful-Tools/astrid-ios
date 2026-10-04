//  TaskListRows.swift
//  The parts of TaskListView's row pipeline that do not need the view (AITD-455).

import Foundation

/// Everything TaskListView's rows are made of. A body is re-evaluated on every selection, drag
/// hover and sheet; the rows are looked up only when one of these changes. The filtering, the
/// sort and the splice are astrid-core's (AITD-460) and search's (AITD-459), answered into `ids`
/// asynchronously — so the key is the answer and the tasks it is drawn with, not their inputs.
struct TaskListRowsKey: Equatable {
    let tasks: [Task]
    let featuredListTasks: [Task]
    /// The core's answer for what is on screen; nil when it has not answered for this list yet.
    let ids: [String]?
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
