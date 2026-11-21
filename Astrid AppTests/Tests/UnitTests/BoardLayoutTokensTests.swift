//  BoardLayoutTokensTests.swift
//  Regression guard for ADEV-172 — "iOS and Mac boards read the board layout tokens instead of
//  typed numbers."
//
//  Core PR #105 took the board's numbers from these views into `layout.comfortable.board-*` and
//  `empty-art` (DS34–DS36). The views now read them from `AstridTokens`, so a change in core
//  `design/tokens.json` reaches the board at the next re-vendor instead of drifting from a copy.
//  The design ratchet (`npm run check:design`) catches a literal coming back; these pin the
//  values that are reachable from outside a view body.

import XCTest
@testable import Astrid_App

final class BoardLayoutTokensTests: XCTestCase {

    func testADEV172_emptyStateArtReadsTheDensityTokens() {
        XCTAssertEqual(EmptyStateDensity.regular.artSize, AstridTokens.Layout.Comfortable.emptyArt)
        XCTAssertEqual(EmptyStateDensity.compact.artSize, AstridTokens.Layout.Compact.emptyArt)
        XCTAssertEqual(EmptyStateDensity.textOnly.artSize, 0)
    }

    func testADEV172_columnCountFloorsAtTheTokenMinimumWidth() {
        let floor = AstridTokens.Layout.Comfortable.boardColumnMinWidth
        XCTAssertEqual(floor, 300, "core's comfortable column floor is iOS's 300 (DS34)")
        XCTAssertEqual(boardColumnsVisible(availableWidth: floor * 3), 3)
        XCTAssertEqual(boardColumnsVisible(availableWidth: floor * 3 - 1), 2)
    }
}
