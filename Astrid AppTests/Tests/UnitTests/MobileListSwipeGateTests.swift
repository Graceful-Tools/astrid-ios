import XCTest
@testable import Astrid_App

/// Swift port of `tests/hooks/mobile-list-swipe-gate.test.ts` (5 cases).
/// Pins iOS behavior to the same rules as the web's mobile swipe gate
/// so both platforms suppress sidebar swipes in board mode identically.
final class MobileListSwipeGateTests: XCTestCase {

    private var base: MobileListSwipeGateState {
        MobileListSwipeGateState(
            isMobile: true,
            mobileView: "list",
            showMobileSidebar: false,
            isBoardMode: false
        )
    }

    func test_allowsBodySwipeOnMobileListView() {
        XCTAssertTrue(shouldHandleMobileListSwipe(base))
    }

    func test_blocksBodySwipeWhenInBoardMode() {
        var s = base
        s.isBoardMode = true
        XCTAssertFalse(shouldHandleMobileListSwipe(s),
                       "Column carousel owns horizontal gesture in board mode")
    }

    func test_blocksBodySwipeWhenSidebarOpen() {
        var s = base
        s.showMobileSidebar = true
        XCTAssertFalse(shouldHandleMobileListSwipe(s))
    }

    func test_blocksBodySwipeWhenNotOnListView() {
        var s = base
        s.mobileView = "task"
        XCTAssertFalse(shouldHandleMobileListSwipe(s))
    }

    func test_blocksBodySwipeOnDesktop() {
        var s = base
        s.isMobile = false
        XCTAssertFalse(shouldHandleMobileListSwipe(s))
    }
}
