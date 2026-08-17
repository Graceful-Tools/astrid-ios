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

    /// Delegates to the SHARED planner. The rule moved to `planProjectColumnMove` when the
    /// quick changer gave iOS a second way to change a column (task 729a190e); this stays as
    /// the Mac's name for it so the board's call sites and tests are untouched.
    static func plan(task: Task, column: ProjectBoardColumn, lists: [TaskList]) -> Plan {
        switch planProjectColumnMove(task: task, column: column, lists: lists) {
        case .none: return .none
        case .setLists(let ids, let role): return .setLists(ids, statusRole: role)
        case .complete(let ids, let role): return .complete(ids, statusRole: role)
        case .uncomplete(let ids, let role): return .uncomplete(ids, statusRole: role)
        }
    }
}
#endif
