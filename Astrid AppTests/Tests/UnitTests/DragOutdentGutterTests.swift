//  DragOutdentGutterTests.swift
//  Regression for task 4eb92ce1 — a subtask could not be dragged out to top level.
//
//  Outdenting by drag was implemented and tested, but the band that means "pull it out" was
//  measured from the row's own leading edge — and a subtask row starts AFTER its indent. The
//  empty gutter to the left of a subtask, which is the space that visually means "out of the
//  parent" and the obvious place to drag to, sat outside every drop target.
//
//  Two things follow, and both are pinned here:
//
//    · a drop in the gutter must mean outdent, not "nest under this row"
//    · the band must be at least as wide as the indent, or a deep row's gutter is still
//      partly un-hittable (four levels in is 64pt, wider than the flat 56pt band ever was)

import XCTest
import CoreGraphics
@testable import Astrid_App

final class DragOutdentGutterTests: XCTestCase {

    /// A wide row, as on iPad — where this was reported, because there is far more empty
    /// space around the list to drag into.
    private let wideRow = CGSize(width: 900, height: 60)

    /// One level in: 8pt base + 16pt per level.
    private let oneLevelIndent: CGFloat = 24
    /// The capped maximum, four levels deep — wider than the old flat band.
    private let deepIndent: CGFloat = 72

    // MARK: - The bug

    /// The gutter beside a subtask is the gesture everyone tries first. It has to work.
    func testADropInTheIndentGutterOutdents() {
        XCTAssertEqual(DragNesting.zone(forDropAt: CGPoint(x: 12, y: 30),
                                        rowSize: wideRow, indent: oneLevelIndent, rowId: "c"),
                       .outdent)
    }

    /// Four levels deep the indent is wider than the old 56pt band, so a drop at 64pt used to
    /// land in the gutter and still read as "nest under this row" — the exact opposite.
    func testADeepRowsGutterOutdentsAllTheWayAcross() {
        XCTAssertEqual(DragNesting.zone(forDropAt: CGPoint(x: 64, y: 30),
                                        rowSize: wideRow, indent: deepIndent, rowId: "c"),
                       .outdent)
    }

    /// The band never shrinks below the hittable minimum, however shallow the row.
    func testATopLevelRowKeepsTheOrdinaryBand() {
        XCTAssertEqual(DragNesting.zone(forDropAt: CGPoint(x: 4, y: 30),
                                        rowSize: wideRow, indent: 0, rowId: "c"),
                       .outdent)
    }

    // MARK: - What must not change

    /// The row body still has to be the biggest target — a wider band must not swallow the
    /// row and make nesting impossible.
    func testTheRowBodyStillNestsUnderIt() {
        XCTAssertEqual(DragNesting.zone(forDropAt: CGPoint(x: 400, y: 30),
                                        rowSize: wideRow, indent: deepIndent, rowId: "c"),
                       .onRow("c"))
        XCTAssertLessThan(DragNesting.outdentBandWidth(rowWidth: wideRow.width, indent: deepIndent),
                          wideRow.width / 2,
                          "The band must never take half the row")
    }

    /// The line above still wins in the top-left corner, at any indent — it is the more
    /// specific statement of intent.
    func testTheLineStillWinsInTheTopLeftCorner() {
        XCTAssertEqual(DragNesting.zone(forDropAt: CGPoint(x: 4, y: 2),
                                        rowSize: wideRow, indent: deepIndent, rowId: "c"),
                       .betweenRows(above: "c"))
    }

    /// The band widens to cover the indent and never narrows below the old value, so no drop
    /// that outdented before stops outdenting now.
    func testTheBandCoversTheIndentAndNeverShrinks() {
        for indent in stride(from: CGFloat(0), through: 200, by: 8) {
            let band = DragNesting.outdentBandWidth(rowWidth: wideRow.width, indent: indent)
            XCTAssertGreaterThanOrEqual(band, indent, "Gutter at indent \(indent) must be reachable")
            XCTAssertGreaterThanOrEqual(band, DragNesting.outdentDragThreshold,
                                        "Never narrower than the drag threshold, at indent \(indent)")
        }
    }
}
