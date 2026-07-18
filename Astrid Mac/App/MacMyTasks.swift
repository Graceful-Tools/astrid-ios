//  MacMyTasks.swift
//  Astrid for Mac — pure filter for the virtual "My Tasks" sidebar entry (Task d0306aab).
//
//  The universal "My Tasks" view: every incomplete task that is mine or unassigned, de-duplicated
//  across lists. (iOS scopes My Tasks to assignee == me; on Mac we also include unassigned tasks
//  so the universal list isn't empty when the user hasn't explicitly assigned tasks to themselves.
//  Tasks assigned to OTHER people are excluded.)

#if os(macOS)
import Foundation

enum MacMyTasks {
    static func filter(_ tasks: [Task], userId: String?) -> [Task] {
        var seen = Set<String>()
        return tasks.filter { task in
            guard !task.completed else { return false }
            let mineOrUnassigned = task.assigneeId == nil || task.assigneeId == userId
            return mineOrUnassigned && seen.insert(task.id).inserted
        }
    }
}
#endif
