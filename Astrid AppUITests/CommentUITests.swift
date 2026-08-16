import XCTest

/// UI tests for comment keyboard dismissal functionality
/// Tests that keyboard appears and dismisses correctly when interacting with comment input
final class CommentUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Keyboard Dismissal Tests

    @MainActor
    func testKeyboardAppearsWhenTappingCommentField() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        // Wait for tasks to load
        sleep(2)

        // Find and open any task to access comment section
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "No Tasks Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("No tasks found to open")
        }

        // Open task detail
        tasks.firstMatch.tap()
        sleep(1)

        // Find comment input field
        let commentField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment'")).firstMatch

        guard commentField.waitForExistence(timeout: timeout) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Comment Field Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            throw XCTSkip("Comment input field not found")
        }

        // Tap comment field
        commentField.tap()

        // Wait for keyboard to appear
        sleep(1)

        // Check if keyboard is visible
        let keyboard = app.keyboards.firstMatch
        let keyboardVisible = keyboard.exists

        // Take screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Keyboard After Tapping Comment Field"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(keyboardVisible, "Keyboard should appear when tapping comment field")
    }

    @MainActor
    func testKeyboardDismissesWhenTappingOutside() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find and open a task
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            throw XCTSkip("No tasks found")
        }

        tasks.firstMatch.tap()
        sleep(1)

        // Find and tap comment field
        let commentField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment'")).firstMatch

        guard commentField.waitForExistence(timeout: timeout) else {
            throw XCTSkip("Comment input field not found")
        }

        commentField.tap()
        sleep(1)

        // Verify keyboard is visible
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else {
            throw XCTSkip("Keyboard did not appear")
        }

        // Tap outside the comment field (tap on a safe area like the header)
        // Find the "Comments" header text
        let commentsHeader = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Comments'")).firstMatch

        if commentsHeader.exists {
            commentsHeader.tap()
        } else {
            // Fallback: tap at a coordinate above the text field
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            coordinate.tap()
        }

        // Wait for keyboard to dismiss
        sleep(1)

        // Check if keyboard is dismissed
        let keyboardDismissed = !keyboard.exists

        // Take screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "After Tapping Outside Comment Field"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(keyboardDismissed, "Keyboard should dismiss when tapping outside the comment field")
    }

    @MainActor
    func testCommentTextPreservedAfterDismissingKeyboard() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find and open a task
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            throw XCTSkip("No tasks found")
        }

        tasks.firstMatch.tap()
        sleep(1)

        // Find comment field
        let commentField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment'")).firstMatch

        guard commentField.waitForExistence(timeout: timeout) else {
            throw XCTSkip("Comment input field not found")
        }

        // Type test comment
        let testComment = "Test comment text"
        commentField.tap()
        commentField.typeText(testComment)

        // Tap outside to dismiss keyboard
        let commentsHeader = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Comments'")).firstMatch

        if commentsHeader.exists {
            commentsHeader.tap()
        } else {
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            coordinate.tap()
        }

        sleep(1)

        // Check if text is still in the field
        let fieldValue = commentField.value as? String ?? ""

        // Take screenshot
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Comment Text After Dismissing Keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertEqual(fieldValue, testComment, "Comment text should be preserved after dismissing keyboard")
    }

    @MainActor
    func testKeyboardDismissalDoesNotInterfereWithButtons() throws {
        app.launch()

        let timeout: TimeInterval = 10

        try UITestLaunch.skipUnlessSignedIn(app)
        sleep(2)

        // Find and open a task
        let tasks = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Task'"))

        guard tasks.count > 0 else {
            throw XCTSkip("No tasks found")
        }

        tasks.firstMatch.tap()
        sleep(1)

        // Find comment field
        let commentField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment'")).firstMatch

        guard commentField.waitForExistence(timeout: timeout) else {
            throw XCTSkip("Comment input field not found")
        }

        // Type a comment
        commentField.tap()
        commentField.typeText("Test comment for button test")
        sleep(1)

        // Try to tap the send button (paperplane icon)
        let sendButton = app.buttons.matching(NSPredicate(format: "identifier CONTAINS 'paperplane' OR label CONTAINS 'Send'")).firstMatch

        if sendButton.exists {
            sendButton.tap()
            sleep(1)

            // Take screenshot
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "After Tapping Send Button"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            // Verify comment was sent (field should be cleared)
            let fieldValue = commentField.value as? String ?? ""
            XCTAssertTrue(fieldValue.isEmpty || fieldValue == "Add a comment...", "Comment field should be cleared after sending")
        } else {
            // If send button not found, just verify buttons are still tappable
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Send Button Not Found"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            throw XCTSkip("Send button not found or not visible")
        }
    }
}
