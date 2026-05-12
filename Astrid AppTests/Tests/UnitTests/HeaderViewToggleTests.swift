import XCTest
@testable import Astrid_App

/// Swift port of `tests/lib/header-view-toggle.test.ts` (8 cases) from
/// astrid-web. Same fixtures, same assertions — keeps the iOS toggle
/// in lockstep with the web toggle for the unified 3-way control
/// behaviour (task a1e5c0ff).
final class HeaderViewToggleTests: XCTestCase {

    private var base: HeaderViewToggleState {
        HeaderViewToggleState(
            isOneColumn: true,
            hasProjectBoard: true,
            chatAvailable: true,
            activeView: .list,
            isSearching: false
        )
    }

    func test_oneCol_board_chat_unifiedThreeWay() {
        let result = getHeaderViewToggle(base)
        XCTAssertEqual(result, HeaderViewToggleConfig(
            segments: [.list, .board, .messages],
            unified: true
        ))
    }

    func test_oneCol_noBoard_chat_unifiedListMessages() {
        var s = base
        s.hasProjectBoard = false
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [.list, .messages],
            unified: true
        ))
    }

    func test_oneCol_board_noChat_unifiedListBoard() {
        var s = base
        s.chatAvailable = false
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [.list, .board],
            unified: true
        ))
    }

    func test_oneCol_noBoard_noChat_empty() {
        var s = base
        s.hasProjectBoard = false
        s.chatAvailable = false
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [],
            unified: false
        ))
    }

    func test_widerLayout_board_legacySplit() {
        var s = base
        s.isOneColumn = false
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [.list, .board],
            unified: false
        ))
    }

    func test_widerLayout_noBoard_listOnlySegments() {
        var s = base
        s.isOneColumn = false
        s.hasProjectBoard = false
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [.list],
            unified: false
        ))
    }

    func test_suppressedWhenActiveViewIsNotList() {
        var s = base
        s.activeView = .settings
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [],
            unified: false
        ))
    }

    func test_suppressedWhenSearching() {
        var s = base
        s.isSearching = true
        XCTAssertEqual(getHeaderViewToggle(s), HeaderViewToggleConfig(
            segments: [],
            unified: false
        ))
    }
}
