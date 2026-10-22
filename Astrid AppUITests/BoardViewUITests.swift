import XCTest

/// Smoke UI tests for the project status board.
///
/// We deliberately stop short of asserting drag-drop reordering: SwiftUI
/// `.draggable` / `.dropDestination` is notoriously brittle under
/// XCUITest on the simulator (the drop target's hover-zone detection
/// races with autoscroll on horizontal containers). The drag-drop *logic*
/// is exhaustively covered by ProjectStatusTests' RED-GREEN unit cases
/// (the same fixtures the web's vitest suite uses) — those are the
/// real contract.
///
/// What this proves: the view-mode rotator is in the header.
///
/// `testBoardRendersForListWithProjectId` lived here and skipped on every
/// run since seeding began: the seeded "UI Test List" has no `projectId`,
/// so no board ever rendered. It returns with the E2E harness task, once a
/// project-backed list is seeded (AITD-525).
final class BoardViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }


    @MainActor
    func testViewModeRotatorButtonAccessibilityLabelsExist() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        // The rotator button cycles list → messages → board → list with
        // each tap. Its accessibilityLabel reflects the *next* mode, so
        // one of these three labels should be present in the header.
        let rotator = app.buttons.matching(
            NSPredicate(format: "label IN { 'Switch to list view', 'Switch to messages', 'Switch to board view' }")
        ).firstMatch
        XCTAssertTrue(rotator.waitForExistence(timeout: 5),
                      "The view-mode rotator should be in the header")
    }
}
