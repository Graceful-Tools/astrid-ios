//  MacUITestLaunch.swift
//  The one place the Mac UI suite launches the app and reaches the shell.
//
//  Every Mac UI file used to append the `-uiTesting` literal itself and copy a seven-line
//  "click Continue-without-an-account, wait for the sidebar" loop. iOS already learned this
//  lesson (`UITestLaunch`, after the `-uiTesting` / `--uitesting` drift bug); this is the Mac half.

import XCTest

enum MacUITestLaunch {
    /// The flag `MacUITestArgs.isUITesting` reads. One literal, one place.
    static let uiTestingFlag = "-uiTesting"

    /// An app configured for UI testing but not yet launched, so a test can add arguments.
    static func makeApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [uiTestingFlag] + arguments
        return app
    }

    /// Reach the app shell from wherever launch landed.
    ///
    /// The offline choice persists in the shared container, so a second run may launch straight
    /// into the shell; the app may also already be signed in (it reads the real keychain). Take
    /// whichever screen shows up. Returns the My Tasks sidebar row, whose `exists` says whether
    /// the shell was reached within `timeout`.
    @MainActor
    @discardableResult
    static func enterShell(_ app: XCUIApplication, timeout: TimeInterval = 30) -> XCUIElement {
        let offline = app.descendants(matching: .any).matching(identifier: "login.offline").firstMatch
        let myTasks = app.descendants(matching: .any).matching(identifier: "sidebar.myTasks").firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !myTasks.exists {
            if offline.exists { offline.click() }
            _ = myTasks.waitForExistence(timeout: 2)
        }
        return myTasks
    }
}
