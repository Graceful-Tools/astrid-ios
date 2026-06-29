import XCTest
@testable import Astrid_App

/// On a board, a left-to-right swipe should open the sidebar ONLY when the user
/// is on the left-most column (there's nothing further left to scroll to) —
/// matching how a regular list opens the sidebar. Otherwise the column carousel
/// owns the horizontal pan.
final class BoardSidebarSwipeTests: XCTestCase {

    private func state(
        isMobile: Bool = true, leftmost: Bool = true,
        w: CGFloat = 120, h: CGFloat = 10, predicted: CGFloat = 250
    ) -> BoardSidebarSwipeState {
        BoardSidebarSwipeState(isMobile: isMobile, isAtLeftmostColumn: leftmost,
                               translationWidth: w, translationHeight: h,
                               predictedEndTranslationWidth: predicted)
    }

    func testOpensOnLeftmostRightwardSwipe() {
        XCTAssertTrue(shouldBoardSwipeOpenSidebar(state()))
    }

    func testNotOnInnerColumns() {
        XCTAssertFalse(shouldBoardSwipeOpenSidebar(state(leftmost: false)),
                       "an inner column should page the carousel, not open the sidebar")
    }

    func testNotOnLeftwardSwipe() {
        XCTAssertFalse(shouldBoardSwipeOpenSidebar(state(w: -120, predicted: -250)),
                       "swiping the other way moves to the next column")
    }

    func testNotOnMostlyVerticalSwipe() {
        XCTAssertFalse(shouldBoardSwipeOpenSidebar(state(w: 30, h: 200)),
                       "a vertical scroll must not open the sidebar")
    }

    func testBelowThresholdDoesNotOpen() {
        XCTAssertFalse(shouldBoardSwipeOpenSidebar(state(w: 40, predicted: 60)),
                       "a small nudge must not open the sidebar")
    }

    func testPredictedFlickOpens() {
        XCTAssertTrue(shouldBoardSwipeOpenSidebar(state(w: 50, predicted: 250)),
                      "a fast flick (predicted end past 200) counts")
    }

    func testNotOnIPad() {
        XCTAssertFalse(shouldBoardSwipeOpenSidebar(state(isMobile: false)),
                       "the phone shell sidebar gesture doesn't apply to iPad")
    }
}
