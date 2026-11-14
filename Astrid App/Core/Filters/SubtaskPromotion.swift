//  SubtaskPromotion.swift
//  Moving a task out of being a subtask, by dragging it. (Task 2ed0d0de)
//
//  The decision — can this task leave its parent? — is astrid-core's `nesting` rule asked about
//  the line between rows (AITD-621): `rows/nesting.rs` ported this file, and web, Windows and
//  Android ask the same function, so no client offers a promotion another refuses. What stays
//  here is the Swift vocabulary: the drop target's id and the wire spelling of "clear".
//
//  It is asked rather than open-coded because it is the part that goes wrong quietly: offering
//  the target for a task that has no parent, or firing a write that clears an already-null one.

import AstridCore
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

    /// True when the task is nested under another and so has somewhere to move out of — the
    /// core's answer to a drop on the line between rows: `moveToTopLevel` for a subtask,
    /// `reorderOnly` for a task already at the top.
    ///
    /// An EMPTY parent id counts as no parent (the core's `parent_of`): web tests truthiness,
    /// so `""` is falsy there, and a plain `!= nil` would offer the target for a task with
    /// nothing above it.
    static func canPromoteToTopLevel(_ task: PromotableTask?) -> Bool {
        guard let task else { return false }
        let row = NestingRow(id: task.id, parentTaskId: task.parentTaskId)
        do {
            return try CoreRules.nesting(zone: .line, draggedId: task.id, rows: [row]) == .moveToTopLevel
        } catch {
            // The dragged row is always sent, so a refusal is a bug in the request. Not
            // offering the promotion is the safe answer: no write goes out.
            AppLog.debug("⚠️ [SubtaskPromotion] astrid-core refused nesting: \(error)")
            return false
        }
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

    /// The wire value that CLEARS a parent. `PUT /api/v1/tasks/[id]` accepts null or `''`
    /// interchangeably, but the Swift client already spends nil on "leave this field
    /// unchanged" — so `''` is the only spelling left that can say "clear".
    static let clearParentValue = ""

    /// The parent a LOCAL task should show for a given wire value.
    ///
    /// `''` must become nil, not an empty string: `SubtaskSplicing` reads any non-nil parent
    /// as still nested, so an optimistic task carrying `''` would drop out of the top level
    /// until the next refresh — the promotion would look like it failed.
    static func localParentId(forWireValue wire: String) -> String? {
        wire.isEmpty ? nil : wire
    }
}

struct PromotionResult: Equatable {
    let taskId: String
    /// Always nil — this operation exists to clear the parent.
    let parentTaskId: String? = nil

    init(taskId: String) { self.taskId = taskId }
}
