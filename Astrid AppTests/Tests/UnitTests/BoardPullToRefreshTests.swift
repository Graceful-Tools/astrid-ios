import XCTest
@testable import Astrid_App

/// AITD-670 "IOS - add pull to refresh in board views like on list view. But can be within board
/// column": the board had no pull-to-refresh at all — the list's was switched off in board mode,
/// because on the page it bounced the carousel while swiping between columns, and nothing took
/// its place. Each column's own card scroll now owns the pull; the page never does on a board.
final class BoardPullToRefreshTests: XCTestCase {

    func testAITD670_aBoardRefreshesFromItsColumns() {
        XCTAssertEqual(PullToRefreshHost.resolve(showingBoard: true), .boardColumns,
                       "pulling a board column down must refresh, as pulling the list does")
    }

    func testAITD670_theBoardPageNeverOwnsThePull() {
        XCTAssertFalse(PullToRefreshHost.boardColumns.pageIsRefreshable,
                       "a page-level refresh on the board bounced the column carousel")
        XCTAssertTrue(PullToRefreshHost.boardColumns.columnsAreRefreshable)
    }

    func testAITD670_aListStillRefreshesFromThePage() {
        let host = PullToRefreshHost.resolve(showingBoard: false)
        XCTAssertEqual(host, .page)
        XCTAssertTrue(host.pageIsRefreshable)
        XCTAssertFalse(host.columnsAreRefreshable)
    }
}
