//  MacSelectedArrowContinuityTests.swift
//  Regression guard for Task AITD-302 — "[mac] selected task arrow overlaps a touch with the row.
//  might need to move right a bit and consider using the same color outline for the border of the
//  selected tasks as in the selected row to show connection and continuity (e.g. the blue
//  outline). apply to all themes."
//
//  Two separate complaints in one report, and they pull in opposite directions:
//
//  1. The notch TOUCHED the row it points at. MacLayoutTests owns that half — the arrow tip is
//     derived from the same constants as the row's trailing edge, and it now clears it.
//  2. The panel was outlined in the neutral hairline while the row it came from wore the accent,
//     so a pop-out that unfolds out of the selected row read as an unrelated grey card resting
//     against it. That is this file: one selection colour, drawn by one call, continuing around
//     the notch instead of stopping at the card's edge.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacSelectedArrowContinuityTests: XCTestCase {

    private func rootSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The body of `taskDetailPopout(_:)` — the card, its border and its arrow.
    private func popoutBody() throws -> String {
        let source = try rootSource()
        guard let start = source.range(of: "private func taskDetailPopout(") else {
            XCTFail("taskDetailPopout() not found — did it move?")
            return ""
        }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    /// ")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - Same outline as the row it points at

    /// The card must ask the SAME question the selected row asks. A hand-picked accent here would
    /// be the same colour today and a different one after any change to the selection styling —
    /// which is precisely the continuity this task is about.
    func testThePanelWearsTheSelectionBorder() throws {
        let body = try popoutBody()
        XCTAssertTrue(body.contains("MacSelectionStyle.borderColor(isSelected: true)"),
                      "The pop-out's border must come from the shared selection style, not a literal colour")
        XCTAssertTrue(body.contains("MacSelectionStyle.selectedWidth"),
                      "…at the selected row's border width, so the two edges match in weight as well as hue")
        XCTAssertFalse(body.contains("stroke(Theme.border"),
                       "The neutral hairline is what made the panel read as an unrelated card")
    }

    /// "Same colour as the selected row" has to be a visible change: the selected edge must
    /// differ from the neutral hairline the panel used to wear, in weight as well as hue.
    func testTheSelectionOutlineIsNotTheNeutralHairline() {
        XCTAssertNotEqual(MacSelectionStyle.borderColor(isSelected: true),
                          MacSelectionStyle.borderColor(isSelected: false))
        XCTAssertNotEqual(MacSelectionStyle.borderColor(isSelected: true), Theme.border)
        XCTAssertGreaterThan(MacSelectionStyle.selectedWidth, MacSelectionStyle.unselectedWidth)
    }

    /// "Apply to all themes" costs nothing as long as the pop-out never decides for itself: it
    /// asks MacSelectionStyle, which resolves Theme.accent, which is themed. A per-theme branch
    /// in the pop-out is how one theme ends up with a border the rest do not have.
    func testThePopoutHasNoPerThemeBorderBranch() throws {
        let body = try popoutBody()
        XCTAssertFalse(body.contains("Theme.Dark."),
                       "The pop-out must not name a single theme's palette — the token is already themed")
        XCTAssertFalse(body.contains("currentThemeMode"),
                       "No theme branching in the pop-out; MacSelectionStyle answers for every theme")
    }

    // MARK: - …and it continues around the notch

    /// The arrow's fill erases the card's border where it overlaps, so without an outline of its
    /// own the border would simply stop for 24 points at the notch — a gap in the very line that
    /// is supposed to join the panel to the row.
    func testTheOutlineContinuesAroundTheArrow() throws {
        let body = try popoutBody()
        XCTAssertTrue(body.contains("MacPopoverArrowEdges"),
                      "The notch needs its own stroked outline or the card's border stops at it")
    }

    /// Stroking the triangle itself would draw its BASE too — a vertical accent line across the
    /// card's face where the notch is supposed to merge into it. The edges shape is open on
    /// purpose, so its path has to end at the third point rather than closing.
    func testTheArrowOutlineIsOpenSoItDrawsNoLineAcrossTheCard() {
        let rect = CGRect(x: 0, y: 0, width: 12, height: 24)
        let edges = MacPopoverArrowEdges().path(in: rect)
        let filled = MacPopoverArrow().path(in: rect)

        XCTAssertFalse(edges.isEmpty)
        // The open outline covers only the two diagonals; the closed triangle bounds the same
        // area but carries the base as well. Compare the drawn LENGTH via the element count.
        XCTAssertEqual(edges.boundingRect, filled.boundingRect,
                       "Same geometry — the outline traces the arrow that is actually drawn")

        var edgeElements = 0
        edges.forEach { _ in edgeElements += 1 }
        var filledElements = 0
        filled.forEach { _ in filledElements += 1 }
        XCTAssertLessThan(edgeElements, filledElements,
                          "The outline must be an OPEN path — a closed one strokes the base across the card")
    }

    /// The tip is the point that has to reach the row, and it does — the outline is drawn on the
    /// same shape the fill uses, so the two cannot disagree about where the arrow is.
    func testTheOutlineTracesTheTipThatPointsAtTheRow() {
        let rect = CGRect(x: 0, y: 0, width: 12, height: 24)
        let edges = MacPopoverArrowEdges().path(in: rect)
        XCTAssertEqual(edges.boundingRect.minX, rect.minX, accuracy: 0.001,
                       "The outline must reach the tip, not stop short of it")
        XCTAssertEqual(edges.boundingRect.maxY - edges.boundingRect.minY, rect.height, accuracy: 0.001)
    }
}
#endif
