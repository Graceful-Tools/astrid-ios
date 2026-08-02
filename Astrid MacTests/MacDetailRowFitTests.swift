//  MacDetailRowFitTests.swift
//  Regression tests for Task 42013da7 — the Mac task detail's content was clipped off its left
//  edge, every line cut mid-word.
//
//  I caused it. Consolidating the fields put three controls in one row — a Due Date toggle, a
//  date+time DatePicker and a repeat Picker — each marked `.fixedSize()`. fixedSize REFUSES to
//  compress, so the row demanded more width than the 380pt panel and the whole Form overflowed.
//
//  A row inside the panel must be able to fit the panel. That is checkable arithmetic, so it is
//  checked here rather than discovered in a screenshot.

import XCTest
@testable import Astrid_Mac

final class MacDetailRowFitTests: XCTestCase {

    /// THE BUG: the When row's controls, at their minimum widths, must fit the panel.
    func testTheWhenRowFitsTheDetailPanel() {
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.whenRowMinimums,
                                           in: MacLayout.detailPanelWidth),
                      "the When row needs \(MacDetailRowFit.required(MacDetailRowFit.whenRowMinimums))pt "
                      + "but the panel is \(MacLayout.detailPanelWidth)pt — it will be clipped")
    }

    /// Same for the priority + assignee row.
    func testThePriorityRowFitsTheDetailPanel() {
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.priorityRowMinimums,
                                           in: MacLayout.detailPanelWidth))
    }

    /// The arithmetic itself: widths plus the gaps between them, plus the row's own insets.
    func testRequiredWidthCountsSpacingAndInsets() {
        let two = MacDetailRowFit.required([100, 100])
        let one = MacDetailRowFit.required([100])
        XCTAssertGreaterThan(two, one * 2 - MacDetailRowFit.rowInsets,
                             "a second control adds its width AND a gap")
    }

    /// A row that genuinely cannot fit must be reported as not fitting — otherwise the guard is
    /// decorative and the next over-wide row ships the same way this one did.
    func testAnOverWideRowIsCaught() {
        XCTAssertFalse(MacDetailRowFit.fits([300, 300], in: MacLayout.detailPanelWidth))
    }
}
