import XCTest
import SwiftUI
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

// MARK: - Task AITD-594 — "iOS iPad swipe in traffic light causes task details to close. It
// shouldn't"
//
// The iPad detail panel closes on a rightward swipe anywhere in it, simultaneously with any
// scroll view inside, so scrolling a decision matrix back to its first column closed the task.

final class TaskPanelSwipeCloseTests: XCTestCase {
    private let grid = CGRect(x: 20, y: 300, width: 500, height: 200)

    private func closes(from start: CGPoint) -> Bool {
        shouldSwipeCloseTaskPanel(start: start, sidewaysScrollRegions: [grid],
                                  translationWidth: 150, translationHeight: 5,
                                  predictedEndTranslationWidth: 300)
    }

    func testAITD594_aSwipeOnTheDecisionMatrixKeepsTheTaskOpen() {
        XCTAssertFalse(closes(from: CGPoint(x: 100, y: 400)), "the grid's own sideways scroll")
    }

    func testAITD594_aSwipeElsewhereStillClosesTheTask() {
        XCTAssertTrue(closes(from: CGPoint(x: 100, y: 100)))
    }

    // MARK: Task AITD-595 — "Trade-off grid: a sideways drag scrolls the grid instead of closing
    // the task" (web AWTD-1534, PRODUCT_CONTRACT §8)

    func testAITD595_aSwipeFromTheScreensLeftEdgeClosesTheTaskEvenOverAGrid() {
        let flush = CGRect(x: 0, y: 300, width: 500, height: 200)
        XCTAssertTrue(shouldSwipeCloseTaskPanel(start: CGPoint(x: 8, y: 400),
                                                sidewaysScrollRegions: [flush],
                                                translationWidth: 150, translationHeight: 5,
                                                predictedEndTranslationWidth: 300),
                      "the edge swipe is back, wherever it starts")
    }
}

@MainActor
final class SidewaysScrollRegionReportTests: XCTestCase {
    func testAITD594_theDecisionMatrixReportsWhereItIs() {
        let reported = regions(reportedBy: Self.wideGrid)
        XCTAssertEqual(reported.count, 1, "one grid, one region")
        XCTAssertGreaterThan(reported.first?.height ?? 0, 20)
    }

    /// AITD-595: a grid with nothing to scroll leaves the swipe to close the task (web: "a grid
    /// that fits needs no scroll, so a swipe across it still goes back").
    func testAITD595_aGridThatFitsReportsNoRegion() {
        XCTAssertEqual(regions(reportedBy: """
            | Option | Cost |
            |---|---|
            | A. Rust core | ++ one codebase |
            """), [])
    }

    /// Eight criteria at 84pt or more each cannot fit in 600.
    private static let wideGrid = """
        | Option | Cost | Speed | Risk | Reach | Effort | Fit | Fun | Time |
        |---|---|---|---|---|---|---|---|---|
        | A. Rust core | ++ one codebase | + fast | ~ new | + all | - big | + yes | ++ fun | - long |
        """

    private func regions(reportedBy source: String) -> [CGRect] {
        var reported: [CGRect] = []
        let view = NavigationStack {
            ScrollView {
                MarkdownText(source: source)
            }
            .onPreferenceChange(SidewaysScrollRegions.self) { reported = $0 }
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return reported
    }
}
