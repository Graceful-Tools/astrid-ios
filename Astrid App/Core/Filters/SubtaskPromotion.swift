//  SubtaskPromotion.swift
//  Moving a task out of being a subtask, by dragging it. (Task 2ed0d0de)
//
//  Swift port of astrid-web's `lib/subtask-promotion.ts`. The web module is the canonical
//  spec — if these diverge, one platform will offer to promote a task the other refuses,
//  which is a bug rather than a platform difference. Same shape as `ProjectStatus.swift`,
//  the port of `project-status.ts`.
//
//  The decision lives here rather than in the drag handlers because it is answerable
//  without a view, and it is the part that goes wrong quietly: offering the target for a
//  task that has no parent, or firing a write that clears an already-null parent.

import Foundation

/// The little a promotion decision needs to know about a task. A protocol rather than
/// `Task` itself so the rules can be exercised without building a whole model object —
/// the web counterpart narrows to `Pick<Task, "id"> & { parentTaskId }` for the same reason.
protocol PromotableTask {
    var id: String { get }
    var parentTaskId: String? { get }
}

extension Task: PromotableTask {}

enum SubtaskPromotion {

    /// Drop-zone identifier, shared by the view that renders the target and the handler that
    /// receives the drop. Matches web's `PROMOTE_DROP_TARGET_ID`.
    static let dropTargetId = "promote-to-top-level"

    /// True when the task is nested under another and so has somewhere to move out of.
    ///
    /// An EMPTY parent id counts as no parent: web tests truthiness, so `""` is falsy there,
    /// and a plain `!= nil` here would offer the target for a task with nothing above it.
    static func canPromoteToTopLevel(_ task: PromotableTask?) -> Bool {
        guard let parentId = task?.parentTaskId else { return false }
        return !parentId.isEmpty
    }

    /// Whether the drop target should be on screen.
    ///
    /// Only while a **subtask** is in flight. A permanently visible "unnest" strip would be
    /// noise for the common case — most tasks are not subtasks and most drags are reorders.
    static func shouldShowPromoteTarget(draggedTask: PromotableTask?) -> Bool {
        canPromoteToTopLevel(draggedTask)
    }

    /// What dropping on the target should write, or nil when the drop is a no-op.
    ///
    /// Only the task's link to its PARENT is cut. Its own children travel with it, still
    /// nested under it. Pulling grandchildren up as well is a different product decision, and
    /// doing it silently on a drag would be a surprise that is awkward to undo.
    static func resolvePromotion(_ task: PromotableTask?) -> PromotionResult? {
        guard canPromoteToTopLevel(task), let task else { return nil }
        return PromotionResult(taskId: task.id)
    }
}

struct PromotionResult: Equatable {
    let taskId: String
    /// Always nil — this operation exists to clear the parent.
    let parentTaskId: String? = nil

    init(taskId: String) { self.taskId = taskId }
}
