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
            throw UITestFailure("Task list not visible")
        }

        // Find and tap the first task cell
        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw UITestFailure("No tasks found in list")
        }

        UITestLaunch.tapCenter(firstTask)

        // Wait for task detail to appear
        // The custom header shows "Task Details" text
        let detailHeader = UITestLaunch.taskDetailHeader(app)
        let detailAppeared = detailHeader.waitForExistence(timeout: 5)

        if !detailAppeared {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Task Detail Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw UITestFailure("Task detail did not appear")
        }

        // Take screenshot before swipe
        let beforeSwipe = XCTAttachment(screenshot: app.screenshot())
        beforeSwipe.name = "Before Swipe Back"
        beforeSwipe.lifetime = .keepAlways
        add(beforeSwipe)

        // The back-swipe, driven the way iOS will accept it: down ON the edge, slowly, with a
        // hold at each end. The 0.05s flick from 5% in that used to be here is not a pan as far
        // as UIKit's screen-edge recogniser is concerned, and it left the detail open — which
        // reads as the app having lost its back-swipe rather than the test never performing one
        // (task b86c97c5).
        UITestLaunch.swipeBackFromLeftEdge(app)

        // Wait a moment for animation
        Thread.sleep(forTimeInterval: 1.0)

        // Take screenshot after swipe
        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Swipe Back"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Verify task detail is gone — "Task Details" header should no longer be visible
        XCTAssertFalse(detailHeader.exists, "Task detail should be dismissed after swipe-back")
    }

    // MARK: - Swipe Right on Task List Opens Sidebar

    @MainActor
    func testSwipeRightOnTaskListOpensSidebar() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw UITestFailure("Task list not visible")
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

        // The closed sidebar keeps its cells in the accessibility tree, so "a Lists header
        // exists" passed whether or not the swipe opened anything (AITD-525). Its header search
        // is only HITTABLE once the sidebar is actually on screen.
        let headerSearch = app.descendants(matching: .any)
            .matching(identifier: "sidebar.headerSearch").firstMatch
        XCTAssertTrue(headerSearch.waitForExistence(timeout: 5), "Sidebar header search should exist")
        let hittable = NSPredicate(format: "isHittable == true")
        let opened = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: hittable, object: headerSearch)], timeout: 5)
        XCTAssertEqual(opened, .completed, "Sidebar should be on screen after swipe-right on task list")
    }

    // MARK: - Swipe Right on Settings Closes Settings

    @MainActor
    func testSwipeRightOnSettingsReturnsToTaskList() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw UITestFailure("Task list not visible")
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
            throw UITestFailure("Settings button not found in sidebar")
        }
        UITestLaunch.tapCenter(settingsButton)

        Thread.sleep(forTimeInterval: 0.5)

        // Verify settings is visible — by its profile row, which nothing else on screen carries.
        let settingsProfile = app.descendants(matching: .any)
            .matching(identifier: "settings.profile").firstMatch
        guard settingsProfile.waitForExistence(timeout: 3) else {
            throw UITestFailure("Settings view did not appear")
        }

        let beforeSwipe = XCTAttachment(screenshot: app.screenshot())
        beforeSwipe.name = "Settings Before Swipe"
        beforeSwipe.lifetime = .keepAlways
        add(beforeSwipe)

        // Swipe right to dismiss settings — the same recognised gesture the detail uses, from
        // one place, so the two cannot drift into testing different things.
        UITestLaunch.swipeBackFromLeftEdge(app)

        Thread.sleep(forTimeInterval: 1.0)

        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Settings Swipe"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Settings must be gone. "My Tasks" alone also matches the sidebar row while Settings
        // is still open, so it cannot say the swipe worked (AITD-525).
        XCTAssertFalse(settingsProfile.exists, "Settings should be dismissed after swiping back")
        XCTAssertTrue(waitForTaskList(timeout: 3), "Task list should be visible after swiping back from settings")
    }

    // MARK: - Taps Still Work After Gesture Setup

    @MainActor
    func testTaskRowTapStillWorksWithSwipeGesture() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw UITestFailure("Task list not visible")
        }

        // Tap a task
        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw UITestFailure("No tasks found in list")
        }
        UITestLaunch.tapCenter(firstTask)

        // Task detail should appear
        let detailHeader = UITestLaunch.taskDetailHeader(app)
        XCTAssertTrue(detailHeader.waitForExistence(timeout: 5), "Task detail should open when tapping a task row")
    }
}
