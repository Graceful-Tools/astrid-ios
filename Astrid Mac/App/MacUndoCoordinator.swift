//  MacUndoCoordinator.swift
//  Astrid for Mac — executes MacUndoStep against the canonical service layer (Task 9b603be4).
//
//  Registers with the window's real UndoManager, so ⌘Z / Edit ▸ Undo work without a custom
//  menu item stealing ⌘Z from the field editor while the user is typing.

#if os(macOS)
import Foundation
import AppKit

@MainActor
final class MacUndoCoordinator: NSObject {
    static let shared = MacUndoCoordinator()

    /// The window's undo manager, handed over by MacRootView (`@Environment(\.undoManager)`).
    weak var undoManager: UndoManager?

    /// The environment value can be nil (a scene without a hosting window yet, a torn-off task
    /// window). Falling back to the key/main window's manager means a change is never silently
    /// unrecorded — an undo stack that only sometimes exists is worse than none.
    var resolvedUndoManager: UndoManager? {
        undoManager ?? NSApp?.keyWindow?.undoManager ?? NSApp?.mainWindow?.undoManager
    }

    /// Record a change the user just made. Registering the REVERSE means ⌘Z writes `backward`;
    /// performing that undo registers the step again, so ⌘⇧Z redoes it.
    func record(_ step: MacUndoStep) {
        guard let undoManager = resolvedUndoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.undo(step) }
        }
        undoManager.setActionName(step.actionName)
    }

    /// Apply a step's reversal, then register the step's inverse so redo works.
    private func undo(_ step: MacUndoStep) {
        apply(step.backward, named: step.actionName)
        record(step.inverted)
    }

    /// Snapshot the tasks about to be deleted, INCLUDING the subtasks that go with a parent —
    /// the server cascades those, and an undo that dropped them would restore half the work.
    func deletionSnapshots(for tasks: [Task], allTasks: [Task]) -> [MacUndo.Snapshot] {
        var byId: [String: MacUndo.Snapshot] = [:]
        for t in tasks {
            byId[t.id] = Self.snapshot(t)
            for child in allTasks where child.parentTaskId == t.id {
                byId[child.id] = Self.snapshot(child)
            }
        }
        return MacUndo.recreationOrder(Array(byId.values))
    }

    static func snapshot(_ t: Task) -> MacUndo.Snapshot {
        MacUndo.Snapshot(id: t.id, title: t.title, notes: t.description,
                         listIds: t.listIds ?? [], priority: t.priority.rawValue,
                         dueDateTime: t.dueDateTime, isAllDay: t.isAllDay,
                         assigneeId: t.assigneeId, parentTaskId: t.parentTaskId,
                         repeating: t.repeating, repeatingData: t.repeatingData)
    }

    // MARK: execution

    private func apply(_ action: MacUndoAction, named name: String) {
        let service = TaskService.shared
        switch action {
        case .setCompleted(let byId):
            for (id, completed) in byId {
                guard let task = service.tasks.first(where: { $0.id == id }) else { continue }
                guard task.completed != completed else { continue }
                MacActions.perform(name) {
                    _ = try await service.completeTask(id: id, completed: completed, task: task)
                }
            }

        case .setLists(let byId):
            for (id, listIds) in byId {
                guard let task = service.tasks.first(where: { $0.id == id }) else { continue }
                MacActions.perform(name) {
                    _ = try await service.updateTask(taskId: id, listIds: listIds, task: task)
                }
            }

        case .delete(let snapshots):
            for snap in snapshots {
                guard let task = service.tasks.first(where: { $0.id == snap.id }) else { continue }
                MacActions.perform(name) { try await service.deleteTask(id: snap.id, task: task) }
            }

        case .recreate(let snapshots):
            // Sequential, parents first: a subtask needs its parent's NEW id, which only exists
            // once the parent has been re-created.
            MacActions.perform(name) {
                var newIds: [String: String] = [:]
                for snap in MacUndo.recreationOrder(snapshots) {
                    let parent = snap.parentTaskId.flatMap { newIds[$0] ?? $0 }
                    // createTask takes whenDate/whenTime, not dueDateTime: an all-day task
                    // carries no time, a timed one repeats the same instant in both.
                    let created = try await service.createTask(
                        listIds: snap.listIds, title: snap.title,
                        description: snap.notes, priority: snap.priority,
                        whenDate: snap.dueDateTime,
                        whenTime: snap.isAllDay ? nil : snap.dueDateTime,
                        assigneeId: snap.assigneeId,
                        repeating: snap.repeating?.rawValue, repeatingData: snap.repeatingData,
                        parentTaskId: parent)
                    newIds[snap.id] = created.id
                }
            }
        }
    }
}
#endif
