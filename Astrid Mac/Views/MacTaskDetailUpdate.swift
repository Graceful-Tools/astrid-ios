//  MacTaskDetailUpdate.swift
//  Astrid for Mac — pure decision helpers for MacTaskDetailView edits (task 63a27f1b).
//
//  These map the detail view's UI state to the exact arguments TaskService.updateTask
//  expects. Kept as pure functions so the clearing/preservation semantics are unit-testable
//  without a running view (the original bug was the view early-returning instead of sending
//  the shared clear sentinels).

#if os(macOS)
import Foundation

enum MacTaskDetailUpdate {
    /// Argument for `TaskService.updateTask(dueDateTime:)`.
    /// When the Due-date toggle is OFF we must send the shared clear sentinel
    /// (`Date.distantPast`) so the due date is actually cleared — not skip the update.
    static func dueDateArg(hasDue: Bool, due: Date) -> Date {
        hasDue ? due : .distantPast
    }

    /// Argument for `TaskService.updateTask(assigneeId:)`.
    /// Per the service contract, empty string unassigns; a nil selection ("No one")
    /// must therefore map to "" rather than being ignored.
    static func assigneeArg(_ id: String?) -> String {
        id ?? ""
    }

    /// Argument for `TaskService.updateTask(repeatFrom:)`.
    /// Preserve the task's existing repeat-from mode instead of hard-coding DUE_DATE,
    /// which would silently flip a "repeat from completion date" task on any repeat edit.
    static func repeatFromArg(_ task: Task) -> String {
        (task.repeatFrom ?? .DUE_DATE).rawValue
    }
}
#endif
