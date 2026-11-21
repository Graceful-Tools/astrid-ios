//  MacBoardLayoutTokensTests.swift
//  Regression guard for ADEV-172 — the Mac board reads core's compact board tokens
//  (`layout.compact.board-*`, DS34) instead of typing 250 / 12 / 16 out in `MacLayout`.

import XCTest
@testable import Astrid_Mac

final class MacBoardLayoutTokensTests: XCTestCase {

    func testADEV172_macBoardGeometryIsTheCompactTokens() {
        XCTAssertEqual(MacLayout.boardColumnMinWidth, AstridTokens.Layout.Compact.boardColumnMinWidth)
        XCTAssertEqual(MacLayout.boardColumnSpacing, AstridTokens.Layout.Compact.boardColumnGap)
        XCTAssertEqual(MacLayout.boardPadding, AstridTokens.Layout.Compact.boardPadding)
        // The values core took from the Mac, unchanged by the move.
        XCTAssertEqual(MacLayout.boardMinimumWidth(columnCount: 3), 250 * 3 + 12 * 2 + 16 * 2)
    }

    func testADEV172_emptyColumnArtIsTheCompactToken() {
        XCTAssertEqual(EmptyStateDensity.compact.artSize, AstridTokens.Layout.Compact.emptyArt)
        XCTAssertEqual(EmptyStateDensity.compact.artSize, 96)
    }
}
