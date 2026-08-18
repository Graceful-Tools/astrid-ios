import XCTest

/// UI tests for task operations
/// Tests critical user flows for task creation, editing, and completion
final class TaskUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()

        // Skip if not logged in (UI tests require authenticated state)
        // In real implementation, you'd handle authentication in setup
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Quick Add Task Tests

    @MainActor
    func testQuickAddTaskVisible() throws {
        app.launch()

        // Wait for app to load
        let timeout: TimeInterval = 10

        // Check if quick add task input is visible (may be on main task list view)
        // This will depend on the actual UI structure
        _ = app.textFields["Add a task..."].waitForExistence(timeout: timeout) ||
            UITestLaunch.quickAddField(app).waitForExistence(timeout: timeout)

        // Take screenshot for debugging
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick Add Task View"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // If we're on the login screen, skip this test
        if app.buttons["Sign in with Apple"].exists || app.buttons["Sign in with Google"].exists {
            throw XCTSkip("User not authenticated - skipping task UI tests")
        }
    }

    @MainActor
    func testCreateTaskWithTitle() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        // Find the task input field
        let taskInput = UITestLaunch.quickAddField(app)

        guard taskInput.waitForExistence(timeout: timeout) else {
            // Take screenshot to debug
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Task Input Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Quick add task input not found")
        }

        // Create a unique task title
        let taskTitle = "UI Test Task \(Date().timeIntervalSince1970)"

        // Tap input and enter title
        guard UITestLaunch.focusQuickAdd(app) else {
            throw XCTSkip("Quick add never took keyboard focus")
        }
        taskInput.typeText(taskTitle)

        // Submit task (press return or tap add button)
        app.keyboards.buttons["Return"].tap()

        // Wait for task to appear in list
        let newTask = app.staticTexts[taskTitle]
        let taskCreated = newTask.waitForExistence(timeout: timeout)

        // Take screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After Task Creation"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(taskCreated, "Created task should appear in the list")
    }

    // MARK: - Task Completion Tests

    @MainActor
    /// Tapping a row's checkbox completes the task, and the completed task leaves the list.
    ///
    /// This skipped as "No tasks found to complete" for as long as the suite could sign in
    /// (task 91a7e180). It asked for `app.cells.matching(identifier CONTAINS 'task')`, and the
    /// cell carries no identifier — SwiftUI stamps it on the elements INSIDE the row, so the
    /// query matched nothing on a screen full of tasks. `UITestLaunch.visibleRows` is the one
    /// place that knows how to ask.
    ///
    /// It also asserted nothing: it tapped, screenshotted, and ended. Measured behaviour is
    /// that the completed row disappears from the list, so that is what it checks now. Safe to
    /// run repeatedly — `npm run test:ui` recreates the fixture tasks on every run.
    func testCompleteTask() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        guard let firstRow = UITestLaunch.waitForFirstVisibleRow(app) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "No Tasks Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("No task rows on screen")
        }

        // The row's own title, which is the first static text inside it.
        let title = firstRow.staticTexts.firstMatch.label
        XCTAssertFalse(title.isEmpty, "a task row should carry its title")

        // The checkbox is the row's `taskRow`-identified BUTTON — the title beside it carries
        // the same identifier, which is exactly the trap that made tapping a row complete it
        // once before.
        let checkbox = firstRow.buttons.matching(identifier: UITestLaunch.taskRowIdentifier).firstMatch
        guard checkbox.waitForExistence(timeout: 5) else {
            throw XCTSkip("The row has no checkbox — an avatar or the unassigned mark instead")
        }
        UITestLaunch.tapCenter(checkbox)

        // Completing re-sorts the list and drops the task out of it. Poll rather than sleep,
        // and say WHICH title was being watched if it never goes — a bare timeout on a
        // predicate cannot tell "the tap did nothing" from "the wrong text was captured".
        let remaining = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
        let deadline = Date().addingTimeInterval(10)
        while remaining.count > 0 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(remaining.count, 0,
                       "completing should drop \"\(title)\" out of the list; still showing after 10s")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After Task Completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Task Detail Tests

    @MainActor
    func testOpenTaskDetail() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        // Wait for tasks to load
        sleep(2)

        // Find any task text to tap
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "No Tasks for Detail"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("No tasks found to open")
        }

        // Tap on first task to open detail
        tasks.firstMatch.tap()

        // Wait for detail view to appear
        // Detail view typically has title field, description, priority picker, etc.
        sleep(1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Task Detail View"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Priority Selection Tests

    @MainActor
    func testChangePriority() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find and open a task
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            throw XCTSkip("No tasks found")
        }

        tasks.firstMatch.tap()
        sleep(1)

        // Find priority picker (might be labeled "Priority", "None", "Low", "Medium", "High")
        let priorityButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'priority' OR label == 'None' OR label == 'Low' OR label == 'Medium' OR label == 'High'")).firstMatch

        if priorityButton.exists {
            priorityButton.tap()

            // Select "High" priority
            let highPriority = app.buttons["High"]
            if highPriority.waitForExistence(timeout: 3) {
                highPriority.tap()
            }
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After Priority Change"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
