//  MacDetailPresentationTests.swift
//  Regression guard for Task 9a98f996 — "[mac] Add ability to expand task details to full screen to
//  the board card task details."
//
//  The board card already offered an "Open full detail…" link. It did nothing: the link selects the
//  task, but the entire detail overlay was gated on NOT being in board view, so on a board there
//  was nothing to show. A dead control, and nothing failed to reveal it.
//
//  The gate is correct for the POP-OUT — that panel floats at the trailing edge and would sit over
//  the columns. It is wrong for FULL SCREEN, which takes the whole content area and has no such
//  conflict. So the rule narrows rather than disappears, and it lives here where it can be asserted
//  instead of inside a view condition.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacDetailPresentationTests: XCTestCase {

    private typealias Mode = MacRootView.ContentMode

    // MARK: - List view: unchanged

    func testListShowsThePopoutForASingleSelection() {
        XCTAssertEqual(MacDetailPresentation.style(mode: .list, selectionCount: 1, fullScreen: false),
                       .popout)
    }

    func testListShowsFullScreenWhenAsked() {
        XCTAssertEqual(MacDetailPresentation.style(mode: .list, selectionCount: 1, fullScreen: true),
                       .fullScreen)
    }

    /// A multi-selection has no single task to detail, and nothing selected has none at all.
    func testNoDetailWithoutExactlyOneTask() {
        for count in [0, 2, 7] {
            XCTAssertEqual(MacDetailPresentation.style(mode: .list, selectionCount: count, fullScreen: false),
                           .none, "\(count) selected is not a detail")
            XCTAssertEqual(MacDetailPresentation.style(mode: .list, selectionCount: count, fullScreen: true),
                           .none, "…full screen does not change that")
        }
    }

    // MARK: - Board: the bug

    /// The fix. Full screen fills the content area, so it has no quarrel with the columns.
    func testBoardShowsFullScreenWhenAsked() {
        XCTAssertEqual(MacDetailPresentation.style(mode: .board, selectionCount: 1, fullScreen: true),
                       .fullScreen,
                       "Expanding a board card to full screen is the whole point of 9a98f996")
    }

    /// …but the pop-out stays suppressed on a board. The card expands INLINE there, which is the
    /// board's own affordance and matches web; a floating panel would cover the columns.
    func testBoardStillSuppressesThePopout() {
        XCTAssertEqual(MacDetailPresentation.style(mode: .board, selectionCount: 1, fullScreen: false),
                       .none)
    }

    // MARK: - Chat

    /// Chat replaces the content area outright — there is nothing to overlay a detail onto.
    func testChatShowsNoDetail() {
        for fullScreen in [true, false] {
            XCTAssertEqual(MacDetailPresentation.style(mode: .chat, selectionCount: 1, fullScreen: fullScreen),
                           .none)
        }
    }

    // MARK: - Layout follows the style, not the flag

    /// Full screen centres in the content area; the pop-out hugs the trailing edge.
    func testAlignmentFollowsTheStyle() {
        XCTAssertEqual(MacDetailPresentation.alignment(for: .fullScreen), .center)
        XCTAssertEqual(MacDetailPresentation.alignment(for: .popout), .trailing)
        XCTAssertEqual(MacDetailPresentation.alignment(for: MacDetailPresentation.Style.none), .trailing)
    }

    // MARK: - The two places offering it must offer the SAME thing

    /// The board card gets the affordance the detail panel already has — same icon, same tooltip.
    /// Two independent inventions of "expand this" is how they drift apart.
    func testBoardCardOffersTheFullScreenControl() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let card = try String(contentsOf: root.appendingPathComponent("Astrid Mac/Views/MacBoardCardEditor.swift"),
                              encoding: .utf8)
        XCTAssertTrue(card.contains("MacDetailPresentation.fullScreenSymbol"),
                      "the board card must use the SHARED glyph, not its own")
        XCTAssertTrue(card.contains("MacDetailPresentation.fullScreenTooltipKey"),
                      "…and the shared tooltip, rather than repeating the key literal")
        XCTAssertTrue(card.contains("detailFullScreen = true"),
                      "the control has to actually turn full screen on, not just open the panel")
    }

    /// The icon pair is the one already in use for full screen, and it changes with the state.
    func testTheSymbolReflectsWhetherWeAreAlreadyFullScreen() {
        XCTAssertEqual(MacDetailPresentation.fullScreenSymbol(isFullScreen: false),
                       "arrow.up.left.and.arrow.down.right")
        XCTAssertEqual(MacDetailPresentation.fullScreenSymbol(isFullScreen: true),
                       "arrow.down.right.and.arrow.up.left")
    }

    func testTheTooltipReflectsWhetherWeAreAlreadyFullScreen() {
        XCTAssertEqual(MacDetailPresentation.fullScreenTooltipKey(isFullScreen: false), "board.full_screen")
        XCTAssertEqual(MacDetailPresentation.fullScreenTooltipKey(isFullScreen: true), "board.exit_full_screen")
    }

    /// The view must ask the rule rather than re-deriving it — the buried condition is what let a
    /// control go dead without anything failing.
    func testTheRootViewAsksTheSharedRule() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Astrid Mac/App/MacRootView.swift"),
                               encoding: .utf8)
        XCTAssertTrue(source.contains("MacDetailPresentation.style("))
        XCTAssertFalse(source.contains("if contentMode != .board, selectedTaskIds.count == 1"),
                       "the hand-rolled condition must be gone, not merely duplicated")
    }
}
#endif
