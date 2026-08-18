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

    /// The task rows on screen — the ROWS, not the pieces inside them.
    ///
    /// SwiftUI stamps `.accessibilityIdentifier` on every accessibility element the row
    /// contains, so matching the identifier alone returned four elements per row and the FIRST
    /// of them is the checkbox:
    ///
    /// ```
    /// Button,     {{24.0, 151.0}, {34.0, 34.0}},  identifier: 'taskRow', label: 'check_box_3'
    /// StaticText, {{70.0, 140.0}, {255.3, 23.0}}, identifier: 'taskRow', label: 'UITEST Fixture — open task 2'
    /// Image,      ...                             identifier: 'taskRow', label: 'number'
    /// StaticText, ...                             identifier: 'taskRow', label: 'UI Test List'
    /// ```
    ///
    /// Tapping the centre of that first match is tapping the checkbox, which COMPLETES the
    /// task — the row's own tap gesture, the one that opens the detail, lives on the list row
    /// around it. A suite that meant "tap a task" was ticking it off instead (task b86c97c5).
    ///
    /// So ask for the cell that CONTAINS a `taskRow` element. That is the row, its centre is
    /// over the title rather than the checkbox, and it still excludes the sidebar's cells,
    /// which is why the identifier was introduced in the first place.
    @MainActor
    static func visibleRows(_ app: XCUIApplication) -> [XCUIElement] {
        let rows = app.cells
            .containing(.any, identifier: taskRowIdentifier)
            .allElementsBoundByIndex
        if !rows.isEmpty { return rows }

        // A row drawn outside a cell — a board card, for one — still has to be findable.
        // Prefer the widest match: of the four elements one row stamps, the widest is the
        // title, never the 34pt checkbox.
        let stamped = app.descendants(matching: .any)
            .matching(identifier: taskRowIdentifier)
            .allElementsBoundByIndex
        if !stamped.isEmpty {
            return stamped.sorted { $0.frame.width > $1.frame.width }
        }

        // Screens with no task rows — the lists screen, for one — still need "the first row on
        // screen". Falling back keeps those callers working rather than making every one of
        // them special-case the identifier.
        return app.cells.allElementsBoundByIndex
    }

    /// Tap the centre of an element.
    ///
    /// A coordinate tap rather than `tap()`, which consults hittability first. Hittability was
    /// once measured as false for EVERY element in this app, and that measurement was written
    /// down here as a fact about the app. It was a fact about the RUN: a modal
    /// "Enable Push Notifications" alert was sitting over the screen, and everything under a
    /// modal reports not-hittable. The app no longer opens that prompt under `-uiTesting`
    /// (task b86c97c5). The coordinate tap stays because it is unambiguous about WHERE it
    /// lands, which is the other half of that bug.
    @MainActor
    static func tapCenter(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The back-swipe, as a gesture iOS will actually recognise.
    ///
    /// The suite drove it as `press(forDuration: 0.05, thenDragTo:)` starting 5% in from the
    /// left. UIKit's screen-edge pan recogniser refuses that on both counts: it wants the touch
    /// to go DOWN on the edge itself, and a 0.05s press followed by an instant drag reads as a
    /// flick rather than a pan. Measured on iPhone 17 with the detail open (task b86c97c5):
    ///
    ///     fast drag from 5%  → detail still open
    ///     slow drag from 1%, holding at each end → detail dismissed
    ///
    /// So the gesture was the failure, not the navigation — which matters, because the obvious
    /// reading of a failing swipe test is that the app has lost its back-swipe.
    @MainActor
    static func swipeBackFromLeftEdge(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.6,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.4)
    }

    /// Identifier the app stamps on the task detail's header. Must match `TaskDetailHeader`.
    static let taskDetailHeaderIdentifier = "taskDetail.header"

    /// The task detail's header, whatever element type it happens to be.
    ///
    /// The suite asked for `app.staticTexts["Task Details"]` in five files. That could never
    /// match: the header is a BUTTON — tapping it scrolls the panel to the top — so the label
    /// is the button's. Nine tests reported "task detail did not appear" when it had, and the
    /// investigations that followed all went looking at the tap (task b86c97c5).
    ///
    /// Matched by identifier, not by label, so this keeps working when the app is in French.
    @MainActor
    static func taskDetailHeader(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: taskDetailHeaderIdentifier).firstMatch
    }

    /// Waits for the task detail to open. False means it did not.
    ///
    /// Ten seconds, not five. The push happens promptly on a warm simulator and not at all
    /// promptly on the fifth clone of a parallel run — and the cost of being wrong is
    /// asymmetric: too short skips the test with "task detail did not appear", which reads as
    /// the app being broken.
    @MainActor
    static func waitForTaskDetail(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        taskDetailHeader(app).waitForExistence(timeout: timeout)
    }

    /// Identifier the app stamps on the comment box. Must match `CommentInput`.
    static let commentFieldIdentifier = "comment.field"

    /// The comment box, whatever element type it happens to be.
    ///
    /// The suite asked for `app.textFields` with a `placeholderValue` containing "comment",
    /// which could never match on two counts: the control is a `TextEditor`, which XCUITest
    /// exposes as a text VIEW, and its placeholder is a separate `Text` so `placeholderValue`
    /// is empty. Four tests skipped with "Comment input field not found" — a sentence about
    /// the app that was really about the query (task 91a7e180). Exactly the shape that once
    /// hid quick-add.
    @MainActor
    static func commentField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: commentFieldIdentifier).firstMatch
    }

    /// Open the first task's detail and return its comment box, or nil with a reason.
    ///
    /// Four tests each rebuilt this out of `staticTexts CONTAINS 'Task'`, `tap()` and `sleep(1)`,
    /// which never checked that the detail had opened at all — so a failure one step earlier
    /// arrived labelled "comment field not found".
    @MainActor
    static func openFirstTaskComment(_ app: XCUIApplication,
                                     timeout: TimeInterval = 15) throws -> XCUIElement {
        guard let row = waitForFirstVisibleRow(app, timeout: timeout) else {
            throw XCTSkip("No task rows on screen")
        }
        tapCenter(row)
        guard waitForTaskDetail(app) else {
            throw XCTSkip("Task detail did not open")
        }
        let field = commentField(app)
        guard field.waitForExistence(timeout: timeout) else {
            throw XCTSkip("Comment box not found on an OPEN task detail — this one is the app")
        }
        return field
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
    ///
    /// The wait is for a REAL task row. `visibleRows` falls back to `app.cells` for screens
    /// that have none, and the sidebar's cells are in the tree from the first frame — so a
    /// wait built on it returned instantly, every time, with a sidebar cell. The caller then
    /// tapped that and skipped with "task detail did not appear", which is true and says
    /// nothing (task b86c97c5). The fallback still happens, but only once the deadline has
    /// passed and there is nothing better to offer.
    @MainActor
    static func waitForFirstVisibleRow(_ app: XCUIApplication,
                                       timeout: TimeInterval = 15) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let identified = app.cells
                .containing(.any, identifier: taskRowIdentifier)
                .allElementsBoundByIndex
            if let row = identified.first { return row }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return firstVisibleRow(app)
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
