//  DragNesting.swift
//  What a task drag MEANS, shared by Mac and iOS.
//
//  Astrid tasks nest through `Task.parentTaskId`, and a drag is the natural way to change
//  that. Three zones, three meanings:
//
//    · over a row               → nest under that row
//    · on the line BETWEEN rows → become top level, positioned there
//    · dragged far enough left  → outdent one level
//
//  The rules live here rather than in the drag handlers for the same reason
//  `SubtaskPromotion` does: they are answerable without a view, they are the part that goes
//  wrong quietly (a cycle, or a write of null over null), and Mac and iOS must not disagree
//  about them. Both platforms call this; neither re-derives it.

import Foundation
import CoreGraphics

/// Where a drag is currently hovering.
enum DragNestingZone: Equatable {
    /// Over a row — nest the dragged task under it.
    case onRow(String)
    /// On the insertion line between two rows. `above` is the row the line sits directly
    /// above; nil means the line above the very first row.
    case betweenRows(above: String?)
}

/// What a drop should do to NESTING. Where the task lands in the ORDER is the caller's
/// business — this says only what happens to the parent link.
enum DragNestingOutcome: Equatable {
    /// Nest under a new parent.
    case makeSubtask(taskId: String, parentId: String)
    /// Cut the parent link entirely.
    case moveToTopLevel(taskId: String)
    /// The task is already top level: the drop changes its position and nothing else.
    /// Distinct from `.none` so callers can still reorder without writing a parent.
    case reorderOnly(taskId: String)
    /// Nothing to do — the drop is meaningless (onto itself, into its own descendant, or
    /// onto the parent it already has).
    case none
}

enum DragNesting {

    /// How far left the pointer must travel before a drag counts as an outdent. A drag is
    /// never purely vertical, so a small sideways wobble during a reorder must not silently
    /// re-nest the task.
    static let outdentDragThreshold: CGFloat = 40

    static func isOutdentDrag(horizontalTranslation: CGFloat) -> Bool {
        horizontalTranslation <= -outdentDragThreshold
    }

    /// Whether `parentId` can adopt `childId` without creating a cycle.
    ///
    /// Shared rather than per-platform: a cycle costs you BOTH tasks — the splicing walk
    /// never reaches them, so they vanish from the list with no way back through the UI.
    static func canParent(childId: String, parentId: String, byId: [String: Task]) -> Bool {
        guard childId != parentId else { return false }
        // Walk the proposed parent's ancestors. Reaching the child means the drop would
        // close a loop. The cap matches `subtaskDepth`'s: a corrupt store must not hang.
        var cursor: String? = parentId
        var steps = 0
        while let id = cursor, steps < 100 {
            if id == childId { return false }
            cursor = byId[id]?.parentTaskId
            steps += 1
        }
        return true
    }

    /// What a drop in this zone should do to the dragged task's parent.
    static func outcome(for zone: DragNestingZone,
                        dragged: PromotableTask,
                        byId: [String: Task]) -> DragNestingOutcome {
        switch zone {
        case .onRow(let targetId):
            guard canParent(childId: dragged.id, parentId: targetId, byId: byId) else { return .none }
            // Already there — a write that changes nothing is still a write, and it would
            // round-trip through the Outbox for no reason.
            guard dragged.parentTaskId != targetId else { return .none }
            return .makeSubtask(taskId: dragged.id, parentId: targetId)

        case .betweenRows:
            // The line means "top level, here". For a task that already IS top level there is
            // no parent to clear, so the drop is a pure reorder — never a null over a null.
            guard SubtaskPromotion.canPromoteToTopLevel(dragged) else {
                return .reorderOnly(taskId: dragged.id)
            }
            return .moveToTopLevel(taskId: dragged.id)
        }
    }

    /// One level out, the outliner convention: a direct subtask reaches top level, a deeper
    /// one lands under its grandparent. Repeated drags walk it the rest of the way out.
    /// Jumping a deeply nested task straight to the top from one sideways nudge would be a
    /// surprise that is awkward to undo.
    static func outdent(_ task: PromotableTask, byId: [String: Task]) -> DragNestingOutcome {
        guard let parentId = task.parentTaskId, !parentId.isEmpty else { return .none }
        guard let grandparentId = byId[parentId]?.parentTaskId, !grandparentId.isEmpty else {
            return .moveToTopLevel(taskId: task.id)
        }
        return .makeSubtask(taskId: task.id, parentId: grandparentId)
    }

    /// The other direction: nest a task under its PREVIOUS SIBLING.
    ///
    /// The row directly above is not the right answer — it may be a deep descendant of
    /// something else entirely, and nesting under it would jump the task several levels in.
    /// The previous SIBLING (same parent, earlier in the rendered order) is what an outliner
    /// indents into, and it is what keeps indent and outdent inverses of each other.
    static func indent(_ task: PromotableTask, in rows: [Task], byId: [String: Task]) -> DragNestingOutcome {
        guard let index = rows.firstIndex(where: { $0.id == task.id }), index > 0 else { return .none }
        let parentId = task.parentTaskId?.isEmpty == true ? nil : task.parentTaskId
        // Walk back for the nearest earlier row sharing this task's parent.
        for row in rows[..<index].reversed() {
            let rowParent = row.parentTaskId?.isEmpty == true ? nil : row.parentTaskId
            guard rowParent == parentId else { continue }
            guard canParent(childId: task.id, parentId: row.id, byId: byId) else { return .none }
            return .makeSubtask(taskId: task.id, parentId: row.id)
        }
        return .none
    }

    /// How tall the "line between rows" band is for a row of this height.
    ///
    /// A fixed 12pt would swallow a short row whole; a fixed fraction would be untappable on
    /// a tall one. This takes the smaller of the two, so the row body always stays the
    /// bigger target and the band is still reachable.
    static func lineBandHeight(rowHeight: CGFloat) -> CGFloat {
        min(12, rowHeight * 0.3)
    }

    /// Which zone a drop at `y` within a row of `rowHeight` landed in.
    ///
    /// Deriving the zone from the drop LOCATION means the row itself is the only drop target
    /// — no overlay view sitting on top of every row waiting to swallow a tap, which is a
    /// mistake this codebase has already paid for more than once.
    static func zone(forDropAtY y: CGFloat, rowHeight: CGFloat, rowId: String) -> DragNestingZone {
        y <= lineBandHeight(rowHeight: rowHeight) ? .betweenRows(above: rowId) : .onRow(rowId)
    }

    /// The value to hand `TaskService.updateTask(parentTaskId:)`, or nil when the outcome
    /// needs no parent write at all. Clearing is spelled with the empty string, since nil
    /// there means "leave this field unchanged".
    static func parentIdToWrite(for outcome: DragNestingOutcome) -> String? {
        switch outcome {
        case .makeSubtask(_, let parentId): return parentId
        case .moveToTopLevel: return SubtaskPromotion.clearParentValue
        case .reorderOnly, .none: return nil
        }
    }
}
