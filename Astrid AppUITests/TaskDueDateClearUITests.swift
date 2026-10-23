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
        XCTAssertTrue(waitForChip(time, notLabelled: Self.morningUnset),
                      "after Morning the time chip should show a time, got \(time.label)")
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
        XCTAssertTrue(waitForLabel(repeatChip, toContain: Self.daily),
                      "after Daily the repeat chip should say so, got \(repeatChip.label)")
        try clearAndExpectNoDueDate(chip)
    }

    /// Journey 6 of the E2E set (AITD-528): Today, Morning and Daily all reach the server, and
    /// No due date then clears the date there too — not just on the chip.
    @MainActor
    func testTodayMorningDailyReachTheServerThenClear_AITD528() throws {
        try XCTSkipUnless(UITestAPI.isAvailable, "needs a session to ask the server")
        let chip = try openNewTaskWithToday()
        let time = app.buttons[Self.timeTrigger]
        XCTAssertTrue(time.waitForExistence(timeout: 5), "a dated task offers a time")
        time.tap()
        let morning = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", Self.morning)).firstMatch
        XCTAssertTrue(morning.waitForExistence(timeout: 5), "the time sheet should offer Morning")
        morning.tap()
        XCTAssertTrue(waitForChip(time, notLabelled: Self.morningUnset),
                      "after Morning the time chip should show a time, got \(time.label)")
        let repeatChip = app.buttons[Self.repeatTrigger]
        XCTAssertTrue(repeatChip.waitForExistence(timeout: 5), "a dated task offers a repeat")
        repeatChip.tap()
        let daily = app.buttons[Self.daily].firstMatch
        XCTAssertTrue(daily.waitForExistence(timeout: 5), "the repeat sheet should offer Daily")
        daily.tap()
        XCTAssertTrue(waitForLabel(repeatChip, toContain: Self.daily),
                      "after Daily the repeat chip should say so, got \(repeatChip.label)")

        try UITestAPI.waitForTask(titled: title, "a dated, daily task") {
            $0.dueDateTime != nil && $0.repeating == "daily"
        }
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
        XCTAssertTrue(waitForChip(chip, notLabelled: Self.noDueDate),
                      "after Today the chip should show a date, got \(chip.label)")
        chip.tap()
        let none = app.buttons[Self.noDueDate].firstMatch
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
        XCTAssertTrue(waitForLabel(chip, toContain: Self.noDueDate),
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
        field.typeText(title)
        // iPad's keyboard names the key "return", and with a hardware keyboard there is none.
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() } else { field.typeText("\n") }

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

        // Past the sheet's dismissal, the picker's 0.3s auto-save and the save's round trip —
        // polled rather than slept (AITD-528).
        XCTAssertTrue(waitForLabel(chip, toContain: Self.noDueDate),
                      "after No due date the chip must say so, got \(chip.label)")

        // The server agrees — asked directly when the run has a session to ask with (AITD-528).
        if UITestAPI.isAvailable {
            try UITestAPI.waitForTask(titled: title, "no due date") { $0.dueDateTime == nil }
        }

        // And so does the app after a round trip: reopening drains the journal and refetches.
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
        // Polled for long enough to catch the date coming BACK, which is the bug: the refetch
        // lands a moment after the detail opens.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            XCTAssertTrue(reopened.label.contains(Self.noDueDate),
                          "after reopening the task it must still have no date, got \(reopened.label)")
            Thread.sleep(forTimeInterval: 0.5)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitForChip(_ chip: XCUIElement, notLabelled text: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !chip.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func waitForLabel(_ element: XCUIElement, toContain text: String,
                              timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(text) { return true }
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
    /// The time chip's label before a time is chosen.
    static let morningUnset = "Add time"
    static let daily = "Daily"
    static let back = "taskDetail.back"
    static let close = "Close"
}
