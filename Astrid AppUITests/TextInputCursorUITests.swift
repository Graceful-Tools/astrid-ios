import XCTest

/// UI tests for text input cursor alignment
/// Verifies cursor positioning in task description, task comments, and list comments
/// Takes screenshots at each step for visual verification of cursor alignment
final class TextInputCursorUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper: Navigate to first task detail

    @MainActor
    private func navigateToTaskDetail() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        let taskListLoaded = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'My Tasks' OR label CONTAINS[c] 'task'")).firstMatch.waitForExistence(timeout: 10)
        if !taskListLoaded {
            throw XCTSkip("Task list not visible")
        }

        guard let firstTask = UITestLaunch.waitForFirstVisibleRow(app) else {
            throw XCTSkip("No tasks found in list")
        }

        UITestLaunch.tapCenter(firstTask)

        let detailHeader = UITestLaunch.taskDetailHeader(app)
        guard detailHeader.waitForExistence(timeout: 5) else {
            throw XCTSkip("Task detail did not appear")
        }
    }

    // MARK: - Task Description Tests

    @MainActor
    func testDescriptionField_PlainText_CursorAlignment() throws {
        try navigateToTaskDetail()

        // Find and tap the description area to enter editing mode
        let descriptionArea = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'description' OR label CONTAINS[c] 'Add a description'")).firstMatch
        if descriptionArea.waitForExistence(timeout: 3) {
            descriptionArea.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Take screenshot before typing
        let beforeTyping = XCTAttachment(screenshot: app.screenshot())
        beforeTyping.name = "Description - Before Typing"
        beforeTyping.lifetime = .keepAlways
        add(beforeTyping)

        // Type plain text
        app.typeText("Testing cursor alignment")
        Thread.sleep(forTimeInterval: 0.3)

        let afterTyping = XCTAttachment(screenshot: app.screenshot())
        afterTyping.name = "Description - After Plain Text"
        afterTyping.lifetime = .keepAlways
        add(afterTyping)

        // Type a new line and more text
        app.typeText("\nSecond line of text")
        Thread.sleep(forTimeInterval: 0.3)

        let afterNewline = XCTAttachment(screenshot: app.screenshot())
        afterNewline.name = "Description - After Newline"
        afterNewline.lifetime = .keepAlways
        add(afterNewline)

        // Type another newline
        app.typeText("\nThird line")
        Thread.sleep(forTimeInterval: 0.3)

        let afterThirdLine = XCTAttachment(screenshot: app.screenshot())
        afterThirdLine.name = "Description - After Third Line"
        afterThirdLine.lifetime = .keepAlways
        add(afterThirdLine)
    }

    // MARK: - Task Comment Tests

    @MainActor
    func testCommentField_PlainText_CursorAlignment() throws {
        try navigateToTaskDetail()

        // Find the comment input field
        let commentField = app.textViews.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment' OR value CONTAINS[c] 'comment'")).firstMatch

        // Try tapping the comment area
        if commentField.waitForExistence(timeout: 3) {
            commentField.tap()
        } else {
            // Try finding by placeholder text
            let placeholder = app.staticTexts["Add a comment..."]
            if placeholder.waitForExistence(timeout: 3) {
                placeholder.tap()
            } else {
                throw XCTSkip("Comment field not found")
            }
        }

        Thread.sleep(forTimeInterval: 0.3)

        let beforeTyping = XCTAttachment(screenshot: app.screenshot())
        beforeTyping.name = "Comment - Before Typing"
        beforeTyping.lifetime = .keepAlways
        add(beforeTyping)

        // Type plain text
        app.typeText("Testing comment cursor")
        Thread.sleep(forTimeInterval: 0.3)

        let afterTyping = XCTAttachment(screenshot: app.screenshot())
        afterTyping.name = "Comment - After Plain Text"
        afterTyping.lifetime = .keepAlways
        add(afterTyping)
    }

    @MainActor
    func testCommentField_WithMention_CursorAlignment() throws {
        try navigateToTaskDetail()

        // Find and tap comment input
        let commentField = app.textViews.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment' OR value CONTAINS[c] 'comment'")).firstMatch

        if commentField.waitForExistence(timeout: 3) {
            commentField.tap()
        } else {
            let placeholder = app.staticTexts["Add a comment..."]
            if placeholder.waitForExistence(timeout: 3) {
                placeholder.tap()
            } else {
                throw XCTSkip("Comment field not found")
            }
        }

        Thread.sleep(forTimeInterval: 0.3)

        // Type text with an @mention trigger
        app.typeText("Hello @")
        Thread.sleep(forTimeInterval: 0.5)

        let afterAtSign = XCTAttachment(screenshot: app.screenshot())
        afterAtSign.name = "Comment - After @ Trigger"
        afterAtSign.lifetime = .keepAlways
        add(afterAtSign)

        // If autocomplete appears, check it
        Thread.sleep(forTimeInterval: 0.5)

        let withAutocomplete = XCTAttachment(screenshot: app.screenshot())
        withAutocomplete.name = "Comment - With Autocomplete"
        withAutocomplete.lifetime = .keepAlways
        add(withAutocomplete)

        // Type more text after the mention trigger
        app.typeText("test ")
        Thread.sleep(forTimeInterval: 0.3)

        let afterMentionText = XCTAttachment(screenshot: app.screenshot())
        afterMentionText.name = "Comment - After Mention Text"
        afterMentionText.lifetime = .keepAlways
        add(afterMentionText)
    }

    @MainActor
    func testCommentField_WithListReference_CursorAlignment() throws {
        try navigateToTaskDetail()

        // Find and tap comment input
        let commentField = app.textViews.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment' OR value CONTAINS[c] 'comment'")).firstMatch

        if commentField.waitForExistence(timeout: 3) {
            commentField.tap()
        } else {
            let placeholder = app.staticTexts["Add a comment..."]
            if placeholder.waitForExistence(timeout: 3) {
                placeholder.tap()
            } else {
                throw XCTSkip("Comment field not found")
            }
        }

        Thread.sleep(forTimeInterval: 0.3)

        // Type text with a #list trigger
        app.typeText("Check #")
        Thread.sleep(forTimeInterval: 0.5)

        let afterHash = XCTAttachment(screenshot: app.screenshot())
        afterHash.name = "Comment - After # Trigger"
        afterHash.lifetime = .keepAlways
        add(afterHash)

        // Type more after trigger
        app.typeText("test ")
        Thread.sleep(forTimeInterval: 0.3)

        let afterListText = XCTAttachment(screenshot: app.screenshot())
        afterListText.name = "Comment - After List Text"
        afterListText.lifetime = .keepAlways
        add(afterListText)
    }

    // MARK: - Keyboard Dismiss Tests

    @MainActor
    func testCommentField_SwipeDownDismissesKeyboard() throws {
        try navigateToTaskDetail()

        // Find and tap comment input
        let commentField = app.textViews.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'comment' OR value CONTAINS[c] 'comment'")).firstMatch

        if commentField.waitForExistence(timeout: 3) {
            commentField.tap()
        } else {
            let placeholder = app.staticTexts["Add a comment..."]
            if placeholder.waitForExistence(timeout: 3) {
                placeholder.tap()
            } else {
                throw XCTSkip("Comment field not found")
            }
        }

        // Verify keyboard appeared
        Thread.sleep(forTimeInterval: 0.5)
        let keyboardUp = XCTAttachment(screenshot: app.screenshot())
        keyboardUp.name = "Keyboard - Visible"
        keyboardUp.lifetime = .keepAlways
        add(keyboardUp)

        // Swipe down on the scroll view to dismiss keyboard
        let scrollArea = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let scrollDown = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        scrollArea.press(forDuration: 0.05, thenDragTo: scrollDown)

        Thread.sleep(forTimeInterval: 0.5)

        let keyboardDown = XCTAttachment(screenshot: app.screenshot())
        keyboardDown.name = "Keyboard - After Swipe Down"
        keyboardDown.lifetime = .keepAlways
        add(keyboardDown)
    }
}
