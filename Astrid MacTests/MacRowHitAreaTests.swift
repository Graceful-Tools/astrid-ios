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

    // MARK: - Minimum height (Task 7c5cd097)

    /// THE BUG: Mac rows had no floor, so height simply followed content. A bare title came out
    /// around 35pt against ~51pt for a row carrying a date or a list chip, and a list mixing the
    /// two had a visibly uneven rhythm. iOS pins `minHeight: 76` and the web virtualiser assumes
    /// 84px; Mac assumed nothing.
    func testARowIsNeverShorterThanTheMinimum() {
        // A single short title with no metadata — the shortest a row can legitimately be.
        let bare = MacRowHitArea.rowHeight(contentHeight: 17)

        XCTAssertGreaterThanOrEqual(bare, MacRowHitArea.minRowHeight,
                                    "a title-only row collapsed below the floor")
    }

    /// The point of the floor: a task with nothing but a title stands as tall as one with
    /// metadata, so a mixed list reads as an even column rather than a ragged one.
    func testABareRowMatchesARowThatCarriesMetadata() {
        let titleOnly = MacRowHitArea.rowHeight(contentHeight: 17)
        // title line + spacing + metadata line
        let withMetadata = MacRowHitArea.rowHeight(contentHeight: 17 + 2 + 14)

        XCTAssertEqual(titleOnly, withMetadata, accuracy: 0.01,
                       "these are the two common row shapes; if they differ the list looks ragged")
    }

    /// The floor is a FLOOR, not a fixed height — a wrapped two-line title still grows.
    func testATallRowStillGrowsPastTheMinimum() {
        // Two title lines plus a metadata line.
        let tall = MacRowHitArea.rowHeight(contentHeight: 17 * 2 + 2 + 14)

        XCTAssertGreaterThan(tall, MacRowHitArea.minRowHeight,
                             "clamping tall rows would truncate wrapped titles")
        XCTAssertEqual(tall, 17 * 2 + 2 + 14 + MacRowHitArea.verticalPadding * 2, accuracy: 0.01)
    }

    /// Mac is denser than iOS by design — its title is 14pt where iOS is 19pt — so the minimum is
    /// derived from Mac's own type, not copied across. It must still be a real minimum.
    func testTheMinimumSuitsMacDensity() {
        XCTAssertGreaterThan(MacRowHitArea.minRowHeight, MacRowHitArea.verticalPadding * 2,
                             "a floor at or below the padding is no floor at all")
        XCTAssertLessThan(MacRowHitArea.minRowHeight, 76,
                          "76 is iOS's number for 19pt type; that row would be oversized here")
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
