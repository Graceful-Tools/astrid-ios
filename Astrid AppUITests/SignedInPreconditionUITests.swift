//  SignedInPreconditionUITests.swift
//  The suite must not be able to pass while signed out (task 44a9cea5).
//
//  This is the regression guard for the failure that made the task worth reopening. The test
//  account existed, the keychain exception for it existed, and the suite still ran signed OUT
//  — because the credential never reached the app. Every affected test responded by SKIPPING
//  itself, so `xcodebuild` exited 0 and the run reported SUCCEEDED while asserting nothing.
//
//  A skip is the wrong response to a broken harness. Skipping is for "this run was not given
//  an account", which is a legitimate way to run the suite. It is not for "this run was given
//  an account and could not use it" — that is a fault, and it has to be loud, or the next
//  person to break the injection finds out the same way this was found out: by looking at a
//  screenshot weeks later and noticing the welcome screen.
//
//  So: no session supplied → skip, and say so. Session supplied → the app MUST be signed in.

import XCTest

final class SignedInPreconditionUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// The welcome screen's canonical marker. "Sign in with Apple" is NOT it — that button is
    /// behind the "Sign in" button, so a check for it returns false on the welcome screen and
    /// reads as "signed in". Half the suite made that mistake and skipped one step later with
    /// a misleading reason ("No tasks found" on an account that was never loaded).
    @MainActor
    private func welcomeScreenIsShowing(timeout: TimeInterval = 10) -> Bool {
        app.buttons["Use without account"].waitForExistence(timeout: timeout)
    }

    @MainActor
    func testASuppliedSessionActuallySignsTheAppIn() throws {
        try XCTSkipUnless(UITestLaunch.hasSession,
                          "No session supplied — run `npm run test:ui`, which mints one.")

        app.launch()

        XCTAssertFalse(
            welcomeScreenIsShowing(),
            """
            A session was supplied and the app still launched signed out.

            This is the harness failing, not the app. Check, in order:
              1. `Astrid AppUITests/UITestSession.plist` exists and is copied into the bundle
              2. `UITestSession.injectedCookie` accepts the flag the runner passes
              3. the session has not expired — mint a fresh one with
                 `cd ../astrid-web && npx tsx scripts/uitest-account.ts --cookie`

            Do NOT convert this into a skip. The whole point of task 44a9cea5 is that a
            signed-out suite must never report success again.
            """)
    }

    /// The suite is only useful signed in if the account has something in it. An account with
    /// no lists sends every data-driven test down its "nothing to work with" skip path, which
    /// is the same silent-success problem one step further along.
    @MainActor
    func testTheSignedInAccountHasItsFixtures() throws {
        try XCTSkipUnless(UITestLaunch.hasSession, "No session supplied.")

        app.launch()
        XCTAssertFalse(welcomeScreenIsShowing(), "Not signed in — see the test above.")

        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'My Tasks'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20),
                      "Signed in, but the task list never appeared.")

        // Look for a fixture BY NAME rather than counting cells.
        //
        // Counting was the first attempt and it was useless: the sidebar contributes cells of
        // its own ("My Tasks", "Search tasks…", "Add List"), so `cells.count > 0` was true on a
        // screen showing no tasks at all. It passed while the landing view read "My Tasks, 0",
        // and the tests underneath went on tapping sidebar rows and wondering why task detail
        // never opened.
        //
        // The fixtures being merely PRESENT on the server is also not enough — "My Tasks"
        // filters on `assigneeId == currentUserId`, so a fixture that is only created by the
        // account is invisible here. Naming one is the only check that covers both.
        let fixture = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'UITEST Fixture'")).firstMatch

        XCTAssertTrue(
            fixture.waitForExistence(timeout: 20),
            """
            Signed in, but no fixture task is visible on My Tasks.

            Either the account has not been seeded, or its tasks are not ASSIGNED to it —
            My Tasks filters on assignee, not creator, so unassigned fixtures exist on the
            server and show up nowhere in the app.

            Reseed with `cd ../astrid-web && npx tsx scripts/uitest-account.ts`.
            """)
    }
}
