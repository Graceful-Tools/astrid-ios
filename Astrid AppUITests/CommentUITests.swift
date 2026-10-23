import XCTest

/// The comment box on a task detail: that the keyboard comes up, goes away, and does not take
/// the typed text or the Send button with it.
///
/// All four of these skipped with "Comment input field not found" for as long as the suite has
/// been able to sign in (task 91a7e180). They asked for `app.textFields` with a
/// `placeholderValue` containing "comment", which could never match: the control is a
/// `TextEditor`, which XCUITest exposes as a text VIEW, and its placeholder is a separate `Text`
/// drawn behind it, so `placeholderValue` is empty. The same wrong shape once hid quick-add.
///
/// They also each rebuilt "open a task" out of `staticTexts CONTAINS 'Task'`, `tap()` and
/// `sleep(1)`, and never checked that the detail had opened — so a failure one step earlier
/// arrived wearing the comment box's name. That path is now `UITestLaunch.openFirstTaskComment`,
/// which says which step actually failed.
final class CommentUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Tap somewhere that is not the comment box, ABOVE the keyboard.
    ///
    /// This used to aim at the "Comments (0)" header, which sits near the bottom of the detail
    /// — under the keyboard once it is up. So the tap landed on a KEY: the keyboard stayed, and
    /// the draft came back as "Test comment textA" with a stray letter appended. Both failures
    /// were the gesture, not the app.
    ///
    /// A tenth of the way down is the detail's own header, which is on screen whatever the
    /// task looks like and focuses nothing.
    @MainActor
    private func tapOutsideTheCommentBox() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Keyboard

    @MainActor
    func testKeyboardAppearsWhenTappingCommentField() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let commentField = try UITestLaunch.openFirstTaskComment(app)
        commentField.tap()

        let appeared = app.keyboards.element.waitForExistence(timeout: 10)
        attach("Keyboard After Tapping Comment Field")
        XCTAssertTrue(appeared, "Keyboard should appear when tapping the comment box")
    }

    /// Dragging DOWN on the comment bar puts the keyboard away.
    ///
    /// This test used to say "when tapping outside", and the app has never done that. It has
    /// three ways to dismiss the comment keyboard — a downward drag on the bar, an interactive
    /// scroll of the detail, and another editor taking the session — and a tap on the body is
    /// not one of them. Because the test had been skipping since before it could sign in,
    /// nobody had ever seen it disagree with the app (task 91a7e180).
    ///
    /// So it now asserts the gesture that exists. Whether a tap outside SHOULD also dismiss is
    /// a product question, raised on the task rather than answered here.
    @MainActor
    func testKeyboardDismissesWhenDraggingDownOnTheCommentBar() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let commentField = try UITestLaunch.openFirstTaskComment(app)
        commentField.tap()

        let keyboard = app.keyboards.element
        guard keyboard.waitForExistence(timeout: 10) else {
            throw UITestFailure("Keyboard did not appear")
        }

        // A real downward drag from the comment bar — the gesture the bar listens for
        // (`DragGesture` where translation.height > 10).
        commentField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.2)

        // Poll rather than sleep: the dismissal is animated, and a fixed wait is either a
        // flake on a loaded machine or wasted seconds on a fast one.
        let deadline = Date().addingTimeInterval(5)
        while keyboard.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        attach("After Dragging Down On The Comment Bar")
        XCTAssertFalse(keyboard.exists,
                       "Dragging down on the comment bar should put the keyboard away")
    }

    // MARK: - What must survive the dismissal

    @MainActor
    func testCommentTextPreservedAfterDismissingKeyboard() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let commentField = try UITestLaunch.openFirstTaskComment(app)
        let testComment = "Test comment text"
        commentField.tap()
        guard app.keyboards.element.waitForExistence(timeout: 10) else {
            throw UITestFailure("Keyboard did not appear, so nothing could be typed")
        }
        commentField.typeText(testComment)

        tapOutsideTheCommentBox()
        // The draft is read once the tap has landed — the keyboard leaving is that signal, and
        // if it never leaves the draft is still checked, which is the point of the test.
        UITestLaunch.waitForDisappearance(app.keyboards.element, timeout: 3)

        attach("Comment Text After Dismissing Keyboard")
        XCTAssertEqual(commentField.value as? String, testComment,
                       "Losing the draft to a keyboard dismissal is the bug this guards")
    }

    @MainActor
    func testKeyboardDismissalDoesNotInterfereWithButtons() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)

        let commentField = try UITestLaunch.openFirstTaskComment(app)
        commentField.tap()
        guard app.keyboards.element.waitForExistence(timeout: 10) else {
            throw UITestFailure("Keyboard did not appear, so nothing could be typed")
        }
        let sent = "UI test comment \(UUID().uuidString.prefix(8))"
        commentField.typeText(sent)

        let sendButton = app.buttons["comment.send"].firstMatch
        guard sendButton.waitForExistence(timeout: 5) else {
            attach("Send Button Not Found")
            throw UITestFailure("Send button not found")
        }

        UITestLaunch.tapCenter(sendButton)

        // An emptied box is also what a send that was DROPPED looks like, so the comment has
        // to be in the thread too (AITD-525) — and its arriving is what to wait on.
        let inThread = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", sent)).firstMatch
        XCTAssertTrue(inThread.waitForExistence(timeout: 10),
                      "The sent comment \"\(sent)\" should appear in the thread")
        attach("After Tapping Send Button")

        // The box no longer holds what was sent. Not "is empty": a TextEditor reports its
        // placeholder as its value on some OS versions, and that placeholder is localized.
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (value CONTAINS %@)", sent),
                                                object: commentField)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: 5), .completed,
                       "Sending must clear the box — got \(commentField.value as? String ?? "")")
    }
}
