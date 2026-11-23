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
}
