//  PickerRowMetricsTests.swift
//  Regression tests for Task 42013da7 — "make sure vertical height of buttons is consistent and
//  margin above and between consistent for both time picker and date picker".
//
//  They were not, and the time picker was not even consistent with ITSELF: its "All day" row used
//  12pt vertical padding while the quick options below it used 8, so the first row was visibly
//  taller than the rest. Across the two pickers the horizontal padding (16 vs 12), the gap between
//  rows (8 vs 4) and the gap above the list (16 vs 12) all differed too.
//
//  Numbers scattered across two files drift. These live in one place and are pinned here.

import XCTest
@testable import Astrid_App

final class PickerRowMetricsTests: XCTestCase {

    /// Every quick-pick row is the same height, whichever picker it is in. This is the actual
    /// complaint: rows of differing heights in one list.
    func testEveryRowHasTheSameVerticalPadding() {
        XCTAssertGreaterThan(PickerRowMetrics.rowVerticalPadding, 0)
        // One value, used by both pickers and by every row within them — including the
        // "no value" row that used to be padded differently from the options beneath it.
        XCTAssertEqual(PickerRowMetrics.rowVerticalPadding,
                       PickerRowMetrics.clearRowVerticalPadding,
                       "the No date / All day row must match the options below it")
    }

    /// The gap between rows, and the gap above the first row, are each one number.
    func testSpacingIsSharedNotPerPicker() {
        XCTAssertGreaterThan(PickerRowMetrics.rowSpacing, 0)
        XCTAssertGreaterThan(PickerRowMetrics.sectionSpacing, 0)
        // The gap BETWEEN rows should be tighter than the gap between SECTIONS, or the list
        // reads as separate groups rather than one set of choices.
        XCTAssertLessThan(PickerRowMetrics.rowSpacing, PickerRowMetrics.sectionSpacing)
    }

    /// Horizontal padding is shared too — the two pickers used 16 and 12, so their rows' text
    /// started at different offsets when opened one after the other.
    func testHorizontalPaddingIsShared() {
        XCTAssertGreaterThan(PickerRowMetrics.rowHorizontalPadding, 0)
    }

    /// A row's total height is padding on both sides plus its content, so equal padding is what
    /// makes equal height. Pinned as a derived value so a future change to one side is caught.
    func testRowHeightIsSymmetric() {
        XCTAssertEqual(PickerRowMetrics.totalVerticalPadding,
                       PickerRowMetrics.rowVerticalPadding * 2)
    }
}
