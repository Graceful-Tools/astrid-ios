//  MacSubtasks.swift
//  Finding a task's subtasks. (Task effc7112)
//
//  The Mac detail used to walk the PARENT'S LISTS to find its children:
//
//      (task.listIds ?? []).flatMap { taskService.getTasksForList($0) }
//                          .filter { $0.parentTaskId == task.id }
//
//  Three things wrong with that, all pinned by MacSubtaskLookupTests:
//
//  1. A parent with NO list flatMaps over an empty array, so it can never have subtasks — you
//     add one, it is created, and nothing appears. Not an edge case: that is every task added
//     from My Tasks.
//  2. A subtask living in a different list from its parent is invisible.
//  3. A parent in several lists yields the same child once per shared list — duplicates.
//
//  Parentage is a property of the CHILD, so asking about the parent's list membership was
//  answering a different question that happened to agree most of the time. iOS always asked it
//  directly (`tasks.filter { $0.parentTaskId == task.id }`); this states the same question once
//  so the Mac cannot drift from it again.

#if os(macOS)
import Foundation

enum MacSubtasks {
    /// The children of `parent`, in the order they appear in `all`.
    static func of(parent: Task, in all: [Task]) -> [Task] {
        all.filter { $0.parentTaskId == parent.id }
    }
}
#endif
