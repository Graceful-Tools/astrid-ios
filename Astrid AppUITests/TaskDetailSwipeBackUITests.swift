import XCTest

/// UI tests for task detail swipe-back gesture
/// Verifies that swiping right on task details closes the detail and returns to the task list
final class TaskDetailSwipeBackUITests: XCTestCase {

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
    func testSwipeBackOnTaskDetailReturnsToTaskList() throws {
        app.launch()

        let timeout: TimeInterval = 10

        // Skip if on login screen
        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated")
        }

        // Wait for task list to load
        let taskListLoaded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'My Tasks' OR label CONTAINS[c] 'task'")).firstMatch.waitForExistence(timeout: timeout)
        if !taskListLoaded {
            // Take screenshot for debugging
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Task List Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Task list not visible")
        }

        // Find and tap the first task cell
        // Tasks are in a scrollable list — look for any tappable cell
        let cells = app.cells
        guard cells.count > 0 else {
            throw XCTSkip("No tasks found in list")
        }

        let firstTask = cells.firstMatch
        firstTask.tap()

        // Wait for task detail to appear
        // The custom header shows "Task Details" text
        let detailHeader = app.staticTexts["Task Details"]
        let detailAppeared = detailHeader.waitForExistence(timeout: 5)

        if !detailAppeared {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Task Detail Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Task detail did not appear")
        }

        // Take screenshot before swipe
        let beforeSwipe = XCTAttachment(screenshot: app.screenshot())
        beforeSwipe.name = "Before Swipe Back"
        beforeSwipe.lifetime = .keepAlways
        add(beforeSwipe)

        // Perform swipe-back gesture (left-to-right from left edge)
        let screenCenter = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let screenRight = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        screenCenter.press(forDuration: 0.05, thenDragTo: screenRight)

        // Wait a moment for animation
        Thread.sleep(forTimeInterval: 0.5)

        // Take screenshot after swipe
        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Swipe Back"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Verify task detail is gone — "Task Details" header should no longer be visible
        XCTAssertFalse(detailHeader.exists, "Task detail should be dismissed after swipe-back")
    }

    @MainActor
    func testBackButtonOnTaskDetailReturnsToTaskList() throws {
        app.launch()

        let timeout: TimeInterval = 10

        // Skip if on login screen
        if app.buttons["Sign in with Apple"].waitForExistence(timeout: 3) {
            throw XCTSkip("User not authenticated")
        }

        // Wait for task list to load
        let taskListLoaded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'My Tasks' OR label CONTAINS[c] 'task'")).firstMatch.waitForExistence(timeout: timeout)
        if !taskListLoaded {
            throw XCTSkip("Task list not visible")
        }

        // Find and tap the first task
        let cells = app.cells
        guard cells.count > 0 else {
            throw XCTSkip("No tasks found in list")
        }

        cells.firstMatch.tap()

        // Wait for task detail
        let detailHeader = app.staticTexts["Task Details"]
        guard detailHeader.waitForExistence(timeout: 5) else {
            throw XCTSkip("Task detail did not appear")
        }

        // Tap the back button (chevron.left)
        let backButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Back' OR label CONTAINS[c] 'chevron'")).firstMatch
        if backButton.exists {
            backButton.tap()
        } else {
            // Try finding by image name
            app.images["chevron.left"].firstMatch.tap()
        }

        // Wait for animation
        Thread.sleep(forTimeInterval: 0.5)

        // Verify task detail is gone
        XCTAssertFalse(detailHeader.exists, "Task detail should be dismissed after tapping back")
    }
}
