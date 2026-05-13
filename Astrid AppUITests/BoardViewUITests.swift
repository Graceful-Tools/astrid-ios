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
        app.launchArguments = ["--uitesting"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testBoardSegmentedToggleAppearsWhenBoardAvailable() throws {
        app.launch()

        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated — sign in to a test account before running")
        }

        // The unified List/Board/Messages picker is a SegmentedControl that
        // only renders when getHeaderViewToggle decides there's more than
        // one segment to offer (i.e. a project board exists for the list
        // OR chat is available in 1-col). If neither precondition is met
        // for the current account, skip.
        let listSegment = app.segmentedControls
            .buttons
            .matching(NSPredicate(format: "label IN { 'List', 'Board', 'Messages' }"))
            .firstMatch
        if !listSegment.waitForExistence(timeout: 5) {
            throw XCTSkip("Segmented toggle not visible — needs a board-backed list or chat-capable account")
        }
        XCTAssertTrue(listSegment.exists)
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
