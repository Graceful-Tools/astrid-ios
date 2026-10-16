//  TaskCapabilities.swift
//  Which editing controls a task's lists allow (AITD-491, web `lib/backends/supports.ts`).
//
//  A GitHub Projects board refuses a priority or due-date write when the board has no such field
//  mapped, so the server says so in `list.supports` and the editor does not offer the control.
//  Asked here once, so the phone and the Mac cannot answer it differently.

import Foundation

enum TaskCapabilities {
    enum Control: Hashable {
        case priority, dueDate
        /// `isPrivate` means something on a classic list. A GitHub board's tasks are as visible
        /// as the project is (spec 9.1), so the server refuses the write.
        case privateTasks
    }

    /// A control is offered unless a list the task is on refuses it. A list that is not loaded
    /// yet refuses nothing: hiding a control that works is the worse mistake.
    static func allows(_ control: Control, listIds: [String], lists: [TaskList]) -> Bool {
        !lists.contains { list in
            guard listIds.contains(list.id), let supports = list.supports else { return false }
            switch control {
            case .priority: return !supports.priority
            case .dueDate: return !supports.dueDate
            case .privateTasks: return !supports.privateTasks
            }
        }
    }

    /// The same rule for ONE list — what a list's own settings screen has in hand, rather than
    /// the set of lists a task is on.
    static func allows(_ control: Control, on list: TaskList) -> Bool {
        allows(control, listIds: [list.id], lists: [list])
    }

    /// The controls those lists refuse.
    static func refused(listIds: [String], lists: [TaskList]) -> Set<Control> {
        Set([Control.priority, .dueDate, .privateTasks].filter { !allows($0, listIds: listIds, lists: lists) })
    }

    /// What a new task may carry onto these lists. A value they refuse is dropped rather than
    /// sent: a list's default, a smart-parsed "!!" or "tomorrow" would otherwise make a create
    /// the server rejects, and the task would never reach the board.
    static func admitted(priority: Int?, whenDate: Date?, whenTime: Date?, isPrivate: Bool?,
                         listIds: [String], lists: [TaskList])
        -> (priority: Int?, whenDate: Date?, whenTime: Date?, isPrivate: Bool?) {
        let datesAllowed = allows(.dueDate, listIds: listIds, lists: lists)
        return (allows(.priority, listIds: listIds, lists: lists) ? priority : nil,
                datesAllowed ? whenDate : nil,
                datesAllowed ? whenTime : nil,
                allows(.privateTasks, listIds: listIds, lists: lists) ? isPrivate : nil)
    }

    /// What deleting the task is called. On a GitHub board an Astrid delete removes the item from
    /// the project and the issue stays (spec §8), so "Delete" would promise more than happens.
    enum Deletion: Equatable {
        case delete, removeFromBoard

        var actionKey: String { self == .delete ? "tasks.delete_task" : "tasks.remove_from_board" }
        var confirmKey: String { self == .delete ? "tasks.delete_confirm" : "tasks.remove_from_board_confirm" }
        var buttonKey: String { self == .delete ? "actions.delete" : "actions.remove" }
    }

    /// A removal when a loaded list the task is on removes and none deletes. A task also on a
    /// classic list really is deleted from Astrid; a list not loaded yet changes neither answer.
    static func deleteWording(listIds: [String], lists: [TaskList]) -> Deletion {
        let modes = lists.filter { listIds.contains($0.id) }.map { $0.supports?.deleteTask ?? .delete }
        return modes.contains(.removeFromList) && !modes.contains(.delete) ? .removeFromBoard : .delete
    }

    static func deleteWording(for task: Task, lists: [TaskList]) -> Deletion {
        deleteWording(listIds: taskListMembershipIdsInOrder(task), lists: lists)
    }
}
