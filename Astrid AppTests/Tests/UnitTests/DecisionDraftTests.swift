//  DecisionDraftTests.swift
//  ADEV-189 follow-up: a decision is written in task details, as a comment or in the description,
//  rather than started from the project board. The composer's draft becomes the markdown
//  (`docs/DECISIONS.md` in astrid-web) that every app draws as cards and a coloured grid.

import AstridCore
import XCTest
@testable import Astrid_App

final class DecisionDraftTests: XCTestCase {

    private func draft(_ question: String, _ options: [String]) -> DecisionDraft {
        var d = DecisionDraft()
        d.question = question
        d.options = options.map { DecisionDraft.Option(text: $0) }
        return d
    }

    func testADEV189_aQuestionAndOptionsWriteTheDecisionFormat() {
        var d = draft("Ship today?", ["Ship today", "Wait for the review"])
        d.recommended = d.options[0].id
        XCTAssertEqual(d.markdown, """
        **Decision:** Ship today?

        - **1.** Ship today (recommended)
        - **2.** Wait for the review
        """)
    }

    func testADEV189_blankOptionsAreLeftOutAndTheRestRenumbered() {
        let d = draft("Where?", ["Lisbon", "  ", "Cabin"])
        XCTAssertTrue(d.markdown.hasSuffix("- **1.** Lisbon\n- **2.** Cabin"), d.markdown)
    }

    func testADEV189_ratedCriteriaAddTheTradeOffGrid() {
        var d = draft("Where?", ["Lisbon", "Cabin"])
        d.criteria = [.init(name: "Cost"), .init(name: "Fun")]
        d.set(.init(rating: "~", text: "flights"), option: d.options[0].id, criterion: d.criteria[0].id)
        d.set(.init(rating: "++", text: "sun"), option: d.options[0].id, criterion: d.criteria[1].id)
        d.set(.init(rating: "+", text: ""), option: d.options[1].id, criterion: d.criteria[0].id)
        XCTAssertTrue(d.markdown.hasSuffix("""
        - **2.** Cabin

        | Option | Cost | Fun |
        |---|---|---|
        | 1. Lisbon | ~ flights | ++ sun |
        | 2. Cabin | + |  |
        """), d.markdown)
    }

    /// What the composer writes is what the apps draw: one set of cards, one grid.
    func testADEV189_theWrittenDecisionDrawsAsCardsAndAGrid() {
        var d = draft("Where?", ["Lisbon", "Cabin"])
        d.recommended = d.options[1].id
        d.criteria = [.init(name: "Cost")]
        d.set(.init(rating: "--", text: "dear"), option: d.options[0].id, criterion: d.criteria[0].id)
        d.set(.init(rating: "++", text: "cheap | quiet"), option: d.options[1].id, criterion: d.criteria[0].id)
        let blocks = Decisions.blocks(source: d.markdown)
        guard case .decision(let decision)? = blocks.first(where: { if case .decision = $0 { true } else { false } }),
              case .tradeOff(let grid)? = blocks.first(where: { if case .tradeOff = $0 { true } else { false } })
        else { return XCTFail("not drawn as a decision and a grid: \(blocks)") }
        XCTAssertEqual(decision.options.map(\.recommended), [false, true])
        XCTAssertEqual(grid.rows.map { $0.cells.map(\.rating) }, [[.veryPoor], [.veryGood]])
    }

    func testADEV189_criteriaWithNoRatingsAddNoGrid() {
        var d = draft("Where?", ["Lisbon", "Cabin"])
        d.criteria = [.init(name: "Cost")]
        XCTAssertFalse(d.markdown.contains("|"))
    }

    func testADEV189_whatStopsItBeingPosted() {
        XCTAssertEqual(draft(" ", ["A", "B"]).problem, .noQuestion)
        XCTAssertEqual(draft("Which?", ["A", ""]).problem, .tooFewOptions)
        var d = draft("Which?", ["A", "B"])
        XCTAssertNil(d.problem)
        d.criteria = [.init(name: "Cost")]
        d.set(.init(rating: nil, text: "cheap"), option: d.options[0].id, criterion: d.criteria[0].id)
        XCTAssertEqual(d.problem, .reasonWithoutRating, "an unrated reason would stop the table reading as a grid")
    }

    func testADEV189_aLineBreakInAnOptionStaysOnItsLine() {
        let d = draft("Which\nway?", ["Left\nturn", "Right"])
        XCTAssertTrue(d.markdown.hasPrefix("**Decision:** Which way?"), d.markdown)
        XCTAssertTrue(d.markdown.contains("- **1.** Left turn\n"), d.markdown)
    }

    func testADEV189_addedToADescriptionAfterWhatIsThere() {
        let d = draft("Which?", ["A", "B"])
        XCTAssertEqual(d.appended(to: ""), d.markdown)
        XCTAssertEqual(d.appended(to: "Notes.\n\n"), "Notes.\n\n" + d.markdown)
    }
}
