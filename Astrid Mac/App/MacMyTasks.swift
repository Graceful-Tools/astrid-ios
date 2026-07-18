//  MacMyTasks.swift
//  Astrid for Mac — pure filter for the virtual "My Tasks" sidebar entry (Task d0306aab):
//  incomplete tasks assigned to the current user, de-duplicated across lists.

#if os(macOS)
import Foundation

enum MacMyTasks {
    static func filter(_ tasks: [Task], userId: String?) -> [Task] {
        guard let userId else { return [] }
        var seen = Set<String>()
        return tasks.filter { $0.assigneeId == userId && !$0.completed && seen.insert($0.id).inserted }
    }
}
#endif
