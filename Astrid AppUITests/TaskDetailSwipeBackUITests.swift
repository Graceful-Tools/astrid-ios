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

    /// Swiping right on Settings opens the sidebar — the same thing it does on a list (AITD-549).
    ///
    /// THE DECISION, and why the test changed rather than the app. Settings is a page in the
    /// sidebar's navigation, like a list: the sidebar picks it, it fills the content area, and a
    /// right swipe on it reveals the sidebar with the page still peeking at the right edge — the
    /// same as `testSwipeRightOnTaskListOpensSidebar`. So after the swipe Settings is still in
    /// the view tree, parked off to the right, by design. This used to assert that its profile row
    /// no longer EXISTED, which failed in 5 of 7 runs on an app doing the right thing; whether it
    /// passed depended on whether SwiftUI had happened to drop the parked view yet.
    ///
    /// What a person sees is what is asserted now: the sidebar is on screen and can be used, and
    /// Settings is no longer what they can tap. No fixed sleeps — each step waits for its state.
    @MainActor
    func testSwipeRightOnSettingsOpensTheSidebar_AITD549() throws {
        app.launch()
        try skipIfNotSignedIn()

        guard waitForTaskList() else {
            throw UITestFailure("Task list not visible")
        }

        // Into Settings the way a person goes: the menu, then the gear.
        let hittable = NSPredicate(format: "isHittable == true")
        let menu = app.buttons.matching(identifier: "taskList.menu").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the header's menu target")
        menu.tap()
        // The closed sidebar keeps its gear in the tree, so wait for it to be TAPPABLE.
        let settingsButton = app.buttons["sidebar.settings"]
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: settingsButton)],
                                        timeout: 5), .completed, "the sidebar should open on the menu")
        UITestLaunch.tapCenter(settingsButton)

        let settingsProfile = app.descendants(matching: .any).matching(identifier: "settings.profile").firstMatch
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: settingsProfile)],
                                        timeout: 10), .completed, "Settings should be showing")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Settings Before Swipe"
        before.lifetime = .keepAlways
        add(before)

        // The same recognised gesture the detail's back-swipe uses, from one place.
        UITestLaunch.swipeBackFromLeftEdge(app)

        // The sidebar is on screen: its header search is tappable only once it has slid in.
        let headerSearch = app.descendants(matching: .any).matching(identifier: "sidebar.headerSearch").firstMatch
        let opened = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: headerSearch)],
                                      timeout: 5)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "After Settings Swipe"
        after.lifetime = .keepAlways
        add(after)
        XCTAssertEqual(opened, .completed, "swiping right on Settings should bring the sidebar on screen")

        // And Settings is parked: pushed off to the right, where at most its edge peeks out. Not
        // "not hittable" — the peeking strip is still on screen, so XCUITest calls the row hittable
        // whenever its hit point lands in it — and not "gone", which is the parked page by design.
        let width = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(settingsProfile.frame.minX, width * 0.5,
                             "Settings should be parked to the right of the sidebar; its row is at "
                             + "\(settingsProfile.frame) in a window \(width) wide")
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
