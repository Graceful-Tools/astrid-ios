import XCTest

/// UI tests for task creation deduplication
/// Tests that one submit creates exactly one task
final class TaskDuplicateUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// One submit, one task.
    ///
    /// This asserted `count <= 1`, which a creation that FAILED satisfies just as well as one
    /// that worked (AITD-525). It now waits for the task to appear, gives a duplicate time to
    /// arrive, and asserts exactly one.
    @MainActor
    func testCreateTaskAppearsExactlyOnce() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        let addTaskField = UITestLaunch.quickAddField(app)

        guard addTaskField.waitForExistence(timeout: timeout) else {
            throw UITestFailure("Quick add task field not found")
        }

        // Create a uniquely named task
        let uniqueTitle = "Unique task \(UUID().uuidString.prefix(8))"
        guard UITestLaunch.focusQuickAdd(app) else {
            throw UITestFailure("Quick add never took keyboard focus")
        }
        addTaskField.typeText(uniqueTitle)
        app.keyboards.buttons["Return"].tap()

        guard UITestLaunch.waitForCreatedTask(app, titled: uniqueTitle) != nil else {
            throw UITestFailure("Task '\(uniqueTitle)' should appear after submitting it")
        }
        let taskCells = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", uniqueTitle)
        )

        // A duplicate arrives after the first copy (the server echo), so give it the chance.
        Thread.sleep(forTimeInterval: 2)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Single Task Created"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertEqual(taskCells.count, 1,
            "Task '\(uniqueTitle)' should appear exactly once, found \(taskCells.count)")
    }
}
