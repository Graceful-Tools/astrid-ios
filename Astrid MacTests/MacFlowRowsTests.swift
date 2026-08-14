//  MacFlowRowsTests.swift
//  Regression guard for Task 459caa56 — "[mac] list pills should wrap at the pill and not become
//  multiline within the list."
//
//  Two separate faults produced one symptom in `MacListPicker`:
//
//  1. The pills sat in a plain `HStack`, which never wraps. With several lists it just squeezed.
//  2. The pill's own `Text` had no line limit, so the squeeze pushed the NAME onto a second line —
//     a two-line pill, which is what "multiline within the list" describes.
//
//  So the row has to break BETWEEN pills, and a pill has to stay one line. This covers the first
//  half: the pure geometry of where the breaks fall, testable without laying out a view.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacFlowRowsTests: XCTestCase {

    private let spacing: CGFloat = 4

    func testItemsThatFitStayOnOneRow() {
        let rows = MacFlowRows.rows(itemWidths: [50, 50, 50], maxWidth: 200, spacing: spacing)
        XCTAssertEqual(rows, [[0, 1, 2]], "50+4+50+4+50 = 158, well inside 200")
    }

    /// The break itself: the third pill does not fit, so it starts a row rather than squeezing.
    func testAnItemThatDoesNotFitStartsANewRow() {
        let rows = MacFlowRows.rows(itemWidths: [80, 80, 80], maxWidth: 200, spacing: spacing)
        XCTAssertEqual(rows, [[0, 1], [2]], "80+4+80 = 164 fits; adding 4+80 would be 248")
    }

    /// Spacing counts BETWEEN items only. Counting it before the first item would break a row that
    /// exactly fits, which is the off-by-one that makes wrapping look arbitrary.
    func testSpacingIsNotChargedBeforeTheFirstItem() {
        XCTAssertEqual(MacFlowRows.rows(itemWidths: [100, 96], maxWidth: 200, spacing: spacing),
                       [[0, 1]], "100 + 4 + 96 = 200 exactly, so it fits")
        XCTAssertEqual(MacFlowRows.rows(itemWidths: [100, 97], maxWidth: 200, spacing: spacing),
                       [[0], [1]], "one point over is a break")
    }

    /// A list with a very long name is wider than the row on its own. It takes a row of its own and
    /// the layout moves on — the alternative is an empty row, or a loop that never terminates.
    func testAnOversizedItemGetsItsOwnRowAndDoesNotStall() {
        let rows = MacFlowRows.rows(itemWidths: [500, 50], maxWidth: 200, spacing: spacing)
        XCTAssertEqual(rows, [[0], [1]])
        XCTAssertEqual(MacFlowRows.rows(itemWidths: [500, 500], maxWidth: 200, spacing: spacing),
                       [[0], [1]])
    }

    func testNoItemsMeansNoRows() {
        XCTAssertTrue(MacFlowRows.rows(itemWidths: [], maxWidth: 200, spacing: spacing).isEmpty)
    }

    /// A width that has not been measured yet (0 or negative proposal) must not throw everything
    /// onto one unbounded row or lose items — every item still appears exactly once.
    func testAnUnmeasuredWidthStillPlacesEveryItem() {
        for maxWidth in [CGFloat(0), -1] {
            let rows = MacFlowRows.rows(itemWidths: [50, 50, 50], maxWidth: maxWidth, spacing: spacing)
            XCTAssertEqual(rows.flatMap { $0 }.sorted(), [0, 1, 2],
                           "no item may be dropped at width \(maxWidth)")
        }
    }

    /// Order is preserved — pills follow the order the task lists them in.
    func testOrderIsPreserved() {
        let rows = MacFlowRows.rows(itemWidths: [80, 80, 80, 80], maxWidth: 200, spacing: spacing)
        XCTAssertEqual(rows.flatMap { $0 }, [0, 1, 2, 3])
    }

    // MARK: - The second half: a pill stays one line

    func testThePillTextIsLimitedToOneLine() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid Mac/Views/MacListPicker.swift"),
            encoding: .utf8)
        let chips = try XCTUnwrap(source.components(separatedBy: "private var chips").last)
        XCTAssertTrue(chips.contains("lineLimit(1)"),
                      "a pill must not wrap its own name onto a second line")
        XCTAssertTrue(chips.contains("MacFlowLayout") || chips.contains("MacFlowRows"),
                      "the pills must sit in the wrapping layout, not a plain HStack")
    }
}
#endif
