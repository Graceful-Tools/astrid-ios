//  MarkDoneQuickSetTests.swift
//  ADEV-146: every quick changer ends in "✓ Mark as done" / "✓ Mark as to-do", web's words.

import UIKit
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

    // MARK: - ADEV-148: the task row's own checkbox, unchecked or checked

    /// An open task's row shows the unchecked box in its priority colour, beside "Mark as done".
    func testADEV148_OpenTaskShowsTheUncheckedRowCheckbox() {
        XCTAssertEqual(MarkDoneQuickSet.checkboxAssetName(completed: false, priority: 2, repeating: false),
                       "check_box_2")
    }

    /// A done task's row shows the checked box, beside "Mark as to-do".
    func testADEV148_DoneTaskShowsTheCheckedRowCheckbox() {
        XCTAssertEqual(MarkDoneQuickSet.checkboxAssetName(completed: true, priority: 3, repeating: false),
                       "check_box_checked_3")
    }

    /// A repeating task's box keeps its arrows, as in the task row.
    func testADEV148_RepeatingTaskKeepsTheRepeatBox() {
        XCTAssertEqual(MarkDoneQuickSet.checkboxAssetName(completed: false, priority: 0, repeating: true),
                       "check_box_repeat_0")
    }

    /// The row and the task row cannot spell the box differently: both use one rule.
    func testADEV148_SameAssetAsTheTaskRow() {
        for priority in 0...3 {
            for completed in [false, true] {
                for repeating in [false, true] {
                    XCTAssertEqual(
                        MarkDoneQuickSet.checkboxAssetName(completed: completed, priority: priority,
                                                           repeating: repeating),
                        TaskCheckboxAsset.name(priority: priority, completed: completed, repeating: repeating))
                    XCTAssertNotNil(UIImage(named: TaskCheckboxAsset.name(priority: priority, completed: completed,
                                                                          repeating: repeating)))
                }
            }
        }
    }
}
