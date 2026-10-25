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

    /// Launch argument the app reads the session from. Must match `UITestSession.cookieArgument`.
    static let cookieArgument = "-uiTestSessionCookie"
    /// Must match `UITestSession.baseURLArgument`.
    static let baseURLArgument = "-uiTestBaseURL"

    /// English whatever the host is set to (AITD-526). Controls are found by identifier; what
    /// this keeps meaningful is the menu-bar titles (`View`, `Task ▸ Complete`, AppKit's
    /// `Undo …`), which have no identifiers to find them by.
    static let englishArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    /// The list sheet's Create/Save button. Must match `MacListEditSheet.saveButton`.
    static let listSaveIdentifier = "listEdit.save"

    /// A task row's checkbox, by state. Must match `MacTaskRow`.
    static let openCheckboxIdentifier = "taskRow.checkbox.open"
    static let completedCheckboxIdentifier = "taskRow.checkbox.completed"

    /// An app configured for UI testing but not yet launched, so a test can add arguments.
    ///
    /// `signedIn: false` (the default) is the hermetic launch: no credential, so the app shows
    /// the sign-in screen and the offline shell is one click away. `signedIn: true` hands it this
    /// run's per-run account (AITD-529) — the same `UITestSession.plist` the iOS suite reads,
    /// through `UITestSessionResource`; the app signs in with it and nothing else.
    static func makeApp(arguments: [String] = [], signedIn: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [uiTestingFlag] + englishArguments + arguments
        if signedIn, let cookie = UITestSessionResource.sessionCookie {
            app.launchArguments += [cookieArgument, cookie]
            app.launchEnvironment[UITestSessionResource.cookieEnvironmentKey] = cookie
            if UITestSessionResource.baseURL != UITestSessionResource.productionBaseURL {
                app.launchArguments += [baseURLArgument, UITestSessionResource.baseURL]
            }
        }
        return app
    }

    /// Reach the app shell from wherever launch landed.
    ///
    /// The offline choice persists in the shared container, so a second run may launch straight
    /// into the shell. Take whichever screen shows up. Never the user's account: under
    /// `-uiTesting` the keychain is blanked and astrid-core opens a scratch cache, so nothing this
    /// suite writes can be delivered as the user (AITD-448). Returns the My Tasks sidebar row,
    /// whose `exists` says whether the shell was reached within `timeout`.
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
