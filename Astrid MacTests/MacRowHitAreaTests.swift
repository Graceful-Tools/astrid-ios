//  MacRowHitAreaTests.swift
//  Regression tests for Task b556c6a9 — "[mac] click target on task rows doesn't fill the row".
//
//  The selection tap covered only the title block, so the card's padding — 9pt above and below,
//  12pt at each edge, and the whole checkbox column — did nothing when clicked. The paddings now
//  live INSIDE the two columns, which is what these values describe.

import XCTest
@testable import Astrid_Mac

final class MacRowHitAreaTests: XCTestCase {

    /// Every part of the card belongs to one column or the other: leading gutter + checkbox to the
    /// left column, everything else to the content column.
    func testColumnsAccountForTheWholeRowWidth() {
        let width: CGFloat = 400
        let checkbox = MacRowHitArea.checkboxColumnWidth(glyph: MacTaskVisuals.rowCheckboxSize)
        let content = MacRowHitArea.contentColumnWidth(rowWidth: width, glyph: MacTaskVisuals.rowCheckboxSize)
        XCTAssertEqual(checkbox + MacRowHitArea.columnSpacing + content, width, accuracy: 0.01,
                       "A gap between the columns is a strip of row that answers no click")
    }

    /// The vertical padding is part of the hit area, not outside it — clicking near the top or
    /// bottom edge of a row must still select it.
    func testVerticalPaddingIsInsideTheHitArea() {
        XCTAssertGreaterThan(MacRowHitArea.verticalPadding, 0)
        XCTAssertEqual(MacRowHitArea.rowHeight(contentHeight: 40),
                       40 + MacRowHitArea.verticalPadding * 2, accuracy: 0.01)
    }

    /// The checkbox column is wider than the glyph, so the strip around the checkbox selects the
    /// row rather than doing nothing — while the glyph itself keeps completing the task.
    func testCheckboxColumnIsWiderThanTheGlyph() {
        let glyph = MacTaskVisuals.rowCheckboxSize
        XCTAssertGreaterThan(MacRowHitArea.checkboxColumnWidth(glyph: glyph), glyph,
                             "Without a margin, clicks beside the checkbox fall through")
    }

    /// Indent shifts the card but must not shrink the tappable content — a deeply nested subtask
    /// row is no harder to click than a top-level one.
    func testIndentShiftsTheRowWithoutShrinkingTheTarget() {
        let flat = MacRowHitArea.contentColumnWidth(rowWidth: 400, glyph: 18)
        let nested = MacRowHitArea.contentColumnWidth(rowWidth: 400 - MacRowHitArea.indent(level: 2), glyph: 18)
        XCTAssertLessThan(nested, flat)
        XCTAssertGreaterThan(nested, 0)
        XCTAssertEqual(MacRowHitArea.indent(level: 9), MacRowHitArea.indent(level: 4),
                       "Indent is capped so deep nesting cannot squeeze the row away")
    }
}
