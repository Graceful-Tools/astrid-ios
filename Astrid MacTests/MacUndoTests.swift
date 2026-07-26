//  MacUndoTests.swift
//  Regression tests for Task 9b603be4 — "[Mac] add Undo (⌘Z) for complete / delete / move".
//
//  The Mac target registered nothing with UndoManager, so ⌘Z did nothing after completing,
//  deleting or moving tasks. These tests pin the pure inverse model: what ⌘Z must put back.

import XCTest
@testable import Astrid_Mac

final class MacUndoTests: XCTestCase {

    private func snapshot(_ id: String, parent: String? = nil) -> MacUndo.Snapshot {
        MacUndo.Snapshot(id: id, title: id.uppercased(), notes: "", listIds: ["l1"], priority: 3,
                         dueDateTime: nil, isAllDay: false, assigneeId: nil, parentTaskId: parent,
                         repeating: nil, repeatingData: nil)
    }

    // MARK: complete

    /// Undoing a completion restores each task's OWN prior state — not a blanket "incomplete".
    /// Bulk-completing a selection that already held a completed task must not un-complete it.
    func testUndoOfCompleteRestoresPerTaskPriorState() {
        let step = MacUndo.completeStep(previous: ["a": false, "b": true], to: true)
        XCTAssertEqual(step.forward, .setCompleted(["a": true, "b": true]))
        XCTAssertEqual(step.backward, .setCompleted(["a": false, "b": true]))
    }

    /// Redo is the undo of the undo — ⌘⇧Z re-applies the original change.
    func testCompleteStepRoundTrips() {
        let step = MacUndo.completeStep(previous: ["a": false], to: true)
        XCTAssertEqual(step.inverted.inverted, step)
        XCTAssertEqual(step.inverted.forward, .setCompleted(["a": false]))
    }

    // MARK: move

    /// Each moved task goes back to its own original lists — a shared destination must not
    /// collapse three different origins into one.
    func testUndoOfMoveRestoresEachTasksOwnLists() {
        let step = MacUndo.moveStep(previous: ["a": ["l1"], "b": ["l2", "l3"]], to: "dest")
        XCTAssertEqual(step.forward, .setLists(["a": ["dest"], "b": ["dest"]]))
        XCTAssertEqual(step.backward, .setLists(["a": ["l1"], "b": ["l2", "l3"]]))
    }

    func testMoveStepRoundTrips() {
        let step = MacUndo.moveStep(previous: ["a": ["l1"]], to: "dest")
        XCTAssertEqual(step.inverted.inverted, step)
    }

    // MARK: delete

    func testUndoOfDeleteRecreatesTheSnapshots() {
        let snap = snapshot("a")
        let step = MacUndo.deleteStep(snapshots: [snap])
        XCTAssertEqual(step.forward, .delete(snapshots: [snap]))
        XCTAssertEqual(step.backward, .recreate(snapshots: [snap]))
        // Redo of an undone delete deletes again.
        XCTAssertEqual(step.inverted.backward, .delete(snapshots: [snap]))
    }

    /// Undoing the delete of a parent brings its children back too — and in an order where the
    /// parent exists before a subtask tries to reference it.
    func testRecreationPutsParentsBeforeSubtasks() {
        let ordered = MacUndo.recreationOrder([snapshot("c", parent: "p"), snapshot("p")])
        XCTAssertEqual(ordered.map(\.id), ["p", "c"], "Parents must be recreated before their subtasks")
    }

    // MARK: presentation

    /// The Edit menu shows "Undo <name>" — the names must be localized, not raw keys.
    func testActionNamesAreLocalized() {
        for (action, key) in [
            (MacUndoAction.setCompleted(["a": true]), "mac.undo.complete"),
            (MacUndoAction.setLists(["a": ["l"]]), "mac.undo.move"),
            (MacUndoAction.delete(snapshots: []), "mac.undo.delete"),
        ] {
            let name = MacUndo.actionName(for: action)
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotEqual(name, key, "\(key) must resolve to a localized string, not the key")
        }
    }

    /// Recreating is presented as the delete it reverses, so the menu never says "Undo Recreate".
    func testRecreateBorrowsTheDeleteName() {
        XCTAssertEqual(MacUndo.actionName(for: .recreate(snapshots: [])),
                       MacUndo.actionName(for: .delete(snapshots: [])))
    }

    // MARK: registration against a real UndoManager

    /// The coordinator must actually arm the undo stack: after recording a change, ⌘Z is enabled
    /// and the Edit menu names it. (XCUITest cannot drive this — it cannot click macOS List rows,
    /// and the `-uiTestSelectRow` harness no longer reaches the shell — so it is pinned here,
    /// against a real UndoManager rather than a stub.)
    @MainActor
    func testRecordingArmsARealUndoManager() {
        let manager = UndoManager()
        let coordinator = MacUndoCoordinator.shared
        let previous = coordinator.undoManager
        defer { coordinator.undoManager = previous }
        coordinator.undoManager = manager

        XCTAssertFalse(manager.canUndo)
        coordinator.record(MacUndo.completeStep(previous: ["a": false], to: true))
        XCTAssertTrue(manager.canUndo, "Completing a task must arm ⌘Z")
        XCTAssertEqual(manager.undoActionName, MacUndo.actionName(for: .setCompleted([:])),
                       "Edit ▸ Undo should name the change")
    }

    /// Undoing re-registers the inverse, so ⌘⇧Z redoes it — an undo you cannot redo is a trap.
    @MainActor
    func testUndoingRegistersTheRedo() {
        let manager = UndoManager()
        let coordinator = MacUndoCoordinator.shared
        let previous = coordinator.undoManager
        defer { coordinator.undoManager = previous }
        coordinator.undoManager = manager

        coordinator.record(MacUndo.moveStep(previous: ["a": ["l1"]], to: "dest"))
        manager.undo()
        XCTAssertTrue(manager.canRedo, "Undo must leave a redo behind")
        XCTAssertEqual(manager.redoActionName, MacUndo.actionName(for: .setLists([:])))
    }

    /// A step is always named for the change the user made, in both directions.
    func testUndoAndRedoShareTheChangeName() {
        let step = MacUndo.deleteStep(snapshots: [snapshot("a")])
        XCTAssertEqual(step.actionName, MacUndo.actionName(for: .delete(snapshots: [])))
        XCTAssertEqual(step.inverted.actionName, step.actionName)
    }
}
