//  ProjectStateMove.swift
//  Runs a board-column move and RETURNS THE TASK IT PRODUCED.
//
//  The return value is the whole point (task AITD-352). `ProjectStateQuickPicker` used to run the
//  plan and discard every result, which was fine for the board — it reads tasks straight out of
//  the observed `TaskService` and redraws itself — but not for iOS task details, which holds a
//  `@State` snapshot of the task taken when the view opened. Nothing replaced that snapshot, so
//  the chips' highlight kept resolving from the pre-move `statusRole` and the row never moved.
//  A button that sends its request and then visibly does nothing is a button that does not work.
//
//  `TaskService.updateTask` and `completeTask` already return the optimistic task immediately,
//  with no network wait, so the fresh value was there to be had all along.
//
//  Sequencing is preserved exactly as both pickers had it, including ASTRID.md rule 2:
//  completion goes through `completeTask`, never `updateTask(completed:)`, because that is the
//  only path that rolls a repeating task forward.
import Foundation

enum ProjectStateMove {

    /// Perform `plan`, returning the task to render afterwards — or nil when the plan was `.none`.
    ///
    /// The two writers are passed in rather than reached for, so the ordering and the hand-back
    /// can be tested without a live `TaskService`.
    static func apply(
        plan: ProjectColumnMovePlan,
        update: (_ listIds: [String], _ statusRole: String) async throws -> Task,
        complete: (_ completed: Bool) async throws -> Task
    ) async throws -> Task? {
        switch plan {
        case .none:
            return nil
        case .setLists(let ids, let role):
            return try await update(ids, role)
        case .complete(let ids, let role):
            _ = try await update(ids, role)
            // Completion goes through `completeTask`, never `updateTask(completed:)` — that is
            // the only path that rolls a repeating task forward (ASTRID.md rule 2).
            return try await complete(true)
        case .uncomplete(let ids, let role):
            _ = try await complete(false)
            return try await update(ids, role)
        }
    }
}
