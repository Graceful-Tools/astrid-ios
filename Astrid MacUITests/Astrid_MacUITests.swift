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
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        return app
    }

    /// The app launches and reaches the sign-in screen (a window + the Passkey button).
    @MainActor
    func testLaunchesToSignInScreen() {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "App should launch to foreground")
        let passkey = app.buttons["login.passkey"]
        XCTAssertTrue(passkey.waitForExistence(timeout: 15), "Sign-in screen should show the Passkey button")
    }

    /// The sign-in screen offers the expected entry points (Passkey + offline).
    @MainActor
    func testSignInOptionsPresent() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["login.passkey"].waitForExistence(timeout: 15))
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

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-uiTesting"]
            app.launch()
        }
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

    /// My Tasks shows the branded empty state (not a blank pane) in a fresh offline account.
    @MainActor
    func testMyTasksShowsBrandedEmptyState() {
        let app = enterOfflineShell()
        app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch.click()
        let empty = app.staticTexts.containing(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                                           "All clear", "All clear")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "My Tasks should show the branded empty state")
    }

    /// Sidebar Search opens the global search surface with its field focused-able.
    @MainActor
    func testSearchSurfaceOpens() {
        let app = enterOfflineShell()
        app.descendants(matching: .any).matching(identifier: "sidebar.search").firstMatch.click()
        let field = app.descendants(matching: .any).matching(identifier: "search.field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search view should show its input field")
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
        app.buttons["Create"].firstMatch.click()

        // Select the new list in the sidebar.
        let listRow = app.staticTexts[listName].firstMatch
        XCTAssertTrue(listRow.waitForExistence(timeout: 10), "Created list should appear in the sidebar")
        listRow.click()

        // Quick-add floats at the bottom; type a task and press return.
        let quickAdd = app.descendants(matching: .any).matching(identifier: "tasks.quickAdd").firstMatch
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10), "Quick-add should be available for a real list")
        quickAdd.click()
        quickAdd.typeText(taskTitle + "\n")

        // The optimistic row appears.
        XCTAssertTrue(app.staticTexts[taskTitle].firstMatch.waitForExistence(timeout: 10),
                      "Quick-added task should appear as a row")
    }
}
