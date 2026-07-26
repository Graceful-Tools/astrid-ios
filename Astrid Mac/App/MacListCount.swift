//  MacListCount.swift
//  Astrid for Mac — the sidebar's per-list count (task 74d6f6aa).
//
//  Mirrors iOS ListSidebarView.getTaskCount: a real list counts the INCOMPLETE tasks in it, a
//  saved-filter list counts whatever its filters admit, and a public list trusts the count the API
//  sent. Virtual lists go through the SHARED filterTasksForList rather than a second copy of the
//  filter logic (iOS has its own private copy; this does not add a third).

#if os(macOS)
import Foundation

enum MacListCount {
    static func count(_ tasks: [Task], list: TaskList, currentUserId: String?) -> Int {
        // A public list's membership is not fully local, so trust the server's number.
        if list.privacy == .PUBLIC, let apiCount = list.taskCount { return apiCount }

        if list.isVirtual == true {
            // The list's own filters decide what counts — including whether completed tasks do.
            return filterTasksForList(tasks, list: list, currentUserId: currentUserId).count
        }
        return tasks.filter { belongs($0, to: list.id) && !$0.completed }.count
    }

    /// Membership by either representation — a task carries `listIds`, and sometimes hydrated
    /// `lists`. Checking only one of them under-counts depending on where the task came from.
    private static func belongs(_ task: Task, to listId: String) -> Bool {
        (task.listIds?.contains(listId) ?? false)
            || (task.lists?.contains { $0.id == listId } ?? false)
    }
}
#endif
