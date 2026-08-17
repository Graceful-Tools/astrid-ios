//  UITestLaunch.swift
//  How the UI suite launches the app, signed in (tasks 44a9cea5, b7fd8f70).
//
//  THE FLAG. The launch arguments were wrong for months: every test passed `--uitesting` while
//  the app checked `-uiTesting`, so the six protections that keep a test run off Jon's real
//  account never engaged. The runner and the app now agree, and this is the only place the
//  suite spells it — a second literal is exactly how they drifted apart before.
//
//  THE CREDENTIAL, AND WHY IT IS NOT AN ENVIRONMENT VARIABLE. The first attempt read the
//  session from `ASTRID_UITEST_COOKIE` in the runner's environment. That never worked, and it
//  failed silently: measured 2026-08-16, a probe test printed `(absent)` for BOTH the plain
//  variable exported into `xcodebuild`'s shell and the documented `TEST_RUNNER_`-prefixed build
//  setting. xcodebuild does not forward either to the xctrunner process on this toolchain. So
//  no cookie was ever injected, the app launched signed out, and every test that needed an
//  account skipped itself — while the suite reported SUCCEEDED. The account existed; nothing
//  was using it.
//
//  What does work is a file inside the test bundle. `scripts/run-tests.sh --ui` mints a session
//  and writes `UITestSession.plist` next to this file; the synchronized group copies it into
//  the bundle; this reads it back. The file is gitignored and rewritten every run, because a
//  NextAuth session expires after 30 days and a committed token would stop working in a way
//  that looks exactly like the skip it replaced.
//
//  The environment is still checked first, so running from Xcode with a scheme variable set
//  keeps working, and so a future toolchain that does forward it needs no change here.

import Foundation
import XCTest

enum UITestLaunch {

    /// The flag the app recognises. Must match `UITestSession.flags`.
    static let flag = "-uiTesting"

    /// Launch argument the app reads the session from. Must match `UITestSession.cookieArgument`.
    static let cookieArgument = "-uiTestSessionCookie"

    /// Environment variable carrying the test account's session cookie.
    static let cookieKey = "ASTRID_UITEST_COOKIE"

    /// Generated bundle resource holding the same value. Written by the test script.
    static let sessionResourceName = "UITestSession"
    static let sessionResourceKey = "sessionCookie"

    /// The session this run was given, or nil when it was given none.
    ///
    /// Mint one with:
    ///
    ///     cd ../astrid-web && npx tsx scripts/uitest-account.ts --cookie
    ///
    /// `npm run test:ui` does it for you.
    static let sessionCookie: String? = {
        if let fromEnvironment = nonEmpty(ProcessInfo.processInfo.environment[cookieKey]) {
            return fromEnvironment
        }
        return nonEmpty(cookieFromBundle())
    }()

    /// True when this run is expected to be signed in. Tests that assert signed-in behaviour
    /// use this to tell "no credential was supplied" (a fair skip) from "a credential was
    /// supplied and did not work" (a failure, and the bug this file documents).
    static var hasSession: Bool { sessionCookie != nil }

    /// The one way the suite launches the app. Every test target file uses this, so the flag
    /// and the credential cannot drift apart between suites — they already did once, and the
    /// suites that lacked the block skipped for a different reason than the ones that had it.
    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [flag]
        if let cookie = sessionCookie {
            // Both channels: the argument is what the app reads first, the environment is
            // there because an argument list is visible in `ps` and an environment is not.
            app.launchArguments += [cookieArgument, cookie]
            app.launchEnvironment[cookieKey] = cookie
        }
        return app
    }

    /// Skips the calling test when the app is not signed in — using the marker that is
    /// actually on the welcome screen.
    ///
    /// Most suites checked `app.buttons["Sign in with Apple"]`, which is NOT on that screen:
    /// the welcome screen offers "Sign in" and "Use without account", and the provider buttons
    /// are one tap further in. So the check returned false on a signed-out app, every test read
    /// that as signed in, and each then skipped one step later with a reason that pointed
    /// somewhere else entirely — "No tasks found" on an account that had never loaded. That is
    /// why the real cause took so long to find, and why the marker lives in one place now.
    @MainActor
    static func skipUnlessSignedIn(_ app: XCUIApplication,
                                   timeout: TimeInterval = 5) throws {
        guard app.buttons["Use without account"].waitForExistence(timeout: timeout)
                || app.buttons["Sign in"].exists
        else { return }

        throw XCTSkip(hasSession
            ? "Signed out despite being given a session — see SignedInPreconditionUITests."
            : "No test-account session — run `npm run test:ui`, which mints one.")
    }

    /// Identifier the app stamps on every task row. Must match `TaskRowView`.
    static let taskRowIdentifier = "taskRow"

    /// The task rows on screen.
    ///
    /// **`isHittable` is useless in this app and must not be used as a filter.** Measured
    /// 2026-08-16 on iPhone 17, with the task list showing and five fixture tasks visible:
    ///
    /// ```
    /// taskRow matches=28  hittable=0
    /// cells=19            hittable=0
    /// fixtureTexts=5      hittable=0
    /// ```
    ///
    /// Everything reports not-hittable, including rows a person can plainly see and tap.
    ///
    /// That measurement retired two earlier explanations, both of which were wrong and both of
    /// which read as app bugs. The "not hittable" failures across five files were blamed on the
    /// closed sidebar keeping its rows in the accessibility tree; they were not — the sidebar
    /// was incidental, and every element in the app answers the same way. Filtering on
    /// `isHittable` then returns NOTHING, which turned those same tests into "No tasks found in
    /// list" — a worse lie than the failure it replaced, because an empty list looks like a
    /// fixture problem.
    ///
    /// The identifier is what actually discriminates, and it does work: 28 matches on a screen
    /// with five tasks, because SwiftUI stamps it on nested elements too. Take the first.
    @MainActor
    static func visibleRows(_ app: XCUIApplication) -> [XCUIElement] {
        let rows = app.descendants(matching: .any)
            .matching(identifier: taskRowIdentifier)
            .allElementsBoundByIndex
        if !rows.isEmpty { return rows }

        // Screens with no task rows — the lists screen, for one — still need "the first row on
        // screen". Falling back keeps those callers working rather than making every one of
        // them special-case the identifier.
        return app.cells.allElementsBoundByIndex
    }

    /// Tap an element that `isHittable` refuses to vouch for.
    ///
    /// `tap()` consults hittability first and refuses with "Neither element nor any descendant
    /// has keyboard focus" / "not hittable" — which, given the measurement above, it would do
    /// for every row in this app. A coordinate tap goes straight to the point and is how these
    /// tests can interact with the list at all.
    @MainActor
    static func tapCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Identifier the app stamps on the quick-add field. Must match `QuickAddTaskView`.
    static let quickAddFieldIdentifier = "quickAdd.field"

    /// The quick-add field, whatever element type it happens to be.
    ///
    /// The suite used to ask for `app.textFields` with a `placeholderValue` containing "task",
    /// which could never match: the field is a `TextEditor`, which XCUITest exposes as a text
    /// VIEW, and its placeholder is a separate `Text` so `placeholderValue` is empty. Four tests
    /// reported "Quick add task field not found", which reads as the field being missing rather
    /// than the query being wrong.
    ///
    /// Matching on `descendants(matching: .any)` rather than a specific type means a future
    /// change from TextEditor to TextField does not silently break this again.
    @MainActor
    static func quickAddField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: quickAddFieldIdentifier).firstMatch
    }

    /// Tap the quick-add field and wait until it can actually receive text.
    ///
    /// `tap()` returns as soon as the tap is delivered, not when focus has landed, so typing
    /// straight afterwards races the keyboard coming up. XCUITest reports that as
    /// "Neither element nor any descendant has keyboard focus", which reads like the field is
    /// wrong rather than early — and it only bites the first test in a class, while the app is
    /// still settling, so it looks like a flake rather than a missing wait.
    ///
    /// Returns false when focus never arrives, so callers can skip rather than fail obscurely.
    @MainActor
    @discardableResult
    static func focusQuickAdd(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let field = quickAddField(app)
        guard field.waitForExistence(timeout: timeout) else { return false }
        field.tap()
        return app.keyboards.element.waitForExistence(timeout: timeout)
    }

    /// The first row on the current screen, or nil when nothing is on screen yet.
    @MainActor
    static func firstVisibleRow(_ app: XCUIApplication) -> XCUIElement? {
        visibleRows(app).first
    }

    /// Waits for a row to appear, then returns it. Nil means the screen never populated —
    /// callers skip on that, since it is a state the harness cannot distinguish from a list
    /// that is legitimately empty.
    @MainActor
    static func waitForFirstVisibleRow(_ app: XCUIApplication,
                                       timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = firstVisibleRow(app) { return row }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    // MARK: - Private

    private static func cookieFromBundle() -> String? {
        let bundle = Bundle(for: UITestLaunchBundleToken.self)
        guard let url = bundle.url(forResource: sessionResourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                     format: nil) as? [String: Any]
        else { return nil }
        return plist[sessionResourceKey] as? String
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Only exists to locate the test bundle.
private final class UITestLaunchBundleToken {}
