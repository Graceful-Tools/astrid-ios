//  Astrid_MacUITests.swift
//  Astrid for Mac — smoke UI coverage (Task 6c30df95). Replaces the empty template test with
//  real product assertions. Launches with -uiTesting for a deterministic login screen (onboarding
//  skipped) and asserts the sign-in UI and the offline-mode path.

import XCTest

final class Astrid_MacUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = MacUITestLaunch.makeApp()
        app.launch()
        return app
    }

    /// The app launches to the foreground on the sign-in screen, which offers the expected
    /// entry points: Passkey and offline. (`testLaunchesToSignInScreen` folded in — AITD-529.)
    @MainActor
    func testSignInOptionsPresent() {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "App should launch to foreground")
        XCTAssertTrue(app.buttons["login.passkey"].waitForExistence(timeout: 15),
                      "Sign-in screen should show the Passkey button")
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10),
                      "‘Continue without an account’ should be available")
    }

    /// Choosing “Continue without an account” enters the app shell (local/offline mode).
    @MainActor
    func testOfflineModeEntersShell() {
        let app = launchApp()
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 15))
        offline.click()
        // The authenticated shell shows the sidebar with the My Tasks row.
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        XCTAssertTrue(myTasks.waitForExistence(timeout: 15),
                      "Offline mode should enter the shell with the sidebar")
    }

    // MARK: - Interaction flows (Task 60dee573) — hermetic via offline mode

    /// Enter the offline shell (shared by the interaction tests below).
    @MainActor private func enterOfflineShell() -> XCUIApplication {
        let app = launchApp()
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 15))
        offline.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sidebar.myTasks")
            .firstMatch.waitForExistence(timeout: 15))
        return app
    }

    /// The caret still lands in quick-add on its own — you can type straight into a selected list
    /// without clicking the field first (task b71850e6).
    ///
    /// This guards the OTHER half of AITD-333. That task made the auto-focus wait for the user's
    /// first interaction with the window, because focusing a text field before anyone has touched
    /// the app summons macOS's Password AutoFill popover and leaves it stranded on screen with
    /// nothing in it. The risk in that change is over-correcting into the b71850e6 bug — "add task
    /// didn't always have a cursor prompt" — so this types WITHOUT clicking the field: the text can
    /// only land if the caret got there by itself, after the clicks that selected the list.
    @MainActor
    func testQuickAddTakesTheCaretWithoutBeingClicked() {
        let app = enterOfflineShell()
        let listName = "UITest Focus \(Int.random(in: 1000...9999))"
        let taskTitle = "UITest autofocus \(Int.random(in: 1000...9999))"

        app.descendants(matching: .any).matching(identifier: "sidebar.newList").firstMatch.click()
        let nameField = app.descendants(matching: .any).matching(identifier: "listEdit.name").firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeText(listName)
        app.buttons[MacUITestLaunch.listSaveIdentifier].firstMatch.click()

        let listRow = app.staticTexts[listName].firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 10))
        listRow.click()

        app.activate()
        let quickAdd = app.descendants(matching: .any).matching(identifier: "tasks.quickAdd").firstMatch
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10))

        // NOT quickAdd.click() — that is the whole point. Type at the window and let the caret
        // prove where it is.
        app.typeText(taskTitle + "\n")

        XCTAssertTrue(app.staticTexts[taskTitle].firstMatch.waitForExistence(timeout: 10),
                      "Typing without clicking produced no task — the quick-add caret never arrived")
    }

    /// My Tasks shows the branded empty state (not a blank pane) in a fresh offline account.
    @MainActor
    func testMyTasksShowsBrandedEmptyState() {
        let app = enterOfflineShell()
        app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch.click()
        let empty = app.descendants(matching: .any).matching(identifier: "emptyState.noTasks").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "My Tasks should show the branded empty state")
    }

    /// Sidebar Search opens the global search surface with its field focused-able.
    @MainActor
    func testSearchSurfaceOpens() {
        let app = enterOfflineShell()
        app.descendants(matching: .any).matching(identifier: "sidebar.search").firstMatch.click()
        let field = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search view should show its input field")

        // Capture the restyled surface (task 233144d9) for review.
        app.activate()
        let window = app.windows.firstMatch
        let shot = XCTAttachment(screenshot: window.exists ? window.screenshot()
                                                          : XCUIScreen.main.screenshot())
        shot.name = "search-surface"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The core E2E: create a list, quick-add a task into it, and see the row appear —
    /// entirely offline (optimistic local store), so it's hermetic.
    @MainActor
    func testCreateListAndQuickAddTask() {
        let app = enterOfflineShell()
        let listName = "UITest List \(Int.random(in: 1000...9999))"
        let taskTitle = "UITest task \(Int.random(in: 1000...9999))"

        // New List via the sidebar toolbar + sheet.
        app.descendants(matching: .any).matching(identifier: "sidebar.newList").firstMatch.click()
        let nameField = app.descendants(matching: .any).matching(identifier: "listEdit.name").firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeText(listName)
        app.buttons[MacUITestLaunch.listSaveIdentifier].firstMatch.click()

        // Select the new list. There is no sidebar filter to narrow it with — the list-name
        // search was removed in task 1b0f034d — so the row is found by its name directly.
        let listRow = app.staticTexts[listName].firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 10), "Created list should appear in the sidebar")
        listRow.click()

        // Quick-add floats at the bottom of the window (the app clamps its window to the visible
        // screen under -uiTesting so this is on-screen). Make sure our app is frontmost first.
        app.activate()
        let quickAdd = app.descendants(matching: .any).matching(identifier: "tasks.quickAdd").firstMatch
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10), "Quick-add should be available for a real list")
        quickAdd.click()
        quickAdd.typeText(taskTitle + "\n")

        // The optimistic row appears.
        XCTAssertTrue(app.staticTexts[taskTitle].firstMatch.waitForExistence(timeout: 10),
                      "Quick-added task should appear as a row")
    }
}
