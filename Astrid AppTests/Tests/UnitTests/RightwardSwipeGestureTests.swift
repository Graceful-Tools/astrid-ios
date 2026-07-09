import XCTest
@testable import Astrid_App

/// The shared shell swipe gesture (go back / close task / open sidebar) used on
/// both iPhone and iPad. Same thresholds everywhere.
final class RightwardSwipeGestureTests: XCTestCase {

    func testFiresOnDeliberateRightwardSwipe() {
        XCTAssertTrue(isRightwardSwipeGesture(translationWidth: 120, translationHeight: 10,
                                              predictedEndTranslationWidth: 250))
    }

    func testIgnoresLeftwardSwipe() {
        XCTAssertFalse(isRightwardSwipeGesture(translationWidth: -120, translationHeight: 10,
                                               predictedEndTranslationWidth: -250))
    }

    func testIgnoresMostlyVertical() {
        XCTAssertFalse(isRightwardSwipeGesture(translationWidth: 30, translationHeight: 200,
                                               predictedEndTranslationWidth: 40))
    }

    func testIgnoresSmallNudge() {
        XCTAssertFalse(isRightwardSwipeGesture(translationWidth: 40, translationHeight: 5,
                                               predictedEndTranslationWidth: 60))
    }

    func testFastFlickCounts() {
        XCTAssertTrue(isRightwardSwipeGesture(translationWidth: 50, translationHeight: 5,
                                              predictedEndTranslationWidth: 250))
    }

    func testLeadingEdgeSwipeAcceptsDistanceOrVelocity() {
        XCTAssertTrue(shouldTriggerLeadingEdgeSwipe(translationWidth: 90, velocityWidth: 100))
        XCTAssertTrue(shouldTriggerLeadingEdgeSwipe(translationWidth: 35, velocityWidth: 350))
    }

    func testLeadingEdgeSwipeRejectsShortSlowOrReverseMovement() {
        XCTAssertFalse(shouldTriggerLeadingEdgeSwipe(translationWidth: 35, velocityWidth: 100))
        XCTAssertFalse(shouldTriggerLeadingEdgeSwipe(translationWidth: -90, velocityWidth: -350))
    }

    /// The board helper still works through the shared gesture.
    func testBoardSwipeUsesSharedGesture() {
        let s = BoardSidebarSwipeState(isMobile: true, isAtLeftmostColumn: true,
                                       translationWidth: 120, translationHeight: 10,
                                       predictedEndTranslationWidth: 250)
        XCTAssertTrue(shouldBoardSwipeOpenSidebar(s))
    }
}
