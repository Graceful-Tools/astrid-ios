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
}
