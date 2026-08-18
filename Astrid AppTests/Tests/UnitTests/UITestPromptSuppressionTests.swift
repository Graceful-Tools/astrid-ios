//  UITestPromptSuppressionTests.swift
//  Regression guard for Task b86c97c5 — "[ios] under UI test, tapping a task row does not open
//  Task Details".
//
//  THE CAUSE, finally measured. Three earlier hypotheses missed it, and one of them was written
//  into `UITestLaunch` as settled fact: that `isHittable` is simply broken in this app, because
//  every element reported false, including rows a person can plainly see. It is not broken. A
//  dump of the accessibility tree three seconds after launch ends with:
//
//      Alert, {{41.0, 355.0}, {320.0, 192.0}}, label: 'Enable Push Notifications'
//        ... Button, label: 'Not Now'   Button, label: 'Enable'
//
//  A modal alert was sitting over the app. Everything under a modal reports not-hittable and
//  swallows taps — so the row tap never reached the row, "Task Details" never appeared, and the
//  suite blamed the query. `AstridApp` fires that prompt one second after `isAuthenticated`
//  turns true, and the whole point of the UI suite's injected session is to turn it true. So
//  the suite was guaranteed to be interrupted, on every run, by construction. The review prompt
//  ("Loving Astrid?") is armed the same way five seconds later.
//
//  A `-uiTesting` run is meant to be hermetic. An interrupting prompt is exactly the kind of
//  thing that must not fire in one.

import XCTest
@testable import Astrid_App

final class UITestPromptSuppressionTests: XCTestCase {

    private let flag = "-uiTesting"

    /// THE RULE: a UI-test run shows no interrupting prompts.
    func testAUITestRunSuppressesInterruptingPrompts() {
        XCTAssertTrue(UITestSession.suppressesInterruptingPrompts(arguments: [flag]),
                      "A modal prompt during a UI test blocks every tap in the app")
    }

    /// And a normal run still shows them — this suppresses prompts under test, it does not
    /// remove a feature.
    func testANormalRunStillPrompts() {
        XCTAssertFalse(UITestSession.suppressesInterruptingPrompts(arguments: []))
        XCTAssertFalse(UITestSession.suppressesInterruptingPrompts(arguments: ["-someOtherFlag"]))
    }

    /// The rule is derived from the flag, not spelled a second time. Six places once re-derived
    /// `-uiTesting` and all six were wrong together; that is why `UITestSession` owns it.
    func testTheRuleFollowsEverySpellingOfTheFlag() {
        for spelling in UITestSession.flags {
            XCTAssertTrue(UITestSession.suppressesInterruptingPrompts(arguments: [spelling]),
                          "\(spelling) must suppress prompts like every other spelling")
        }
    }

    /// The notification prompt asks the shared rule rather than checking the flag itself.
    func testTheNotificationPromptIsSuppressedUnderTest() async {
        let decision = await NotificationPromptManager.shared
            .shouldPromptForNotifications(isUITesting: true)
        XCTAssertFalse(decision.shouldPrompt,
                       "The push prompt must not open over a UI test run")
    }

    /// So does the review prompt — five seconds later, over the same tests.
    func testTheReviewPromptIsSuppressedUnderTest() async {
        let shows = await ReviewPromptManager.shared.shouldPromptForReview(isUITesting: true)
        XCTAssertFalse(shows, "The review prompt must not open over a UI test run")
    }
}
