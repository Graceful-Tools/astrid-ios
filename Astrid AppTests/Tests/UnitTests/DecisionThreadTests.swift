//  DecisionThreadTests.swift
//  AITD-579: an agent's question shows its options as a, b, c cards you tap to answer.
//
//  The cards take a tap only while the question is open, and show which option a reply chose.
//  A question is answered by the first later comment from someone other than whoever asked it:
//  a system line ("moved to Waiting") or the asker's own follow-up does not answer it.

import AstridCore
import XCTest
@testable import Astrid_App

final class DecisionThreadTests: XCTestCase {

    private let agent = "ai-agent-claude"
    private let jon = "jon"
    private let question = """
        **Decision:** Which way?
        - **A.** Go (recommended)
        - **B.** Wait
        """

    private func comment(_ id: String, _ content: String, by author: String?, at minute: Int) -> Comment {
        TestHelpers.createTestComment(id: id, content: content, authorId: author,
                                      createdAt: Date(timeIntervalSince1970: TimeInterval(minute * 60)))
    }

    private var decision: Decision {
        for block in Decisions.blocks(CoreRules.markdown(question)) {
            if case .decision(let decision) = block { return decision }
        }
        XCTFail("the question is a decision")
        return Decision(question: [], options: [])
    }

    func testAITD579_anUnansweredQuestionTakesATap() {
        let asked = comment("q", question, by: agent, at: 1)
        let thread = [asked, comment("s", "Jon moved this to Waiting", by: nil, at: 2),
                      comment("f", "Also, no rush", by: agent, at: 3)]
        let response = DecisionResponse(answer: DecisionThread.answer(to: asked, in: thread), choose: { _ in })
        XCTAssertEqual(response.state(for: decision), .open)
    }

    func testAITD579_aReplyStartingWithALetterShowsThatCardChosen() {
        let asked = comment("q", question, by: agent, at: 1)
        let thread = [asked, comment("r", "b", by: jon, at: 2), comment("x", "A", by: jon, at: 3)]
        let response = DecisionResponse(answer: DecisionThread.answer(to: asked, in: thread), choose: { _ in })
        XCTAssertEqual(response.state(for: decision), .chosen("B"))
    }

    func testAITD579_aReplyInWordsClosesTheCardsWithoutChoosingOne() {
        let asked = comment("q", question, by: agent, at: 1)
        let thread = [asked, comment("r", "Let's talk first", by: jon, at: 2)]
        let response = DecisionResponse(answer: DecisionThread.answer(to: asked, in: thread), choose: { _ in })
        XCTAssertEqual(response.state(for: decision), .answeredInWords)
    }

    func testAITD579_anEarlierCommentNeverAnswersALaterQuestion() {
        let asked = comment("q", question, by: agent, at: 5)
        let thread = [comment("r", "A", by: jon, at: 1), asked]
        XCTAssertNil(DecisionThread.answer(to: asked, in: thread))
    }

    func testAITD579_aDescriptionOrYourOwnQuestionOnlyShowsTheCards() {
        XCTAssertEqual(DecisionResponse.state(nil, for: decision), .readOnly)
    }

    /// AITD-584: no "Answer with this option?" sheet on iPhone — a tap sends, as a click does on the Mac.
    func testAITD584_tappingAnOpenOptionSendsItAtOnce() {
        var sent: [String] = []
        let response = DecisionResponse(answer: nil, choose: { sent.append($0.letter) })
        response.tap(decision.options[1], in: decision)
        XCTAssertEqual(sent, ["B"])
    }

    func testAITD584_tappingAnAnsweredQuestionSendsNothing() {
        var sent: [String] = []
        let asked = comment("q", question, by: agent, at: 1)
        let thread = [asked, comment("r", "A", by: jon, at: 2)]
        let response = DecisionResponse(answer: DecisionThread.answer(to: asked, in: thread),
                                        choose: { sent.append($0.letter) })
        response.tap(decision.options[1], in: decision)
        XCTAssertEqual(sent, [])
    }
}
