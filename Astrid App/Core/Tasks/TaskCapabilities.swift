//  TaskCapabilities.swift
//  Which editing controls a task's lists allow (AITD-491, web `lib/backends/supports.ts`).
//
//  A GitHub Projects board refuses a priority or due-date write when the board has no such field
//  mapped, so the server says so in `list.supports` and the editor does not offer the control.
//  Asked here once, so the phone and the Mac cannot answer it differently.
//
//  The rule itself is astrid-core's `capabilities` (AITD-667): which lists refuse, and when a
//  delete is a removal, are decided there, so web, Windows and Android cannot answer it a third
//  way. What stays here is the Swift vocabulary the views speak — `Control`, `Deletion`'s keys,
//  and `admitted`'s dropping of refused values.

import AstridCore
import Foundation

enum TaskCapabilities {
    enum Control: Hashable {
        case priority, dueDate
        /// `isPrivate` means something on a classic list. A GitHub board's tasks are as visible
        /// as the project is (spec 9.1), so the server refuses the write.
        case privateTasks
    }

    /// The core's answer for a task on `listIds`. Sent only the lists the task is on — the only
    /// ones the rule reads — so a view drawing a row does not encode every list it knows.
    static func answer(listIds: [String], lists: [TaskList]) -> ListCapabilities {
        CoreRules.capabilities(listIds: listIds, lists: lists.filter { listIds.contains($0.id) })
    }

    /// A control is offered unless a list the task is on refuses it. A list that is not loaded
    /// yet refuses nothing: hiding a control that works is the worse mistake.
    static func allows(_ control: Control, listIds: [String], lists: [TaskList]) -> Bool {
        allows(control, in: answer(listIds: listIds, lists: lists))
    }

    private static func allows(_ control: Control, in answer: ListCapabilities) -> Bool {
        switch control {
        case .priority: return answer.priority
        case .dueDate: return answer.dueDate
        case .privateTasks: return answer.privateTasks
        }
    }

    /// The same rule for ONE list — what a list's own settings screen has in hand, rather than
    /// the set of lists a task is on.
    static func allows(_ control: Control, on list: TaskList) -> Bool {
        allows(control, listIds: [list.id], lists: [list])
    }

    /// The controls those lists refuse. One question for all three.
    static func refused(listIds: [String], lists: [TaskList]) -> Set<Control> {
        let answer = answer(listIds: listIds, lists: lists)
        return Set([Control.priority, .dueDate, .privateTasks].filter { !allows($0, in: answer) })
    }

    /// What a new task may carry onto these lists. A value they refuse is dropped rather than
    /// sent: a list's default, a smart-parsed "!!" or "tomorrow" would otherwise make a create
    /// the server rejects, and the task would never reach the board.
    static func admitted(priority: Int?, whenDate: Date?, whenTime: Date?, isPrivate: Bool?,
                         listIds: [String], lists: [TaskList])
        -> (priority: Int?, whenDate: Date?, whenTime: Date?, isPrivate: Bool?) {
        let answer = answer(listIds: listIds, lists: lists)
        return (answer.priority ? priority : nil,
                answer.dueDate ? whenDate : nil,
                answer.dueDate ? whenTime : nil,
                answer.privateTasks ? isPrivate : nil)
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
        answer(listIds: listIds, lists: lists).deletion == .removeFromList ? .removeFromBoard : .delete
    }

    static func deleteWording(for task: Task, lists: [TaskList]) -> Deletion {
        deleteWording(listIds: taskListMembershipIdsInOrder(task), lists: lists)
    }
}
