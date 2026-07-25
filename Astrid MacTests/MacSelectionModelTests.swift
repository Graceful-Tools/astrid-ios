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
