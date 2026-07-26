//  MacSelectionModelTests.swift
//  Astrid for Mac — Tasks 0f695ef2 + a1cb6083: manual selection tap rules, arrow clamping,
//  and the scroll-dismiss threshold.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSelectionModelTests: XCTestCase {

    // MARK: tap rules

    func testPlainTapSelects() {
        XCTAssertEqual(MacSelectionModel.tap(current: [], tapped: "a", commandKey: false), ["a"])
        XCTAssertEqual(MacSelectionModel.tap(current: ["b"], tapped: "a", commandKey: false), ["a"],
                       "Plain tap replaces the selection")
    }

    func testReTapOnSelectedCloses() {
        XCTAssertEqual(MacSelectionModel.tap(current: ["a"], tapped: "a", commandKey: false), [],
                       "Tapping the selected task again deselects (closes the pop-out)")
        // But re-tap within a multi-selection collapses to just that task (plain tap semantics).
        XCTAssertEqual(MacSelectionModel.tap(current: ["a", "b"], tapped: "a", commandKey: false), ["a"])
    }

    func testCommandClickTogglesMembership() {
        XCTAssertEqual(MacSelectionModel.tap(current: ["a"], tapped: "b", commandKey: true), ["a", "b"])
        XCTAssertEqual(MacSelectionModel.tap(current: ["a", "b"], tapped: "b", commandKey: true), ["a"])
        XCTAssertEqual(MacSelectionModel.tap(current: [], tapped: "a", commandKey: true), ["a"])
    }

    // MARK: arrow clamping

    func testArrowClampsInsidePanel() {
        XCTAssertEqual(MacSelectionModel.arrowY(rowMidY: 300, panelHeight: 600), 300, "Points at the row")
        XCTAssertEqual(MacSelectionModel.arrowY(rowMidY: -50, panelHeight: 600), 28, "Clamped to top inset")
        XCTAssertEqual(MacSelectionModel.arrowY(rowMidY: 5000, panelHeight: 600), 572, "Clamped to bottom inset")
        XCTAssertEqual(MacSelectionModel.arrowY(rowMidY: 10, panelHeight: 40), 20, "Tiny panel → centered")
    }

    // MARK: scroll dismissal

    func testScrollThreshold() {
        XCTAssertFalse(MacSelectionModel.scrollShouldClose(delta: 5), "Jitter must not dismiss")
        XCTAssertFalse(MacSelectionModel.scrollShouldClose(delta: -20))
        XCTAssertTrue(MacSelectionModel.scrollShouldClose(delta: 30), "Intentional scroll dismisses")
        XCTAssertTrue(MacSelectionModel.scrollShouldClose(delta: -30))
    }
}
#endif

// MARK: - Arrow aiming (task 69fd1f19 — "the arrow is pointing at the wrong task")

extension MacSelectionModelTests {

    /// The row's midY is measured in the CONTENT space; the arrow lives in the panel's own space.
    /// Converting must go through the panel's measured origin, not a hardcoded inset.
    func testArrowConvertsRowPositionThroughThePanelOrigin() {
        // Row centred at y=300 in content space; panel starts at y=100 → 200 inside the panel.
        XCTAssertEqual(
            MacSelectionModel.arrowLocalY(rowMidY: 300, panelOriginY: 100, panelHeight: 600),
            200, accuracy: 0.001)
    }

    /// A taller/shorter panel shifts its own origin (it is centred): the arrow must follow.
    func testArrowTracksTheRowWhenThePanelOriginMoves() {
        let rowMidY: CGFloat = 420
        let a = MacSelectionModel.arrowLocalY(rowMidY: rowMidY, panelOriginY: 40, panelHeight: 700)
        let b = MacSelectionModel.arrowLocalY(rowMidY: rowMidY, panelOriginY: 140, panelHeight: 500)
        XCTAssertEqual(a, 380, accuracy: 0.001)
        XCTAssertEqual(b, 280, accuracy: 0.001)
        XCTAssertNotEqual(a, b, "A moved panel origin must change where the arrow points")
    }

    func testArrowStaysInsideThePanelForRowsNearTheEdges() {
        // Row above the panel's top → clamped to the inset, still touching the panel.
        XCTAssertEqual(MacSelectionModel.arrowLocalY(rowMidY: 10, panelOriginY: 100, panelHeight: 600),
                       28, accuracy: 0.001)
        // Row below the bottom → clamped to height - inset.
        XCTAssertEqual(MacSelectionModel.arrowLocalY(rowMidY: 5000, panelOriginY: 100, panelHeight: 600),
                       572, accuracy: 0.001)
    }

    func testArrowCentresWhenTheSelectedRowIsNotMeasured() {
        // Selected row scrolled out of the lazy List → no measurement; don't aim at a random row.
        XCTAssertEqual(MacSelectionModel.arrowLocalY(rowMidY: nil, panelOriginY: 100, panelHeight: 600),
                       300, accuracy: 0.001)
    }
}
