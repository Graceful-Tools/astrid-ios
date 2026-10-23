import XCTest

/// UI tests for task operations
/// Tests critical user flows for task creation, editing, and completion
final class TaskUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()

    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Quick Add Task Tests

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
            throw UITestFailure("Quick add task input not found")
        }

        // Create a unique task title
        let taskTitle = "UI Test Task \(Date().timeIntervalSince1970)"

        // Tap input and enter title
        guard UITestLaunch.focusQuickAdd(app) else {
            throw UITestFailure("Quick add never took keyboard focus")
        }
        // Submit with a newline — the Return key's name depends on the keyboard's language.
        taskInput.typeText(taskTitle + "\n")

        // Wait for task to appear in list
        let taskCreated = UITestLaunch.waitForCreatedTask(app, titled: taskTitle) != nil

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
    /// It also asserted nothing: it tapped, screenshotted, and ended. It then asserted that the
    /// completed row DISAPPEARS, which was measured on an account holding hundreds of leftover
    /// tasks: the row re-sorted below every open one, far out of the lazy accessibility tree,
    /// and that read as gone. On the five-fixture account the reset is meant to produce, the
    /// row stays on screen, struck through and ticked, and the assertion failed on an app doing
    /// exactly the right thing (AITD-490). So it checks the tick. It used to accept the row
    /// leaving as well, but a row re-sorting out of the lazy tree satisfies "the count dropped"
    /// just as well as a completion does, so that branch could pass on a tap that did nothing
    /// (AITD-525). Safe to run repeatedly — `npm run test:ui` recreates the fixture tasks on
    /// every run.
    func testCompleteTask() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        guard UITestLaunch.waitForFirstVisibleRow(app) != nil else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "No Tasks Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw UITestFailure("No task rows on screen — the seeder guarantees five")
        }

        // The checkbox is the row's `taskRow`-identified BUTTON — the title beside it carries
        // the same identifier, which is exactly the trap that made tapping a row complete it
        // once before. Its label is the image name, `check_box[_repeat][_checked]_<priority>`,
        // which is the only place the row says whether it is ticked.
        func checkbox(in row: XCUIElement) -> XCUIElement {
            row.buttons.matching(identifier: UITestLaunch.taskRowIdentifier).firstMatch
        }
        // The first OPEN row: ticking one that is already done would un-complete it.
        guard let openRow = UITestLaunch.visibleRows(app).first(where: {
            let box = checkbox(in: $0)
            return box.exists && !box.label.contains("_checked")
        }) else {
            throw UITestFailure("No open row with a checkbox — the seeded fixtures are open and unassigned")
        }

        // The row's own title, which is the first static text inside it.
        let title = openRow.staticTexts.firstMatch.label
        XCTAssertFalse(title.isEmpty, "a task row should carry its title")
        let titled = NSPredicate(format: "label == %@", title)

        UITestLaunch.tapCenter(checkbox(in: openRow))

        // Completing re-sorts the list, so the row is looked up again by title on every poll
        // rather than held onto. Poll rather than sleep, and say WHICH title was being watched
        // if nothing changes — a bare timeout on a predicate cannot tell "the tap did nothing"
        // from "the wrong text was captured".
        var ticked = false
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let box = checkbox(in: app.cells.containing(titled).firstMatch)
            ticked = box.exists && box.label.contains("_checked")
            if ticked { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(ticked, "completing \"\(title)\" should tick its checkbox")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After Task Completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

}
