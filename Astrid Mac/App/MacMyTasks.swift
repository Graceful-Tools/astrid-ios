//  MacMyTasks.swift
//  Astrid for Mac — pure filter for the virtual "My Tasks" sidebar entry (Task d0306aab).
//
//  The universal "My Tasks" view: every task that is mine or unassigned, de-duplicated across
//  lists. (iOS scopes My Tasks to assignee == me; on Mac we also include unassigned tasks so the
//  universal list isn't empty when the user hasn't explicitly assigned tasks to themselves.
//  Tasks assigned to OTHER people are excluded.)
//
//  THE SAVED FILTERS APPLY HERE TOO (task ebdf94a1). This used to hardcode "incomplete", which
//  meant the completion filter could not even be expressed, and priority and due date were
//  ignored outright. iOS has had all three for a while, saved in `MyTasksPreferences` and synced
//  — so a filter set on the phone did nothing on the desktop, which reads as the desktop being
//  broken rather than as a missing feature.
//
//  The filtering is NOT reimplemented. `applyCompletionFilterWithWindow` and
//  `applyListDueDateFilter` are shared and already mirror iOS, and a second implementation of
//  what "today" means is exactly how two platforms start disagreeing about a due date
//  (ASTRID.md rule 8).

#if os(macOS)
import Foundation

enum MacMyTasks {

    /// My Tasks, with the user's saved filters applied.
    ///
    /// `preferences` is passed in rather than read from the shared service so this stays pure
    /// and testable — the same reason `filterTasksForList` takes `currentUserId`.
    static func filter(_ tasks: [Task],
                       userId: String?,
                       preferences: MyTasksPreferences) -> [Task] {
        // Scope first: whose tasks these are is not a filter the user can change here.
        var seen = Set<String>()
        var result = tasks.filter { task in
            let mineOrUnassigned = task.assigneeId == nil || task.assigneeId == userId
            return mineOrUnassigned && seen.insert(task.id).inserted
        }

        // Completion. No per-list recently-completed window applies to the virtual list, so the
        // window is nil and the shared helper falls back to its plain behaviour.
        result = applyCompletionFilterWithWindow(result,
                                                 filter: preferences.filterCompletion ?? "default",
                                                 window: nil)

        // Priority. My Tasks stores a LIST of priorities where a real list stores one string;
        // empty means "all", and it is the default, so treating it as "match nothing" would
        // blank the view for everyone who has never opened the filter sheet.
        if let priorities = preferences.filterPriority, !priorities.isEmpty {
            result = result.filter { priorities.contains($0.priority.rawValue) }
        }

        // Due date.
        if let dueDate = preferences.filterDueDate, dueDate != "all" {
            result = applyListDueDateFilter(result, filter: dueDate)
        }

        return result
    }
}
#endif
