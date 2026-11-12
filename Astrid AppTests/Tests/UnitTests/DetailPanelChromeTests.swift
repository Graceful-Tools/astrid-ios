//  DetailPanelChromeTests.swift
//  Regression guard for AITD-607 — "[design] Task details open out of the selected row, with the
//  selection outline, on iOS" (register DS7 in astrid-core `design/README.md`).
//
//  The Mac and web panels wear the selected row's outline, point an arrow at that row, and open
//  over `motion.panel`. The iPad panel had a neutral shadowed card, slid in from the screen edge on
//  its own spring, and the arrow hung off the row instead. These pin the iPad to the tokens.

import XCTest
@testable import Astrid_App

final class DetailPanelChromeTests: XCTestCase {

    /// `size.comfortable.selection-outline` — the same width the selected iPad row strokes, so the
    /// panel and the row read as one shape.
    func testOutlineIsTheComfortableSelectionOutlineToken() {
        XCTAssertEqual(DetailPanelChrome.selectionOutlineWidth, 2.5)
        XCTAssertEqual(TaskRowView.selectedBorderWidth, DetailPanelChrome.selectionOutlineWidth,
                       "The row and the panel wear one outline (AITD-607)")
    }

    /// `motion.panel` 300 ms ease-out to open; `motion.fast` 150 ms for the arrow following the row.
    func testMotionComesFromTheTokens() {
        XCTAssertEqual(DetailPanelChrome.panelDuration, 0.30, accuracy: 0.0001)
        XCTAssertEqual(DetailPanelChrome.arrowFollowDuration, 0.15, accuracy: 0.0001)
    }

    /// The arrow aims at the row, converted through the panel's own origin.
    func testArrowPointsAtTheRowInPanelCoordinates() {
        let y = DetailPanelChrome.arrowLocalY(rowMidY: 400, panelOriginY: 100, panelHeight: 800)
        XCTAssertEqual(y, 300)
    }

    /// A row above or below the panel clamps the arrow inside it, so it still touches the card.
    func testArrowClampsInsideThePanel() {
        XCTAssertEqual(DetailPanelChrome.arrowLocalY(rowMidY: 0, panelOriginY: 100, panelHeight: 800), 28)
        XCTAssertEqual(DetailPanelChrome.arrowLocalY(rowMidY: 5000, panelOriginY: 100, panelHeight: 800), 772)
    }

    /// No measured row (scrolled out of the list): centre it rather than point at nothing.
    func testArrowCentresWithoutARow() {
        XCTAssertEqual(DetailPanelChrome.arrowLocalY(rowMidY: nil, panelOriginY: 100, panelHeight: 800), 400)
    }

    /// The reporter forgets a row only if it is still the one it holds, so a row leaving the screen
    /// after the next one was selected does not erase the new row's position.
    @MainActor
    func testReporterClearsOnlyTheRowItHolds() {
        let reporter = SelectedRowReporter()
        reporter.report(taskId: "a", midY: 120)
        reporter.report(taskId: "b", midY: 300)
        reporter.clear(taskId: "a")
        XCTAssertEqual(reporter.midY, 300)
        reporter.clear(taskId: "b")
        XCTAssertNil(reporter.midY)
    }

    // MARK: - AITD-627 — "Arrow pointing at task details should be same color as task details
    // background in all themes"

    /// The arrow is filled with the details face, not the panel's base colour. In Ocean the face is
    /// cyan washed with white, so a base-cyan arrow read as a dark wedge beside a near-white card.
    func testArrowFillIsTheDetailsSurfaceInEveryTheme_AITD627() {
        for theme in [ThemeMode.ocean, .light, .dark] {
            XCTAssertEqual(DetailPanelChrome.arrowFill(theme: theme), TaskDetailsSurface(theme: theme),
                           "Arrow and details face disagree in \(theme) (AITD-627)")
        }
    }

    /// Ocean's face is the washed cyan the details view always drew; Light and Dark are their base.
    func testOceanSurfaceCarriesTheWhiteWash_AITD627() {
        XCTAssertEqual(TaskDetailsSurface(theme: .ocean).whiteWash, 0.8, accuracy: 0.0001)
        XCTAssertEqual(TaskDetailsSurface(theme: .light).whiteWash, 0)
        XCTAssertEqual(TaskDetailsSurface(theme: .dark).whiteWash, 0)
    }

    /// Auto is resolved before it gets here; if it slips through it reads as Light, as before.
    func testUnresolvedAutoFallsBackToLight_AITD627() {
        XCTAssertEqual(TaskDetailsSurface(theme: .auto), TaskDetailsSurface(theme: .light))
    }
}
