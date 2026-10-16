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
    }

    /// A control is offered unless a list the task is on refuses it. A list that is not loaded
    /// yet refuses nothing: hiding a control that works is the worse mistake.
    static func allows(_ control: Control, listIds: [String], lists: [TaskList]) -> Bool {
        !lists.contains { list in
            guard listIds.contains(list.id), let supports = list.supports else { return false }
            switch control {
            case .priority: return !supports.priority
            case .dueDate: return !supports.dueDate
            }
        }
    }

    /// The controls those lists refuse.
    static func refused(listIds: [String], lists: [TaskList]) -> Set<Control> {
        Set([Control.priority, .dueDate].filter { !allows($0, listIds: listIds, lists: lists) })
    }
}
