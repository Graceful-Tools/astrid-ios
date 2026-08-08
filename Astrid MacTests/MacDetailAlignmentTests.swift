//  MacDetailAlignmentTests.swift
//  The Mac task detail's column structure.
//
//  The detail used to lead each field with an 80pt TEXT label — "Priority",
//  "When", "Lists". Three problems at once: the words restated what the control
//  beside them already showed, the labels lined up with nothing above them, and
//  they cost every row a fifth of a 380pt panel.
//
//  iOS has always used an icon in a narrow leading column, with the field's
//  content starting exactly where the task title starts. That is now the Mac's
//  layout, and these tests pin the two alignments it depends on — both of which
//  are arithmetic, and so belong here rather than in a screenshot.

import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacDetailAlignmentTests: XCTestCase {

    /// THE ASK: the field icons sit in the same column as the title row's
    /// checkbox. Same width, so they share a centre line.
    func testFieldIconsShareTheTitleCheckboxColumn() {
        XCTAssertEqual(MacDetailRowMetrics.leadingColumnWidth,
                       MacTaskVisuals.detailCheckboxSize,
                       "the icon column IS the checkbox column — a different width offsets every "
                       + "field icon from the checkbox above it")
    }

    /// THE ASK: the date, the lists and the priority control all start at the
    /// same x as the task title. Both rows are composed from these two
    /// constants, so the only way they can disagree is if one stops using them.
    func testFieldContentStartsWhereTheTitleTextStarts() {
        XCTAssertEqual(MacDetailRowMetrics.contentInset,
                       MacDetailRowMetrics.leadingColumnWidth + MacDetailRowMetrics.columnGap)
    }

    /// The leading column is narrow — an icon, not a word. The 80pt label it
    /// replaced is the thing being guarded against.
    func testTheLeadingColumnIsIconSizedNotLabelSized() {
        XCTAssertLessThan(MacDetailRowMetrics.leadingColumnWidth, 40,
                          "an 80pt text label is what this replaced")
    }

    /// The row-fit arithmetic has to count the icon column, or it will happily
    /// approve a row that overflows by exactly that much. It previously counted
    /// only the Form's own insets and ignored the 80pt label entirely.
    func testRowFitCountsTheLeadingColumn() {
        XCTAssertGreaterThanOrEqual(MacDetailRowFit.rowInsets,
                                    MacDetailRowMetrics.contentInset,
                                    "a row's usable width excludes its leading icon column")
    }

    /// And the When row still fits, with the icon column now honestly counted.
    func testTheWhenRowStillFitsWithTheLeadingColumnCounted() {
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.whenRowMinimums,
                                           in: MacLayout.detailPanelWidth),
                      "needs \(MacDetailRowFit.required(MacDetailRowFit.whenRowMinimums))pt "
                      + "of \(MacLayout.detailPanelWidth)pt")
    }

    func testThePriorityRowStillFitsWithTheLeadingColumnCounted() {
        XCTAssertTrue(MacDetailRowFit.fits(MacDetailRowFit.priorityRowMinimums,
                                           in: MacLayout.detailPanelWidth))
    }

    // MARK: - Type

    /// THE ASK: subtasks read like the description. One token drives both, so
    /// they cannot drift apart the way two inherited defaults did.
    func testSubtasksAndDescriptionShareOneBodyFont() {
        XCTAssertEqual(MacTypography.detailBody,
                       Font.system(size: MacTypography.detailBodySize, weight: .regular))
    }

    /// Body text sits below the detail title in the ramp, and is not the tiny
    /// field-label size.
    func testDetailBodySitsBetweenTheLabelAndTheTitle() {
        XCTAssertGreaterThan(MacTypography.detailBodySize, MacTypography.labelSize)
        XCTAssertLessThan(MacTypography.detailBodySize, MacTypography.detailTitleSize)
    }
}
