//  TaskBlockers.swift
//  "Waiting on" — the tasks a task is blocked by (AITD-429 on iOS, AITD-430 on the Mac; web's
//  AWTD-1002). Spec of record: astrid-web docs/specs/TASK_BLOCKING_DEPENDENCIES.md.
//
//  The rules here are web's, copied rather than re-decided — `showsTaskBlockers` in
//  lib/task-detail-project-state.ts and `rankBlockerCandidates` in lib/task-dependencies.ts —
//  and stated once in Core so the phone and the Mac ask the same question. The copy says
//  "waiting on"; the wire says "blocker".
//
//  What is deliberately NOT here: status moves. Adding a blocker to a Ready task moves it to
//  Waiting, and completing the last one moves it back — the server does both and sends the
//  result as `task_updated`. A client that wrote `statusRole` itself would race it.

import Foundation

/// One blocker as `/api/v1/tasks/{id}/blockers` renders it (web `V1Blocker`).
///
/// `hidden` is the permission case: the reader may not see that task, so it carries an id and
/// nothing else. **A hidden blocker still blocks** — count it, render it, never drop it.
struct TaskBlocker: Codable, Identifiable, Equatable {
    let id: String
    let title: String?
    let identifier: String?
    let completed: Bool?
    let hidden: Bool?

    var isHidden: Bool { hidden == true }
    var isCompleted: Bool { completed == true }
}

/// `GET /api/v1/tasks/{id}/blockers` (web `V1BlockersResponse`).
struct TaskBlockersResponse: Codable {
    /// Tasks this one is waiting on.
    let blockedBy: [TaskBlocker]
    /// Tasks waiting on this one.
    let blocks: [TaskBlocker]
    /// Every visible task that waits on this one, transitively. Picking one would be refused
    /// as a cycle, so the picker never offers them.
    let dependentIds: [String]
}

/// `POST` / `DELETE` on the blockers route (web `V1BlockerMutationResponse`).
struct TaskBlockerMutationResponse: Codable {
    let taskId: String
    let blockingTaskId: String
    let blockedBy: [TaskBlocker]
}

/// A task as `/api/v1/search` returns it — only what the picker needs.
struct BlockerSearchHit: Codable, Identifiable, Equatable {
    struct ListRef: Codable, Equatable {
        let id: String
    }

    let id: String
    let title: String
    let completed: Bool?
    let lists: [ListRef]?
}

enum TaskBlockers {

    /// Does the "Waiting on" row appear? (web `showsTaskBlockers`)
    ///
    /// - Not on a project board → hidden. Blocking is a board idea; ask `isTaskInProject`.
    /// - Has blockers → shown, to readers too: the row is a label before it is a control, and
    ///   the controls inside it are what hides for a read-only viewer.
    /// - No blockers → shown only to someone who can edit, because the empty row is the only
    ///   way to add the first one. A reader has nothing to read.
    static func showsRow(isInProject: Bool, isReadOnly: Bool, hasBlockers: Bool) -> Bool {
        guard isInProject else { return false }
        return hasBlockers || !isReadOnly
    }

    /// The picker searches the server from two characters, never the loaded tasks: a local
    /// filter works at a few hundred tasks and silently misses at a few thousand.
    static let minimumQueryLength = 2

    static func shouldSearch(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumQueryLength
    }

    /// What the picker offers, in the order it offers it (web `rankBlockerCandidates`).
    ///
    /// Drops the task itself and `excludedIds` (already linked, or would cycle) and nothing
    /// else, then puts tasks sharing a list with this one first, keeping search order inside
    /// each group. Ranking, not filtering: a cross-board blocker is still one search away.
    static func rankCandidates(hits: [BlockerSearchHit],
                               taskId: String,
                               taskListIds: [String],
                               excludedIds: [String]) -> [BlockerSearchHit] {
        let excluded = Set([taskId] + excludedIds)
        let board = Set(taskListIds)
        let offered = hits.filter { !excluded.contains($0.id) }
        let isNeighbour: (BlockerSearchHit) -> Bool = { hit in
            (hit.lists ?? []).contains { board.contains($0.id) }
        }
        return offered.filter(isNeighbour) + offered.filter { !isNeighbour($0) }
    }

    /// Is this the 409 `dependency_cycle` refusal — the two tasks would wait on each other?
    /// It has its own message (`tasks.waitingOn.cycleError`); every other failure is `addError`.
    static func isCycleRefusal(_ error: Error) -> Bool {
        guard case AstridAPIError.httpError(let status, let message) = error else { return false }
        return status == 409 && message.contains("dependency_cycle")
    }
}
