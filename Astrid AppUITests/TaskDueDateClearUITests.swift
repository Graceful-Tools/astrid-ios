import XCTest

/// "No due date" has to leave the task with no due date (AITD-511).
///
/// The task detail's date sheet offers "No due date" first among its quick picks. Choosing it on
/// a dated task has to leave the chip reading "No due date" — and keep reading it once the sheet
/// is gone and the save has gone through, which is where the date used to come back.
final class TaskDueDateClearUITests: XCTestCase {

    var app: XCUIApplication!
    let title = "Undate \(UUID().uuidString.prefix(8))"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testNoDueDateClearsADatedTask_AITD511() throws {
        let chip = try openNewTaskWithToday()
        try clearAndExpectNoDueDate(chip)
    }

    @MainActor
    func testNoDueDateClearsATimedTask_AITD511() throws {
        let chip = try openNewTaskWithToday()
        let time = app.buttons[Self.timeTrigger]
        XCTAssertTrue(time.waitForExistence(timeout: 5), "a dated task offers a time")
        time.tap()
        let morning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.morning)).firstMatch
        XCTAssertTrue(morning.waitForExistence(timeout: 5), "the time sheet should offer Morning")
        morning.tap()
        Thread.sleep(forTimeInterval: 1)
        try clearAndExpectNoDueDate(chip)
    }

    @MainActor
    func testNoDueDateClearsARepeatingTask_AITD511() throws {
        let chip = try openNewTaskWithToday()
        let repeatChip = app.buttons[Self.repeatTrigger]
        XCTAssertTrue(repeatChip.waitForExistence(timeout: 5), "a dated task offers a repeat")
        repeatChip.tap()
        let daily = app.buttons[Self.daily].firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 5), "the repeat sheet should offer Daily")
        daily.tap()
        Thread.sleep(forTimeInterval: 1)
        try clearAndExpectNoDueDate(chip)
    }

    /// A new task, opened, with Today picked — the chip it returns is the date trigger.
    @MainActor
    private func openNewTaskWithToday() throws -> XCUIElement {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let field = UITestLaunch.quickAddField(app)
        guard field.waitForExistence(timeout: 10), UITestLaunch.focusQuickAdd(app) else {
            throw XCTSkip("Quick add not available")
        }
        field.typeText(title)
        app.keyboards.buttons["Return"].tap()

        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the new task should appear")
        if app.keyboards.count > 0 { app.swipeDown() }
        UITestLaunch.tapCenter(row)
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "task detail should open")

        let chip = app.buttons[Self.trigger]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the date chip should be on the When row")
        chip.tap()
        let today = app.buttons[Self.today].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the date sheet should offer Today")
        today.tap()
        XCTAssertTrue(waitForChip(chip, notLabelled: Self.noDueDate),
                      "after Today the chip should show a date, got \(chip.label)")
        return chip
    }

    @MainActor
    private func clearAndExpectNoDueDate(_ chip: XCUIElement) throws {
        let title = self.title
        chip.tap()
        let none = app.buttons[Self.noDueDate].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "the date sheet should offer No due date")
        none.tap()

        // Past the sheet's dismissal, the picker's 0.3s auto-save and the save's round trip.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(chip.label.contains(Self.noDueDate),
                      "after No due date the chip must say so, got \(chip.label)")

        // And the server agrees: reopening drains the journal and refetches the task.
        app.buttons[Self.back].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the task should still be listed")
        Thread.sleep(forTimeInterval: 3)
        UITestLaunch.tapCenter(row)
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "task detail should reopen")
        Thread.sleep(forTimeInterval: 5)
        let reopened = app.buttons[Self.trigger]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(reopened.label.contains(Self.noDueDate),
                      "after reopening the task it must still have no date, got \(reopened.label)")
    }

    private func waitForChip(_ chip: XCUIElement, notLabelled text: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !chip.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// `InlineDatePicker`'s trigger, and the English `picker.*` strings the suite runs under.
    static let trigger = "datePicker.trigger"
    static let today = "Today"
    static let noDueDate = "No due date"
    static let timeTrigger = "timePicker.trigger"
    static let repeatTrigger = "repeatPicker.trigger"
    static let morning = "Morning"
    static let daily = "Daily"
    static let back = "taskDetail.back"
}
