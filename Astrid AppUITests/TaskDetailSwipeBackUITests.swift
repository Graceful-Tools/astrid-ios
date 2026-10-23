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

    /// Waits for the task list's header, by identifier (AITD-526).
    @MainActor
    private func waitForTaskList(timeout: TimeInterval = 10) -> Bool {
        UITestLaunch.waitForTaskList(app, timeout: timeout)
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

        // Wait for task detail to appear — at the helper's own timeout, which says why five
        // seconds was too short.
        let detailHeader = UITestLaunch.taskDetailHeader(app)
        let detailAppeared = UITestLaunch.waitForTaskDetail(app)

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
        let dismissed = UITestLaunch.waitForDisappearance(detailHeader)

        // Take screenshot after swipe
        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Swipe Back"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        XCTAssertTrue(dismissed, "Task detail should be dismissed after swipe-back")
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

        // The closed sidebar keeps its cells in the accessibility tree, so "a Lists header
        // exists" passed whether or not the swipe opened anything (AITD-525). Its header search
        // is only HITTABLE once the sidebar is actually on screen.
        let headerSearch = app.descendants(matching: .any)
            .matching(identifier: "sidebar.headerSearch").firstMatch
        XCTAssertTrue(headerSearch.waitForExistence(timeout: 5), "Sidebar header search should exist")
        let hittable = NSPredicate(format: "isHittable == true")
        let opened = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: hittable, object: headerSearch)], timeout: 5)
        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Sidebar Swipe"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)
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

        // Open the sidebar with the swipe testSwipeRightOnTaskListOpensSidebar proves. The
        // hamburger it used to look for first was matched by label, and the header's menu is an
        // unlabelled overlay — so that branch never ran.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
        // 0.15s: a 0.05s flick can fall under the open threshold on a loaded simulator.
        start.press(forDuration: 0.15, thenDragTo: end)

        // Tap settings button in sidebar
        let settingsButton = app.buttons["sidebar.settings"]
        // Must be hittable, not merely present: the closed sidebar keeps its gear button in
        // the tree, and tapping an off-screen element fails rather than skipping.
        let onScreen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
                                                 object: settingsButton)
        guard settingsButton.waitForExistence(timeout: 3),
              XCTWaiter().wait(for: [onScreen], timeout: 5) == .completed else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Settings Button Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw UITestFailure("Settings button not found in sidebar")
        }
        UITestLaunch.tapCenter(settingsButton)

        // Verify settings is visible — by its profile row, which nothing else on screen carries.
        let settingsProfile = app.descendants(matching: .any)
            .matching(identifier: "settings.profile").firstMatch
        guard settingsProfile.waitForExistence(timeout: 5) else {
            throw UITestFailure("Settings view did not appear")
        }

        let beforeSwipe = XCTAttachment(screenshot: app.screenshot())
        beforeSwipe.name = "Settings Before Swipe"
        beforeSwipe.lifetime = .keepAlways
        add(beforeSwipe)

        // Swipe right to dismiss settings — the same recognised gesture the detail uses, from
        // one place, so the two cannot drift into testing different things.
        UITestLaunch.swipeBackFromLeftEdge(app)
        let dismissed = UITestLaunch.waitForDisappearance(settingsProfile)

        let afterSwipe = XCTAttachment(screenshot: app.screenshot())
        afterSwipe.name = "After Settings Swipe"
        afterSwipe.lifetime = .keepAlways
        add(afterSwipe)

        // Settings must be gone — the list's header alone can be in the tree behind it, so it
        // cannot say the swipe worked (AITD-525).
        XCTAssertTrue(dismissed, "Settings should be dismissed after swiping back")
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
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "Task detail should open when tapping a task row")
    }
}
