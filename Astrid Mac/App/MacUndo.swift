//  MacUndo.swift
//  Astrid for Mac — ⌘Z for complete / move / delete (Task 9b603be4).
//
//  macOS users expect ⌘Z to put back whatever the last action took away; the Mac target
//  registered nothing with UndoManager, so it did nothing. Undo runs through the real
//  UndoManager (`@Environment(\.undoManager)`) rather than a custom ⌘Z menu item, so a text
//  field being edited keeps its own field-editor undo and Edit ▸ Undo picks up the action name.
//
//  This file is the PURE half — what a change wrote and what it must write to reverse it.
//  Executing it lives in MacUndoCoordinator; keeping them apart is what makes the inverse testable.

#if os(macOS)
import Foundation

/// A mutation expressed as the state to WRITE (never as a delta), so reversing it is just
/// writing the state that was there before.
enum MacUndoAction: Equatable {
    /// taskId → the completed value to write.
    case setCompleted([String: Bool])
    /// taskId → the listIds to write.
    case setLists([String: [String]])
    /// Delete these tasks.
    case delete(snapshots: [MacUndo.Snapshot])
    /// Re-create these tasks (the reverse of a delete).
    case recreate(snapshots: [MacUndo.Snapshot])
}

/// A change and its reversal, captured together at the call-site — `backward` has to be read
/// BEFORE the write happens, which is exactly why it is not derivable from `forward` alone.
struct MacUndoStep: Equatable {
    let forward: MacUndoAction
    let backward: MacUndoAction

    /// Undoing registers this, so ⌘⇧Z redoes the original change.
    var inverted: MacUndoStep { MacUndoStep(forward: backward, backward: forward) }

    /// What the Edit menu shows after "Undo" / "Redo" — always named for the change the user made.
    var actionName: String { MacUndo.actionName(for: forward) }
}

enum MacUndo {

    /// Everything needed to re-create a deleted task. There is no restore endpoint, so undoing a
    /// delete re-creates from this — a NEW id, and comments do not come back.
    struct Snapshot: Equatable {
        let id: String
        let title: String
        let notes: String
        let listIds: [String]
        let priority: Int
        let dueDateTime: Date?
        let isAllDay: Bool
        let assigneeId: String?
        let parentTaskId: String?
        let repeating: Task.Repeating?
        let repeatingData: CustomRepeatingPattern?
    }

    // MARK: building steps

    /// Completing tasks. `previous` is each task's state BEFORE, so undo restores a task that was
    /// already completed rather than blanket-uncompleting the whole selection.
    static func completeStep(previous: [String: Bool], to completed: Bool) -> MacUndoStep {
        MacUndoStep(forward: .setCompleted(previous.mapValues { _ in completed }),
                    backward: .setCompleted(previous))
    }

    /// Moving tasks to one list. `previous` is each task's own original listIds, so a shared
    /// destination does not collapse three different origins into one on undo.
    static func moveStep(previous: [String: [String]], to listId: String) -> MacUndoStep {
        MacUndoStep(forward: .setLists(previous.mapValues { _ in [listId] }),
                    backward: .setLists(previous))
    }

    /// Deleting tasks. Snapshots are read before the delete; undo re-creates from them.
    static func deleteStep(snapshots: [Snapshot]) -> MacUndoStep {
        MacUndoStep(forward: .delete(snapshots: snapshots),
                    backward: .recreate(snapshots: snapshots))
    }

    /// Parents before children — re-creating a subtask needs its parent to exist first.
    static func recreationOrder(_ snapshots: [Snapshot]) -> [Snapshot] {
        snapshots.filter { $0.parentTaskId == nil } + snapshots.filter { $0.parentTaskId != nil }
    }

    // MARK: presentation

    /// Recreate borrows the delete name so the menu never reads "Undo Recreate Task".
    static func actionName(for action: MacUndoAction) -> String {
        switch action {
        case .setCompleted:      return NSLocalizedString("mac.undo.complete", comment: "")
        case .setLists:          return NSLocalizedString("mac.undo.move", comment: "")
        case .delete, .recreate: return NSLocalizedString("mac.undo.delete", comment: "")
        }
    }
}

/// Edit-menu presentation + routing for ⌘Z (Task 9b603be4). Pure, so the routing rule — the
/// field editor wins while you are typing — is testable without a window.
enum MacUndoMenu {
    enum Verb { case undo, redo }
    enum Target { case fieldEditor, stack, none }

    /// "Undo" on its own when nothing is undoable, "Undo Complete Task" when something is.
    static func title(verb: Verb, actionName: String?) -> String {
        let base = NSLocalizedString(verb == .undo ? "actions.undo" : "actions.redo", comment: "")
        guard let name = actionName, !name.isEmpty else { return base }
        return "\(base) \(name)"
    }

    /// The task stack wins whenever it has something in it, and a focused text field's editor
    /// picks up the rest. The other order — field editor first — reads better on paper but cannot
    /// be shown honestly in the menu: the title is built while SwiftUI assembles the menu bar,
    /// where asking AppKit who is focused wedges the app, so a field-first rule would let the item
    /// say "Undo Complete Task" and then undo your typing instead. Undoing a completion is also
    /// the change worth protecting; retyping a few characters is not.
    static func target(fieldEditorCanUndo: Bool, stackCanUndo: Bool) -> Target {
        if stackCanUndo { return .stack }
        return fieldEditorCanUndo ? .fieldEditor : .none
    }
}
#endif
