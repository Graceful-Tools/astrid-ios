import XCTest

/// A decision is written from a task's details and lands in its thread as cards (ADEV-189). The
/// project board's Decisions screen it replaces asked for more and showed less: the cards and
/// the coloured grid were already how a decision reads, so writing one belongs where it is read.
final class DecisionComposerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestLaunch.makeApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func optionOneCount() -> Int {
        app.descendants(matching: .any).matching(identifier: "decision.option.1").count
    }

    @MainActor
    func testADEV189_aDecisionWrittenInTaskDetailsPostsAsCards() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        _ = try UITestLaunch.openFirstTaskComment(app)

        element("comment.attachMenu").tap()
        let ask = element("taskDetail.askForDecision")
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "the comment bar's menu offers a decision")
        ask.tap()

        let question = "Which way \(UUID().uuidString.prefix(6))?"
        let questionField = element("decisionComposer.question")
        XCTAssertTrue(questionField.waitForExistence(timeout: 5), "the composer opened")
        questionField.tap()
        questionField.typeText(question)
        let options = app.descendants(matching: .any).matching(identifier: "decisionComposer.option")
        for (i, text) in ["Left", "Right"].enumerated() {
            options.element(boundBy: i).tap()
            options.element(boundBy: i).typeText(text)
        }
        attach("Decision composer")

        let done = element("decisionComposer.done")
        XCTAssertTrue(done.isEnabled, "a question and two options are enough to post")
        done.tap()

        let asked = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", question)).firstMatch
        XCTAssertTrue(asked.waitForExistence(timeout: 15), "the decision is in the thread")
        XCTAssertTrue(element("decision.option.2").waitForExistence(timeout: 5), "its options draw as cards")
        attach("Decision in the thread")
    }

    /// With a rated criterion the decision posts as one grid whose rows are the options (ADEV-229):
    /// no cards above it, and the composer's preview draws it the same way.
    @MainActor
    func testADEV229_aDecisionWithTradeOffsPostsAsOneGrid() throws {
        app.launch()
        try UITestLaunch.skipUnlessSignedIn(app)
        _ = try UITestLaunch.openFirstTaskComment(app)
        // Counted before the composer opens: its preview draws the grid too, and an earlier test's
        // decision may already be on this task.
        let before = optionOneCount()
        let cardsBefore = app.descendants(matching: .any).matching(NSPredicate(format: "value == 'card'")).count
        element("comment.attachMenu").tap()
        element("taskDetail.askForDecision").tap()

        let question = "Which grid \(UUID().uuidString.prefix(6))?"
        let questionField = element("decisionComposer.question")
        XCTAssertTrue(questionField.waitForExistence(timeout: 5))
        questionField.tap()
        questionField.typeText(question)
        let options = app.descendants(matching: .any).matching(identifier: "decisionComposer.option")
        for (i, text) in ["Left", "Right"].enumerated() {
            options.element(boundBy: i).tap()
            options.element(boundBy: i).typeText(text)
        }
        element("decisionComposer.addCriterion").tap()
        let criterion = element("decisionComposer.criterion")
        criterion.tap()
        criterion.typeText("Cost")
        app.swipeUp()
        // One set of lights per option; the first may be scrolled away, so take one on screen.
        let lights = app.buttons.matching(identifier: "decisionComposer.light.4")
        XCTAssertTrue(lights.firstMatch.waitForExistence(timeout: 5), "each option is rated with traffic lights")
        let picked = app.buttons.matching(
            NSPredicate(format: "identifier == 'decisionComposer.light.4' AND selected == true")).firstMatch
        for _ in 0..<2 where !picked.exists {
            // Below the sheet's toolbar: a light scrolled under it reports hittable, but the
            // toolbar takes the tap.
            let onScreen = try XCTUnwrap(lights.allElementsBoundByIndex.first {
                $0.isHittable && $0.frame.minY > app.navigationBars.firstMatch.frame.maxY
            }, "a traffic light on screen")
            onScreen.tap()
            _ = picked.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(picked.exists, "the tapped light is picked")
        attach("Decision with trade-offs")
        element("decisionComposer.done").tap()

        let asked = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", question)).firstMatch
        XCTAssertTrue(asked.waitForExistence(timeout: 15), "the decision is in the thread")
        XCTAssertTrue(element("decision.choosableGrid").waitForExistence(timeout: 5),
                      "a decision with trade-offs draws as one grid")
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "value == 'card'")).count,
                       cardsBefore, "and adds no cards above it")
        XCTAssertEqual(optionOneCount() - before, 1, "the option is drawn once, as a row")
        attach("Decision grid in the thread")

        // ADEV-232: the asker can choose on their own trade-off — tap a row, confirm, and the
        // choice is posted as the reply. The newest grid is the last one on the task.
        let rowTwo = app.descendants(matching: .any).matching(identifier: "decision.option.2")
            .allElementsBoundByIndex.last { $0.label.contains("Right") }
        try XCTUnwrap(rowTwo, "the posted grid's second row").tap()
        let choose = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "2 — Right")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "the choice is confirmed before it is posted")
        choose.tap()
        let reply = app.staticTexts.matching(NSPredicate(format: "label == %@", "2 — Right")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 15), "your own choice is posted as the reply")
        attach("Own decision chosen")

        // ADEV-233: the iPhone stays upright, but a full-screen grid turns sideways on request
        // and comes back upright when closed.
        let window = app.windows.firstMatch
        func isLandscape() -> Bool { window.frame.width > window.frame.height }
        XCTAssertFalse(isLandscape(), "the app is upright")
        let fullScreen = app.buttons.matching(identifier: "tradeOffGrid.fullScreen")
        XCTAssertTrue(fullScreen.firstMatch.waitForExistence(timeout: 5), "every grid has Full screen")
        for _ in 0..<3 where !(fullScreen.allElementsBoundByIndex.last?.isHittable ?? false) {
            app.swipeDown()  // the reply may have scrolled the grid's top away
        }
        try XCTUnwrap(fullScreen.allElementsBoundByIndex.last, "the posted grid's Full screen").tap()
        let rotate = element("tradeOffGrid.rotate")
        XCTAssertTrue(rotate.waitForExistence(timeout: 5), "the full-screen grid offers to turn")
        rotate.tap()
        XCTAssertTrue(waitUntil(timeout: 5, isLandscape), "the grid turns sideways")
        // Held sideways, as a person turns the phone to follow it (device left = interface right).
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))  // past the turn's animation
        XCTAssertTrue(element("tradeOffGrid.rotate").isHittable, "and offers to turn back")
        attach("Grid in landscape")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !isLandscape() }, "closing it turns the app upright again")
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }
}
