//  MarkDoneQuickSetTests.swift
//  ADEV-146: every quick changer ends in "✓ Mark as done" / "✓ Mark as to-do", web's words.

import XCTest
@testable import Astrid_App

final class MarkDoneQuickSetTests: XCTestCase {

    /// ADEV-146: an open task offers to mark it done.
    func testADEV146_OpenTaskSaysMarkAsDone() {
        XCTAssertEqual(MarkDoneQuickSet.labelKey(completed: false), "tasks.mark_as_done")
        XCTAssertEqual(EnglishStrings.text("tasks.mark_as_done"), "Mark as done")
    }

    /// ADEV-146: a done task offers to put it back on the to-do list — not "Mark Incomplete".
    func testADEV146_DoneTaskSaysMarkAsToDo() {
        XCTAssertEqual(MarkDoneQuickSet.labelKey(completed: true), "tasks.mark_as_todo")
        XCTAssertEqual(EnglishStrings.text("tasks.mark_as_todo"), "Mark as to-do")
    }

    /// The key resolves in the running bundle, so the row never draws its own key.
    func testADEV146_LabelsResolve() {
        for completed in [false, true] {
            let key = MarkDoneQuickSet.labelKey(completed: completed)
            XCTAssertNotEqual(MarkDoneQuickSet.label(completed: completed), key)
        }
    }

    /// A check mark both ways — the old row swapped to an undo arrow for a done task.
    func testADEV146_CheckMarkBothWays() {
        XCTAssertEqual(MarkDoneQuickSet.systemImage, "checkmark")
    }
}
