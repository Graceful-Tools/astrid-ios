//  MacBoardMove.swift
//  Astrid for Mac — plan a project-status board drag/drop into service operations (Task 196d482a).
//
//  Uses the shared ProjectStatus contract (resolveProjectColumnMove / getTaskProjectColumnId) and
//  splits completion transitions out so the Done column goes through TaskService.completeTask
//  (repeat rollover), never updateTask(completed:), per ASTRID.md.

#if os(macOS)
import Foundation

enum MacBoardMove {
    enum Plan: Equatable {
        case none                          // dropped onto its current column
        case setLists([String])            // status/inbox move, no completion change
        case complete([String])            // → Done: set lists (status stripped) then complete
        case uncomplete([String])          // Done → elsewhere: un-complete then set lists
    }

    static func plan(task: Task, column: ProjectBoardColumn, lists: [TaskList]) -> Plan {
        if getTaskProjectColumnId(task, lists: lists) == column.id { return .none }
        let move = resolveProjectColumnMove(task, targetColumn: column, lists: lists)
        switch column.kind {
        case .done:
            return .complete(move.listIds)
        case .inbox, .status:
            return task.completed ? .uncomplete(move.listIds) : .setLists(move.listIds)
        }
    }
}
#endif
