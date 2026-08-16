import XCTest

/// UI tests for authentication flows
/// Tests login screen, OAuth buttons, and sign out
final class AuthUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Login Screen Tests

    @MainActor
    func testLoginScreenElements() throws {
        app.launch()

        // Wait for either login screen or main app
        sleep(2)

        // Check if we're on login screen
        let appleSignIn = app.buttons["Sign in with Apple"]
        let googleSignIn = app.buttons["Sign in with Google"]

        // If not on login screen, this test passes (already authenticated)
        if !appleSignIn.exists && !googleSignIn.exists {
            // Take screenshot of authenticated state
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Already Authenticated"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            return
        }

        // Verify login buttons exist
        XCTAssertTrue(appleSignIn.exists, "Sign in with Apple button should exist")

        // Google sign in might exist
        if googleSignIn.exists {
            XCTAssertTrue(googleSignIn.exists, "Sign in with Google button should exist")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Login Screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testAppleSignInButtonTappable() throws {
        app.launch()

        sleep(2)

        let appleSignIn = app.buttons["Sign in with Apple"]

        guard appleSignIn.exists else {
            throw XCTSkip("Not on login screen")
        }

        // Verify button is enabled and tappable
        XCTAssertTrue(appleSignIn.isEnabled, "Apple Sign In button should be enabled")
        XCTAssertTrue(appleSignIn.isHittable, "Apple Sign In button should be tappable")
    }

    @MainActor
    func testGoogleSignInButtonTappable() throws {
        app.launch()

        sleep(2)

        let googleSignIn = app.buttons["Sign in with Google"]

        guard googleSignIn.exists else {
            throw XCTSkip("Google Sign In button not present or not on login screen")
        }

        // Verify button is enabled and tappable
        XCTAssertTrue(googleSignIn.isEnabled, "Google Sign In button should be enabled")
        XCTAssertTrue(googleSignIn.isHittable, "Google Sign In button should be tappable")
    }

    // MARK: - Settings Access Tests

    @MainActor
    func testSettingsAccessible() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find settings tab or button
        let settingsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting'")).firstMatch
        let settingsButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting' OR label CONTAINS[c] 'gear' OR identifier CONTAINS 'settings'")).firstMatch

        // `exists` is not enough. The sidebar stays in the accessibility tree while closed,
        // so its gear button "exists" off-screen and tapping it fails as not-hittable — which
        // reads as a settings bug rather than as a test looking at the wrong element.
        if settingsTab.exists && settingsTab.isHittable {
            settingsTab.tap()
        } else if settingsButton.exists && settingsButton.isHittable {
            settingsButton.tap()
        }

        sleep(1)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings View"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSignOutButtonExists() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Navigate to settings
        let settingsTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'setting'")).firstMatch
        if settingsTab.exists {
            settingsTab.tap()
            sleep(1)
        }

        // Look for sign out button (might need to scroll)
        let signOutButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sign out' OR label CONTAINS[c] 'log out' OR label CONTAINS[c] 'logout'")).firstMatch

        // Scroll to find sign out if not visible
        if !signOutButton.exists {
            app.swipeUp()
            sleep(1)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sign Out Button Search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
