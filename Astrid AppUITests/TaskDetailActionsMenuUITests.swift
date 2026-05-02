import XCTest

/// Regression coverage for the task-detail "..." actions menu (top-right).
/// The button used to render as a 20pt SF Symbol with .buttonStyle(.plain) and no
/// .contentShape — the actual hittable area was the glyph (~20×20pt), well below
/// Apple's 44pt HIG minimum, so users were tapping and getting no response.
final class TaskDetailActionsMenuUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testActionsMenuIsHittableAndOpensMenu() throws {
        app.launch()

        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated")
        }

        // Open a task
        let taskListLoaded = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'My Tasks' OR label CONTAINS[c] 'task'"))
            .firstMatch
            .waitForExistence(timeout: 10)
        guard taskListLoaded else { throw XCTSkip("Task list not visible") }

        let cells = app.cells
        guard cells.count > 0 else { throw XCTSkip("No tasks found in list") }
        cells.firstMatch.tap()

        let detailHeader = app.staticTexts["Task Details"]
        guard detailHeader.waitForExistence(timeout: 5) else { throw XCTSkip("Task detail did not appear") }

        // The actions menu should be present and big enough to tap
        let menu = app.buttons["taskDetailActionsMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3), "Actions menu should expose its accessibility identifier")
        XCTAssertTrue(menu.isHittable, "Actions menu must be hittable — tap target was too small in earlier builds")

        let frame = menu.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "Actions menu width must meet HIG 44pt minimum (got \(frame.width))")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "Actions menu height must meet HIG 44pt minimum (got \(frame.height))")

        // Tap and verify a menu item shows up
        menu.tap()
        let copyItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'copy'")).firstMatch
        let shareItem = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share'")).firstMatch
        let menuOpened = copyItem.waitForExistence(timeout: 2) || shareItem.waitForExistence(timeout: 2)
        XCTAssertTrue(menuOpened, "Tapping the actions menu should reveal Copy/Share/Delete items")
    }
}
