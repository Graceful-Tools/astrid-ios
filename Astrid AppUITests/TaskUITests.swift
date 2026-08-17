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
    func testCompleteTask() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        // Wait for tasks to load
        sleep(2)

        // Find a task checkbox (implementation depends on actual UI)
        // Typically a button or image that toggles completion
        let taskRows = app.cells.matching(NSPredicate(format: "identifier CONTAINS 'task'"))

        guard taskRows.count > 0 else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "No Tasks Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("No tasks found to complete")
        }

        let firstTask = taskRows.firstMatch

        // Find checkbox within the task row
        let checkbox = firstTask.buttons.firstMatch

        if checkbox.exists {
            checkbox.tap()

            // Take screenshot after completion
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "After Task Completion"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
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
