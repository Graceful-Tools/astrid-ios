//  DragOutdentGutterTests.swift
//  Regression for task 4eb92ce1 — a subtask could not be dragged out to top level.
//
//  Two things were wrong, and this file covers the one that is a shared RULE.
//
//  The design fault was that iOS inferred which of the three outcomes a drop meant from its
//  coordinates inside a single row-wide target. One target draws one highlight, so nesting,
//  promoting and outdenting looked identical until after you let go — and `.dropDestination`
//  inside a `List` does not reliably receive the drop at all. Both platforms now give each
//  outcome its own target, the Mac's long-standing design. That part is structure, not
//  arithmetic, and it is not testable without a real drag.
//
//  What IS arithmetic is how wide the outdent band has to be, and that is what broke the
//  gesture people actually try. A subtask row is indented, and the empty gutter that indent
//  creates is where you drag it to pull it out. A band measured only from the row's own
//  leading edge left that gutter meaning nothing.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class DragOutdentGutterTests: XCTestCase {

    /// A wide row, as on iPad — where this was reported, because there is far more empty
    /// space around the list to drag into.
    private let wideWidth: CGFloat = 900

    /// One level in: 16pt per level.
    private let oneLevelIndent: CGFloat = 16
    /// The capped maximum, four levels deep — wider than the old flat band.
    private let deepIndent: CGFloat = 64

    // MARK: - The bug

    /// The band has to reach across the gutter, or the space beside a subtask still means
    /// "nest under this row" — the exact opposite of the gesture being made.
    func testTheBandCoversAOneLevelGutter() {
        XCTAssertGreaterThanOrEqual(
            DragNesting.outdentBandWidth(rowWidth: wideWidth, indent: oneLevelIndent),
            oneLevelIndent)
    }

    /// Four levels deep the indent is 64pt, wider than the old flat 56pt band. Part of a deep
    /// row's gutter would have stayed un-hittable even once it became a target at all.
    func testTheBandCoversTheDeepestGutter() {
        XCTAssertGreaterThanOrEqual(
            DragNesting.outdentBandWidth(rowWidth: wideWidth, indent: deepIndent),
            deepIndent)
    }

    /// Every indent, not just the two named ones — the band must never fall short.
    func testTheBandCoversEveryIndentAndNeverShrinks() {
        for indent in stride(from: CGFloat(0), through: 200, by: 8) {
            let band = DragNesting.outdentBandWidth(rowWidth: wideWidth, indent: indent)
            XCTAssertGreaterThanOrEqual(band, indent, "Gutter at indent \(indent) must be reachable")
            XCTAssertGreaterThanOrEqual(band, DragNesting.outdentDragThreshold,
                                        "Never narrower than the drag threshold, at indent \(indent)")
        }
    }

    // MARK: - What must not change

    /// A row with no indent keeps exactly the band it always had, so no drop that outdented
    /// before stops outdenting now.
    func testATopLevelRowKeepsTheOriginalBand() {
        XCTAssertEqual(DragNesting.outdentBandWidth(rowWidth: wideWidth, indent: 0),
                       DragNesting.outdentBandWidth(rowWidth: wideWidth))
    }

    /// The band must never take over the row: most of it still has to mean "nest under this".
    func testTheBandNeverSwallowsTheRow() {
        for indent in [CGFloat(0), 16, 64] {
            XCTAssertLessThan(DragNesting.outdentBandWidth(rowWidth: wideWidth, indent: indent),
                              wideWidth / 2, "The band must never take half the row")
        }
    }

    /// A narrow row (iPhone, deeply nested) is the case where a fixed band and a wide indent
    /// could collide. The row body must survive there too.
    func testANarrowRowStillHasABodyToDropOn() {
        let narrow: CGFloat = 320
        XCTAssertLessThan(DragNesting.outdentBandWidth(rowWidth: narrow, indent: deepIndent),
                          narrow / 2)
    }
}
