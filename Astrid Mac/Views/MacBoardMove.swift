//  MacBoardMove.swift
//  Astrid for Mac — plan a project-status board drag/drop into service operations (Task 196d482a).
//
//  Uses the shared ProjectStatus contract (resolveProjectColumnMove / getTaskProjectColumnId) and
//  splits completion transitions out so the Done column goes through TaskService.completeTask
//  (repeat rollover), never updateTask(completed:), per ASTRID.md.

#if os(macOS)
import Foundation

enum MacBoardMove {
    /// Each case carries the status role to write as well as the lists, because the board
    /// resolves a card's column from `Task.statusRole` first (AWTD-566). A plan that described
    /// only the membership left the role behind, and the resolver put the card straight back
    /// where it came from — "moving from Ready to Inbox doesn't always work", where "not
    /// always" meant "not for any task that has a role".
    ///
    /// `statusRole` is "" for Inbox and Done, which carry no status; "" is the value that
    /// CLEARS it, both locally and on the server.
    enum Plan: Equatable {
        case none                                              // dropped onto its current column
        case setLists([String], statusRole: String)            // status/inbox move, no completion change
        case complete([String], statusRole: String)            // → Done: set lists then complete
        case uncomplete([String], statusRole: String)          // Done → elsewhere: un-complete then set lists
    }

    static func plan(task: Task, column: ProjectBoardColumn, lists: [TaskList]) -> Plan {
        if getTaskProjectColumnId(task, lists: lists) == column.id { return .none }
        let move = resolveProjectColumnMove(task, targetColumn: column, lists: lists)
        let role = move.statusRole ?? ""
        switch column.kind {
        case .done:
            return .complete(move.listIds, statusRole: role)
        case .inbox, .status:
            return task.completed
                ? .uncomplete(move.listIds, statusRole: role)
                : .setLists(move.listIds, statusRole: role)
        }
    }
}
#endif
