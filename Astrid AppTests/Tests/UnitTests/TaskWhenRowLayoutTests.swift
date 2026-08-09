//  TaskWhenRowLayoutTests.swift
//  Which controls the task detail's "When" row shows, and how they wrap.
//
//  THE BUG: date, time and repeat were one HStack. Each chip sizes to its own
//  content and refuses to compress, so the row demanded the sum of three fixed
//  controls — more than a phone row has. Whichever came last was pushed off, and
//  once the date grew a weekday ("Wed, Aug 12, 2026") it was the TIME that
//  vanished.
//
//  My first fix put repeat on its own line unconditionally. That cured the
//  squeeze but spent a second line even where there was room for all three —
//  wrapping is a function of the width available, not a decision to take in
//  advance. So the controls are a flat list and FlowRows packs them.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class TaskWhenRowLayoutTests: XCTestCase {

    // MARK: - Which controls are on the row

    /// Stated as its own case because this was a report: the time went missing.
    func testTimeIsPresentForEveryDatedTask() {
        XCTAssertTrue(TaskWhenRowLayout.controls(hasDate: true).contains(.time))
    }

    func testDatedTaskShowsDateTimeAndRepeat() {
        XCTAssertEqual(TaskWhenRowLayout.controls(hasDate: true),
                       [.date, .time, .repeatPattern])
    }

    /// THE BUG: repeat used to be dropped when the repeat was CUSTOM, because
    /// the pattern then had a row of its own. Once the chip started showing the
    /// pattern itself, that exception meant a custom-repeating task displayed no
    /// repeat control at all — no icon, no mention, nothing.
    func testRepeatIsShownForEveryDatedTaskIncludingCustom() {
        XCTAssertTrue(TaskWhenRowLayout.controls(hasDate: true).contains(.repeatPattern),
                      "a custom-repeating task showed no repeat control at all")
    }

    /// With no date there is nothing for a time or repeat to attach to.
    func testUndatedTaskShowsOnlyTheDateControl() {
        XCTAssertEqual(TaskWhenRowLayout.controls(hasDate: false), [.date])
    }

    // MARK: - Wrapping happens only when it must

    /// THE CORRECTION: with room for all three, they stay on ONE line. The
    /// interim fix always pushed repeat down, which wasted a line on a wide panel.
    func testControlsStayOnOneLineWhenThereIsRoom() {
        let rows = FlowRows.rows(itemWidths: [150, 90, 80], maxWidth: 400, spacing: 8)
        XCTAssertEqual(rows.count, 1, "they fit — nothing should wrap")
        XCTAssertEqual(rows.first, [0, 1, 2])
    }

    /// And they wrap when they genuinely do not fit.
    func testTheLastControlWrapsWhenItDoesNotFit() {
        let rows = FlowRows.rows(itemWidths: [150, 90, 80], maxWidth: 260, spacing: 8)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first, [0, 1])
        XCTAssertEqual(rows.last, [2])
    }

    /// The gap only exists BETWEEN items, so it must not be charged to the first
    /// one — counting it there wraps a row that actually fits.
    func testSpacingIsNotChargedToTheFirstItemOnARow() {
        // 150 + 8 + 90 = 248, exactly the width available.
        XCTAssertEqual(FlowRows.rows(itemWidths: [150, 90], maxWidth: 248, spacing: 8).count, 1)
        // One point less and it cannot fit.
        XCTAssertEqual(FlowRows.rows(itemWidths: [150, 90], maxWidth: 247, spacing: 8).count, 2)
    }

    /// A control wider than the row still gets placed. A row that overflows is
    /// bad; a control that disappears is the bug this whole area keeps producing.
    func testAnOverWideControlStillGetsARow() {
        let rows = FlowRows.rows(itemWidths: [500], maxWidth: 200, spacing: 8)
        XCTAssertEqual(rows, [[0]])
    }

    func testEveryControlIsPlacedExactlyOnce() {
        for maxWidth in stride(from: CGFloat(60), through: 600, by: 20) {
            let rows = FlowRows.rows(itemWidths: [150, 90, 80], maxWidth: maxWidth, spacing: 8)
            XCTAssertEqual(rows.flatMap { $0 }.sorted(), [0, 1, 2],
                           "width \(maxWidth) lost or duplicated a control")
        }
    }

    func testNoEmptyRows() {
        for maxWidth in stride(from: CGFloat(20), through: 600, by: 20) {
            for row in FlowRows.rows(itemWidths: [150, 90, 80], maxWidth: maxWidth, spacing: 8) {
                XCTAssertFalse(row.isEmpty)
            }
        }
    }

    func testNoItemsMeansNoRows() {
        XCTAssertTrue(FlowRows.rows(itemWidths: [], maxWidth: 300, spacing: 8).isEmpty)
    }

    // MARK: - Height

    func testHeightCountsRowSpacingBetweenRowsOnly() {
        XCTAssertEqual(FlowRows.height(rowCount: 1, rowHeight: 20, spacing: 8), 20)
        XCTAssertEqual(FlowRows.height(rowCount: 2, rowHeight: 20, spacing: 8), 48)
        XCTAssertEqual(FlowRows.height(rowCount: 0, rowHeight: 20, spacing: 8), 0)
    }
}
