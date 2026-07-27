//  MacUndoCoordinator.swift
//  Astrid for Mac — executes MacUndoStep against the canonical service layer (Task 9b603be4).
//
//  Registers with the window's real UndoManager, so ⌘Z / Edit ▸ Undo work without a custom
//  menu item stealing ⌘Z from the field editor while the user is typing.

#if os(macOS)
import Foundation
import AppKit
import Combine

@MainActor
final class MacUndoCoordinator: NSObject, ObservableObject {
    static let shared = MacUndoCoordinator()

    /// The app OWNS its undo stack rather than borrowing the window's. `@Environment(\.undoManager)`
    /// proved unreliable here — registrations against it never reached Edit ▸ Undo, which stayed
    /// plain "Undo" — and the Edit menu items below drive this stack directly, so ⌘Z is either
    /// wired or the tests fail. An UndoManager (not a hand-rolled array) keeps the grouping,
    /// action names and redo semantics AppKit users expect.
    private let ownStack = UndoManager()

    /// Overridable for tests; nil means the app's own stack.
    var undoManager: UndoManager?

    /// Fired whenever the stack changes so the Edit menu re-renders its titles. Declared by hand:
    /// the synthesized publisher of a @MainActor class cannot satisfy the nonisolated requirement.
    nonisolated let objectWillChange = ObservableObjectPublisher()

    var resolvedUndoManager: UndoManager? { undoManager ?? ownStack }

    override init() {
        super.init()
        // Notification callbacks are a safe place to look at NSApp; the menu-build path is not.
        // NSUndoManagerCheckpoint is deliberately NOT observed: it fires constantly, and turning
        // each one into a menu rebuild (which itself checkpoints) wedges the app at launch — it
        // never finishes loading accessibility.
        for name: NSNotification.Name in [.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
                                          .NSUndoManagerDidCloseUndoGroup,
                                          NSText.didBeginEditingNotification,
                                          NSText.didEndEditingNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    self?.objectWillChange.send()
                }
            }
        }
    }

    // MARK: Edit menu

    var canUndo: Bool { resolvedUndoManager?.canUndo ?? false }
    var canRedo: Bool { resolvedUndoManager?.canRedo ?? false }

    /// Names the task action whenever there is one — which, given the routing rule above, is
    /// exactly what ⌘Z will do. The title is computed while SwiftUI assembles the menu bar, so it
    /// must not touch NSApp: reading `NSApp.keyWindow` there wedges the app at launch.
    var undoTitle: String { MacUndoMenu.title(verb: .undo, actionName: resolvedUndoManager?.undoActionName) }
    var redoTitle: String { MacUndoMenu.title(verb: .redo, actionName: resolvedUndoManager?.redoActionName) }

    /// ⌘Z while typing belongs to the field editor — that is what every other Mac app does.
    /// Only when the focused field has nothing to undo does the task stack get the keystroke.
    func performUndo() {
        switch MacUndoMenu.target(fieldEditorCanUndo: Self.fieldEditorUndoManager()?.canUndo ?? false,
                                  stackCanUndo: canUndo) {
        case .fieldEditor: Self.fieldEditorUndoManager()?.undo()
        case .stack:       resolvedUndoManager?.undo()
        case .none:        break
        }
    }

    func performRedo() {
        switch MacUndoMenu.target(fieldEditorCanUndo: Self.fieldEditorUndoManager()?.canRedo ?? false,
                                  stackCanUndo: canRedo) {
        case .fieldEditor: Self.fieldEditorUndoManager()?.redo()
        case .stack:       resolvedUndoManager?.redo()
        case .none:        break
        }
    }

    /// The undo manager of the text view currently being edited, if any.
    private static func fieldEditorUndoManager() -> UndoManager? {
        (NSApp?.keyWindow?.firstResponder as? NSText)?.undoManager
            ?? (NSApp?.keyWindow?.firstResponder as? NSTextView)?.undoManager
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
