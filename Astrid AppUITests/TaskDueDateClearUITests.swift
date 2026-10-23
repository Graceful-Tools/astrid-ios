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
        let morning = app.buttons[Self.morning].firstMatch
        XCTAssertTrue(morning.waitForExistence(timeout: 5), "the time sheet should offer Morning")
        morning.tap()
        // Picking a time saves and closes the sheet; the date chip is reachable again once it has.
        XCTAssertTrue(UITestLaunch.waitForDisappearance(morning), "the time sheet should close after Morning")
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
        XCTAssertTrue(UITestLaunch.waitForDisappearance(daily, timeout: 10), "the repeat sheet should close after Daily")
        try clearAndExpectNoDueDate(chip)
    }

    /// On iPad the date sheet is a fixed-height form sheet, and its content — the quick picks
    /// plus the whole calendar — is taller than it. The sheet clipped the overflow at both ends,
    /// so "No due date", the FIRST row, sat above the sheet's top edge where nothing could tap it
    /// (AITD-511, Jon's iPad screenshot). On iPhone the sheet is tall enough, so this one only
    /// means anything on iPad, in landscape where the sheet is shortest.
    @MainActor
    func testNoDueDateCanBeTappedOnIPad_AITD511() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("the clipped sheet is an iPad layout")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        // A fixture row rather than a quick-added task: the iPad layout only has to open one.
        guard let row = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw UITestFailure("No tasks on screen")
        }
        UITestLaunch.tapCenter(row)
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "task detail should open")
        let chip = app.buttons[Self.trigger]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the date chip should be on the When row")
        chip.tap()
        let today = app.buttons[Self.today].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the date sheet should offer Today")
        today.tap()
        XCTAssertTrue(UITestLaunch.waitForLabel(chip, contains: noDueDate, false, timeout: 5),
                      "after Today the chip should show a date, got \(chip.label)")
        chip.tap()
        let none = app.buttons[Self.noDueDateOption].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "the date sheet should offer No due date")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        // Not `isHittable`: SwiftUI hit-tests the clipped row where it would have been drawn, so
        // XCUITest called it hittable — and tapped it — while the screen showed nothing there.
        // What a person can reach is a row below the sheet's own bar.
        let close = app.navigationBars.buttons[Self.close].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the date sheet should have its Close")
        XCTAssertGreaterThanOrEqual(none.frame.minY, close.frame.maxY,
                                    "No due date must be drawn inside the sheet, not clipped above it")
        none.tap()
        XCTAssertTrue(UITestLaunch.waitForLabel(chip, contains: noDueDate),
                      "after No due date the chip must say so, got \(chip.label)")
    }

    /// A new task, opened, with Today picked — the chip it returns is the date trigger.
    @MainActor
    private func openNewTaskWithToday() throws -> XCUIElement {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let field = UITestLaunch.quickAddField(app)
        guard field.waitForExistence(timeout: 10), UITestLaunch.focusQuickAdd(app) else {
            throw UITestFailure("Quick add not available")
        }
        // A newline, not the Return key: the key is named per keyboard language, "return" on
        // iPad, and absent with a hardware keyboard.
        field.typeText(title + "\n")

        guard let row = UITestLaunch.waitForCreatedTask(app, titled: title) else {
            throw UITestFailure("the new task should appear")
        }
        // No swipe to put the keyboard away: it never did, and it scrolled the list back to the
        // top, out from under the row `waitForCreatedTask` had just scrolled into view (AITD-543).
        UITestLaunch.tapCenter(row)
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "task detail should open")

        let chip = app.buttons[Self.trigger]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the date chip should be on the When row")
        chip.tap()
        let today = app.buttons[Self.today].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the date sheet should offer Today")
        today.tap()
        XCTAssertTrue(UITestLaunch.waitForLabel(chip, contains: noDueDate, false, timeout: 5),
                      "after Today the chip should show a date, got \(chip.label)")
        return chip
    }

    @MainActor
    private func clearAndExpectNoDueDate(_ chip: XCUIElement) throws {
        let title = self.title
        chip.tap()
        let none = app.buttons[Self.noDueDateOption].firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "the date sheet should offer No due date")
        none.tap()

        // Past the sheet's dismissal and the picker's 0.3s auto-save: polled, not slept.
        XCTAssertTrue(UITestLaunch.waitForLabel(chip, contains: noDueDate),
                      "after No due date the chip must say so, got \(chip.label)")

        // And the server agrees: reopening drains the journal and refetches the task.
        app.buttons[Self.back].tap()
        // Found the way it was found the first time: scrolled into view, since the list comes
        // back at the top and the task sits below what is on screen (AITD-543).
        guard let row = UITestLaunch.waitForCreatedTask(app, titled: title, timeout: 10) else {
            throw UITestFailure("the task should still be listed")
        }
        UITestLaunch.tapCenter(row)
        XCTAssertTrue(UITestLaunch.waitForTaskDetail(app), "task detail should reopen")
        let reopened = app.buttons[Self.trigger]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        // The reopened detail first shows the cached task and then the refetched one, so the
        // label is waited on: a date that came back from the server shows up within this window,
        // and that is the regression. The old fixed 5s wait asserted the same thing, slower.
        let cleared = UITestLaunch.waitForLabel(reopened, contains: noDueDate)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(cleared, "after reopening the task it must still have no date, got \(reopened.label)")
        XCTAssertFalse(UITestLaunch.waitForLabel(reopened, contains: noDueDate, false, timeout: 3),
                       "the date must not come back once the refetch lands, got \(reopened.label)")
    }

    /// What the chip says with no date — read from the app's table, since the state is only in
    /// the label (AITD-526).
    private let noDueDate = UITestStrings.en("picker.no_due_date")

    /// `InlineDatePicker`'s trigger and the sheets' option identifiers (AITD-526): the controls
    /// are found by identifier, so a localized simulator cannot hide them.
    static let trigger = "datePicker.trigger"
    static let today = "datePicker.option.picker.today"
    static let noDueDateOption = "datePicker.option.none"
    static let timeTrigger = "timePicker.trigger"
    static let repeatTrigger = "repeatPicker.trigger"
    static let morning = "timePicker.option.picker.morning"
    static let daily = "repeatPicker.option.daily"
    static let back = "taskDetail.back"
    static let close = "sheet.close"
}
