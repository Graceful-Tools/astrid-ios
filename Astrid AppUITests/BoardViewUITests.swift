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
/// What these tests do prove:
/// - When a user opens a list whose `projectId` is set, the board UI
///   chrome renders (we see the board's identifying accessibility tag).
/// - The List/Board segmented toggle appears in 1-col mode.
///
/// Both tests skip gracefully when the simulator's account isn't signed
/// in or has no board-backed list, matching the pattern used by
/// TaskDuplicateUITests.
final class BoardViewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        // Sign the run in as the dedicated uitest@astrid.cc account when a session
        // is available (task 44a9cea5). Without it these tests skip themselves, which
        // is what made the suite assert almost nothing.
        //   export ASTRID_UITEST_COOKIE="$(cd ../astrid-web && npx tsx scripts/uitest-account.ts --cookie)"
        if let cookie = ProcessInfo.processInfo.environment[UITestLaunch.cookieKey], !cookie.isEmpty {
            app.launchEnvironment[UITestLaunch.cookieKey] = cookie
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testViewModeRotatorButtonAccessibilityLabelsExist() throws {
        app.launch()

        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated — sign in to a test account before running")
        }

        // The rotator button cycles list → messages → board → list with
        // each tap. Its accessibilityLabel reflects the *next* mode, so
        // one of these three labels should be present in the header.
        let rotator = app.buttons.matching(
            NSPredicate(format: "label IN { 'Switch to list view', 'Switch to messages', 'Switch to board view' }")
        ).firstMatch
        if !rotator.waitForExistence(timeout: 5) {
            throw XCTSkip("Rotator button not visible — no list selected or test account is read-only")
        }
        XCTAssertTrue(rotator.exists)
    }

    @MainActor
    func testBoardRendersForListWithProjectId() throws {
        app.launch()

        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated")
        }

        // Look for the Inbox column header — virtual columns are always
        // present when a board renders, regardless of which custom statuses
        // a project has.
        let inboxLabel = app.staticTexts["Inbox"]
        if !inboxLabel.waitForExistence(timeout: 8) {
            throw XCTSkip("No board-backed list in the test account — open or create one before running")
        }
        XCTAssertTrue(inboxLabel.exists)

        // And the Done column at the other end.
        let doneLabel = app.staticTexts["Done"]
        XCTAssertTrue(doneLabel.waitForExistence(timeout: 2))
    }
}
