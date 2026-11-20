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
    // ADEV-164: drawn from astrid-core's layers, so these ask for the layers, not a PNG name.

    /// An open task's row shows the unchecked box, beside "Mark as done".
    func testADEV148_OpenTaskShowsTheUncheckedRowCheckbox() {
        XCTAssertEqual(TaskCheckboxAsset.layers(completed: false, repeating: false), ["checkbox-box"])
    }

    /// A done task's row shows the checked box, beside "Mark as to-do".
    func testADEV148_DoneTaskShowsTheCheckedRowCheckbox() {
        XCTAssertEqual(TaskCheckboxAsset.layers(completed: true, repeating: false),
                       ["checkbox-box", "checkbox-check"])
    }

    /// A repeating task's box keeps its arrows, as in the task row.
    func testADEV148_RepeatingTaskKeepsTheRepeatBox() {
        XCTAssertEqual(TaskCheckboxAsset.layers(completed: false, repeating: true), ["checkbox-repeat"])
        XCTAssertEqual(TaskCheckboxAsset.layers(completed: true, repeating: true),
                       ["checkbox-repeat", "checkbox-check"])
    }

    /// The row draws the task row's own art: one view, so it cannot spell the box differently.
    func testADEV148_SameArtAsTheTaskRow() throws {
        let source = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(
            "Astrid App/Views/Components/MarkDoneQuickSetRow.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TaskCheckboxArt("))
    }

    // MARK: - ADEV-164: the checkbox is core's art, tinted with the priority tokens (DS21)

    /// ADEV-164: the three layers are vendored from astrid-core and resolve in the app bundle.
    func testADEV164_CoreLayersResolveInTheBundle() {
        for name in ["checkbox-box", "checkbox-repeat", "checkbox-check"] {
            XCTAssertNotNil(UIImage(named: name), "\(name) is missing — vendor AstridDesign.xcassets")
        }
    }

    /// ADEV-164: none of the 32 fixed-colour PNGs is left to fall back on.
    func testADEV164_NoCheckboxPNGsRemain() {
        for priority in 0...3 {
            for completed in [false, true] {
                for repeating in [false, true] {
                    let old = TaskCheckboxAsset.name(priority: priority, completed: completed, repeating: repeating)
                    XCTAssertNil(UIImage(named: old), "\(old) is still in a catalog")
                }
            }
        }
    }

    /// ADEV-164: the box takes the palette's priority colour — low is the accent, or its dark ink
    /// in Dark — and no priority is the muted text, as on web (`priority-text-none`).
    func testADEV164_TintIsThePalettesPriorityColour() {
        for palette in [AstridTokens.light, AstridTokens.dark, AstridTokens.ocean] {
            XCTAssertEqual(TaskCheckboxAsset.tint(priority: 0, palette: palette), palette.textMuted)
            XCTAssertEqual(TaskCheckboxAsset.tint(priority: 1, palette: palette), palette.priorityLow)
            XCTAssertEqual(TaskCheckboxAsset.tint(priority: 2, palette: palette), palette.priorityMedium)
            XCTAssertEqual(TaskCheckboxAsset.tint(priority: 3, palette: palette), palette.priorityHigh)
            XCTAssertEqual(TaskCheckboxAsset.tint(priority: 9, palette: palette), palette.textMuted)
        }
        XCTAssertNotEqual(TaskCheckboxAsset.tint(priority: 1, palette: AstridTokens.dark),
                          TaskCheckboxAsset.tint(priority: 1, palette: AstridTokens.light))
    }

    // MARK: - ADEV-152: full-size checkbox, contrasting row, readable text, one design

    /// "The checkbox should be full size as in rows": the task row's 34pt control, not 24pt.
    func testADEV152_CheckboxIsTheRowsSize() {
        XCTAssertEqual(MarkDoneQuickSet.checkboxSize, AstridTokens.Size.Comfortable.leadingControl)
        XCTAssertEqual(MarkDoneQuickSet.checkboxSize, 34)
    }

    /// Your own task: no note, just "Mark as done".
    func testADEV152_YourOwnTaskHasNoNote() {
        XCTAssertNil(MarkDoneQuickSet.note(needsConfirmation: false, assigneeLabel: nil))
        XCTAssertNil(MarkDoneQuickSet.note(needsConfirmation: false, assigneeLabel: "Ada"))
    }

    /// Nobody's task: the same row, saying so under the label, instead of "Complete this task?".
    func testADEV152_UnassignedTaskSaysSoUnderTheSameRow() {
        XCTAssertEqual(MarkDoneQuickSet.note(needsConfirmation: true, assigneeLabel: nil),
                       EnglishStrings.text("tasks.confirm_complete_unassigned"))
    }

    /// Someone else's task names them, so the tap is never a blind one (ADEV-70).
    func testADEV152_SomeoneElsesTaskNamesThem() {
        let note = MarkDoneQuickSet.note(needsConfirmation: true, assigneeLabel: "Ada")
        XCTAssertEqual(note, CompletionConfirmation.message(assigneeLabel: "Ada"))
        XCTAssertTrue(note?.contains("Ada") == true)
    }

    /// The row's text and background come from the theme's palette. iOS `Theme.textPrimary` is
    /// the light palette's ink whatever the theme, which is why "Mark as done" read dark-on-dark.
    func testADEV152_RowReadsThePalette() throws {
        let source = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(
            "Astrid App/Views/Components/MarkDoneQuickSetRow.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("Theme.textPrimary"), "fixed light ink on a dark popover")
        XCTAssertTrue(source.contains("@ThemedPalette"))
        XCTAssertTrue(source.contains("palette.textPrimary"))
        XCTAssertTrue(source.contains("palette.bgSecondary"), "the assignee row's surface, for contrast")
    }
}

