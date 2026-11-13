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
//  The decision is astrid-core's `nesting` rule (AITD-645): it is answerable without a view, it
//  is the part that goes wrong quietly (a cycle, or a write of null over null), and no client may
//  disagree about it. What stays here is the drag's geometry and the wire spelling of the write.
//  Both platforms call this; neither re-derives it.

import AstridCore
import CoreGraphics
import Foundation

/// Where a drag is currently hovering.
enum DragNestingZone: Equatable {
    /// Over a row — nest the dragged task under it.
    case onRow(String)
    /// On the insertion line between two rows. `above` is the row the line sits directly
    /// above; nil means the line above the very first row.
    case betweenRows(above: String?)
    /// Pulled out to the leading edge — move the dragged task one level out of its parent,
    /// wherever it currently sits. Unlike the other two, this says nothing about the row it
    /// was dropped over.
    case outdent
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

    // MARK: - The decision — astrid-core's `nesting` rule (AITD-645)
    //
    // What a drop MEANS (cycles, a parent it already has, null over null, outdent one level,
    // indent under the previous sibling) is answered by astrid-core, the same function the web,
    // Windows and Android drops ask. These three keep their Swift signatures so the drop
    // handlers and the keyboard bindings did not change; none of them re-derives the rule.

    /// What a drop in this zone should do to the dragged task's parent.
    static func outcome(for zone: DragNestingZone,
                        dragged: PromotableTask,
                        byId: [String: Task]) -> DragNestingOutcome {
        let coreZone: NestingZone
        switch zone {
        case .onRow(let targetId): coreZone = .on(targetId)
        case .betweenRows: coreZone = .line
        case .outdent: coreZone = .outdent
        }
        return ask(coreZone, dragged: dragged, rows: byId.values)
    }

    /// One level out, the outliner convention: a direct subtask reaches top level, a deeper
    /// one lands under its grandparent. The SAME rule the drag's gutter uses, so pulling a task
    /// left and pressing the outdent key cannot mean two different things.
    static func outdent(_ task: PromotableTask, byId: [String: Task]) -> DragNestingOutcome {
        ask(.outdent, dragged: task, rows: byId.values)
    }

    /// The other direction: nest a task under its PREVIOUS SIBLING among `rows` as drawn —
    /// not the row directly above, which may be a deep descendant of something else.
    static func indent(_ task: PromotableTask, in rows: [Task], byId: [String: Task]) -> DragNestingOutcome {
        ask(.indent(rows.map(\.id)), dragged: task, rows: Array(byId.values) + rows)
    }

    /// One question to the core. The rows go as `id` + `parentTaskId` only — all the rule reads —
    /// and the dragged row always goes, as the caller holds it: the core refuses a drop whose
    /// dragged row it was never shown rather than answer `none`.
    private static func ask(_ zone: NestingZone, dragged: PromotableTask,
                            rows: some Sequence<Task>) -> DragNestingOutcome {
        var byId: [String: NestingRow] = [:]
        for row in rows { byId[row.id] = NestingRow(id: row.id, parentTaskId: row.parentTaskId) }
        byId[dragged.id] = NestingRow(id: dragged.id, parentTaskId: dragged.parentTaskId)
        do {
            switch try CoreRules.nesting(zone: zone, draggedId: dragged.id, rows: Array(byId.values)) {
            case .makeSubtask(let parentId): return .makeSubtask(taskId: dragged.id, parentId: parentId)
            case .moveToTopLevel: return .moveToTopLevel(taskId: dragged.id)
            case .reorderOnly: return .reorderOnly(taskId: dragged.id)
            case .none: return .none
            }
        } catch {
            // Every row this sends includes the dragged one, so a refusal is a bug in the request.
            // Doing nothing is the safe drop: no write goes out.
            AppLog.debug("⚠️ [DragNesting] astrid-core refused nesting: \(error)")
            return .none
        }
    }

    /// How tall the "line between rows" band is for a row of this height.
    ///
    /// A fixed 12pt would swallow a short row whole; a fixed fraction would be untappable on
    /// a tall one. This takes the smaller of the two, so the row body always stays the
    /// bigger target and the band is still reachable.
    static func lineBandHeight(rowHeight: CGFloat) -> CGFloat {
        min(12, rowHeight * 0.3)
    }

    /// How wide the leading "pull it out" band is, for a row indented by `indent`.
    ///
    /// It must cover the INDENT GUTTER (task 4eb92ce1). A subtask's gutter is the empty space
    /// its indent creates, and it is the obvious place to drag to — it is the space that
    /// visually means "out of the parent". Measuring the band only from the row's own leading
    /// edge left that gutter meaning nothing, so the gesture everyone tries first was the one
    /// guaranteed to fail.
    ///
    /// `indent` also has to be a floor rather than a cap: four levels in is 72pt, wider than
    /// the flat band ever was, so a fixed width would leave part of a deep row's gutter still
    /// reading as "nest under this row" — the exact opposite of the intent.
    static func outdentBandWidth(rowWidth: CGFloat, indent: CGFloat = 0) -> CGFloat {
        max(min(56, rowWidth * 0.2), indent)
    }

    // A `zone(forDropAt:rowSize:rowId:)` used to live here, inferring which of the three a drop
    // meant from its COORDINATES inside one row-wide target. Both platforms now give each
    // outcome its OWN drop target, so the zone follows from which target received the drop and
    // there is nothing left to infer. Removed rather than left in place: a tested function
    // sitting beside the live rules reads as one of them.
    //
    // Coordinates were the wrong basis twice over. One target can only draw one highlight, so
    // you could not see whether you were about to nest, promote or outdent until after you let
    // go; and `.dropDestination` inside a `List` does not reliably receive the event at all —
    // the row's own handling swallows it (652edb22, 83f45d49).

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
