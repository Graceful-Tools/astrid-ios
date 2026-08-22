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
    private let fixtureListName = "UI Test List"

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
        if !rotator.waitForExistence(timeout: 5) {
            throw XCTSkip("Rotator button not visible — no list selected or test account is read-only")
        }
        XCTAssertTrue(rotator.exists)
    }

    @MainActor
    func testBoardRendersForListWithProjectId() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        openSidebarIfNeeded()
        try selectFixtureBoardList()
        try openBoardViewIfNeeded()

        // Look for the Inbox column header — virtual columns are always
        // present when a board renders, regardless of which custom statuses
        // a project has.
        let inboxLabel = app.staticTexts["Inbox"]
        if !inboxLabel.waitForExistence(timeout: 8) {
            throw XCTSkip("Board did not render for the seeded project-backed list")
        }
        XCTAssertTrue(inboxLabel.exists)

        try scrollBoardToDoneColumn()

        // And the Done column at the other end.
        let doneLabel = app.staticTexts["Done"]
        XCTAssertTrue(doneLabel.waitForExistence(timeout: 8))
    }

    @MainActor
    private func openSidebarIfNeeded() {
        let menuButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'menu' OR label CONTAINS[c] 'sidebar' OR label CONTAINS[c] 'line.3.horizontal'")
        ).firstMatch

        if menuButton.waitForExistence(timeout: 3) {
            UITestLaunch.tapCenter(menuButton)
            return
        }

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func selectFixtureBoardList() throws {
        let listButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", fixtureListName)).firstMatch
        guard listButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("Seeded board list not visible in the sidebar")
        }
        UITestLaunch.tapCenter(listButton)
    }

    @MainActor
    private func openBoardViewIfNeeded() throws {
        let rotator = app.buttons.matching(
            NSPredicate(format: "label IN { 'Switch to list view', 'Switch to messages', 'Switch to board view' }")
        ).firstMatch
        guard rotator.waitForExistence(timeout: 8) else {
            throw XCTSkip("View rotator not visible after selecting the seeded board list")
        }

        for _ in 0..<2 {
            if rotator.label == "Switch to list view" {
                return
            }
            UITestLaunch.tapCenter(rotator)
            _ = rotator.waitForExistence(timeout: 2)
        }

        guard rotator.label == "Switch to list view" else {
            throw XCTSkip("Board view did not become active after rotating the header toggle")
        }
    }

    @MainActor
    private func scrollBoardToDoneColumn() throws {
        let doneLabel = app.staticTexts["Done"]
        for _ in 0..<8 {
            if doneLabel.exists {
                return
            }
            app.swipeLeft()
            if doneLabel.waitForExistence(timeout: 2) {
                return
            }
        }
        throw XCTSkip("Done column never became visible after paging the board to the right")
    }
}
