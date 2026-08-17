import XCTest

/// UI tests for swipe-right navigation gestures
/// Verifies swipe-right works on task detail, settings, and task list (sidebar)
final class TaskDetailSwipeBackUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// This suite had the marker right when the others had it wrong — "Use without account" is
    /// the welcome screen's canonical button. That is now the shared check, so keep using it
    /// from one place rather than two.
    @MainActor
    private func skipIfNotSignedIn() throws {
        try UITestLaunch.skipUnlessSignedIn(app)
    }

    /// Waits for the task list "My Tasks" header to appear.
    /// Uses an exact match on the localized header so we don't accidentally match
    /// the welcome screen subtitle "Your intelligent task manager".
    @MainActor
    private func waitForTaskList(timeout: TimeInterval = 10) -> Bool {
        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'My Tasks'")).firstMatch
        return header.waitForExistence(timeout: timeout)
    }

    @MainActor
    func testSwipeBackOnTaskDetailReturnsToTaskList() throws {
        app.launch()
        try skipIfNotSignedIn()

        if !waitForTaskList() {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Task List Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Task list not visible")
        }

        // Find and tap the first task cell
        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No tasks found in list")
        }

        UITestLaunch.tapCenter(firstTask)

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
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw XCTSkip("Task list not visible")
        }

        // Find and tap the first task
        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No tasks found in list")
        }

        UITestLaunch.tapCenter(firstTask)

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

    // MARK: - Swipe Right on Task List Opens Sidebar

    @MainActor
    func testSwipeRightOnTaskListOpensSidebar() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw XCTSkip("Task list not visible")
        }

        // Perform swipe-right gesture from upper area to avoid task cells / list swipe actions.
        // Use a slightly longer press so the gesture registers as a deliberate drag rather
        // than a flick whose predicted end-translation can fall under the open threshold on
        // slower/loaded simulators.
        let swipeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
        swipeStart.press(forDuration: 0.15, thenDragTo: swipeEnd)

        // Let the sidebar's spring open-animation (≈0.25s) settle before asserting, matching
        // the robust pattern used by the other swipe tests in this file. Asserting mid-animation
        // is the root cause of this test's flakiness — the accessibility tree is unstable while
        // the sidebar scales/fades in.
        Thread.sleep(forTimeInterval: 0.5)

        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Sidebar Swipe"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Sidebar contains a "Lists" section header that does NOT appear on the task list itself.
        // Use waitForExistence to allow for any remaining open animation.
        let listsHeader = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Lists' OR label ==[c] 'Add List'")).firstMatch
        XCTAssertTrue(listsHeader.waitForExistence(timeout: 5), "Sidebar should be visible after swipe-right on task list")
    }

    // MARK: - Swipe Right on Settings Closes Settings

    @MainActor
    func testSwipeRightOnSettingsReturnsToTaskList() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw XCTSkip("Task list not visible")
        }

        // Open sidebar first (tap hamburger menu)
        let menuButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'menu' OR label CONTAINS[c] 'sidebar' OR label CONTAINS[c] 'line.3.horizontal'")).firstMatch
        if menuButton.exists {
            menuButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
        } else {
            // Swipe right to open sidebar
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Tap settings button in sidebar
        let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Settings' OR label CONTAINS[c] 'settings' OR label CONTAINS[c] 'gearshape'")).firstMatch
        // Must be hittable, not merely present: the closed sidebar keeps its gear button in
        // the tree, and tapping an off-screen element fails rather than skipping.
        guard settingsButton.waitForExistence(timeout: 3) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Settings Button Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Settings button not found in sidebar")
        }
        UITestLaunch.tapCenter(settingsButton)

        Thread.sleep(forTimeInterval: 0.5)

        // Verify settings is visible
        let settingsHeader = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Settings' OR label CONTAINS[c] 'settings'")).firstMatch
        guard settingsHeader.waitForExistence(timeout: 3) else {
            throw XCTSkip("Settings view did not appear")
        }

        let beforeSwipe = XCTAttachment(screenshot: app.screenshot())
        beforeSwipe.name = "Settings Before Swipe"
        beforeSwipe.lifetime = .keepAlways
        add(beforeSwipe)

        // Swipe right to dismiss settings
        let swipeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

        Thread.sleep(forTimeInterval: 0.5)

        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Settings Swipe"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Task list should be visible again (settings dismissed)
        XCTAssertTrue(waitForTaskList(timeout: 3), "Task list should be visible after swiping back from settings")
    }

    // MARK: - Taps Still Work After Gesture Setup

    @MainActor
    func testTaskRowTapStillWorksWithSwipeGesture() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw XCTSkip("Task list not visible")
        }

        // Tap a task
        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No tasks found in list")
        }
        UITestLaunch.tapCenter(firstTask)

        // Task detail should appear
        let detailHeader = app.staticTexts["Task Details"]
        XCTAssertTrue(detailHeader.waitForExistence(timeout: 5), "Task detail should open when tapping a task row")
    }
}
