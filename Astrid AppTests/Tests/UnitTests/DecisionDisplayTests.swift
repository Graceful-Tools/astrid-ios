//  DecisionDisplayTests.swift
//  ADEV-229: a decision with a trade-off grid draws as the grid alone, each row the option to
//  choose; the cards are only for a decision without one. The markdown is unchanged, so what an
//  agent writes (cards list + grid) and what the composer writes both draw this way.

import AstridCore
import XCTest
@testable import Astrid_App

final class DecisionDisplayTests: XCTestCase {

    private let withGrid = """
    **Decision:** Where should we hold the team offsite?

    - **1.** Lisbon (recommended)
    - **2.** Mountain cabin

    | Option | Cost | Fun |
    |---|---|---|
    | 1. Lisbon | ~ flights | ++ sun |
    | 2. Cabin | + one rental | + hiking |

    - **Cost:** what the company pays.
    """

    private func kinds(_ shown: [DecisionDisplay]) -> [String] {
        shown.map {
            switch $0 {
            case .block(.markdown): "markdown"
            case .block(.decision): "cards"
            case .block(.tradeOff): "grid"
            case .choosableGrid: "choosable"
            }
        }
    }

    func testADEV229_aDecisionWithAGridDrawsAsTheGridAlone() {
        let shown = DecisionDisplay.arrange(Decisions.blocks(source: withGrid))
        XCTAssertEqual(kinds(shown), ["choosable", "markdown"], "no cards, the grid once, the criteria key kept")
        guard case .choosableGrid(let decision, let grid)? = shown.first else { return XCTFail() }
        XCTAssertEqual(decision.options.count, grid.rows.count)
        XCTAssertEqual(decision.options.first?.recommended, true)
    }

    func testADEV229_aDecisionWithoutAGridKeepsItsCards() {
        let shown = DecisionDisplay.arrange(Decisions.blocks(source: "**Decision:** Which?\n\n- **1.** A\n- **2.** B"))
        XCTAssertEqual(kinds(shown), ["cards"])
    }

    /// Rows and options are matched by position, so a grid with a different number of rows is not
    /// the same choice: both are drawn, as before.
    func testADEV229_aGridThatDoesNotMatchTheOptionsLeavesBoth() {
        let source = withGrid.replacingOccurrences(of: "- **2.** Mountain cabin", with: "- **2.** Cabin\n- **3.** Pizza")
        XCTAssertEqual(kinds(DecisionDisplay.arrange(Decisions.blocks(source: source))), ["cards", "grid", "markdown"])
    }

    func testADEV229_aGridWithNoDecisionIsJustAGrid() {
        let grid = "| Option | Cost |\n|---|---|\n| 1. A | ++ cheap |\n| 2. B | - dear |"
        XCTAssertEqual(kinds(DecisionDisplay.arrange(Decisions.blocks(source: grid))), ["grid"])
    }

    /// What the composer writes is a decision with a grid, so it posts as one grid to tap.
    func testADEV229_theComposersDecisionPostsAsAChoosableGrid() {
        var d = DecisionDraft()
        d.question = "Which?"
        d.options = [.init(text: "A"), .init(text: "B")]
        d.criteria = [.init(name: "Cost")]
        d.set(.init(rating: "+", text: ""), option: d.options[0].id, criterion: d.criteria[0].id)
        XCTAssertEqual(kinds(DecisionDisplay.arrange(Decisions.blocks(source: d.markdown))), ["choosable"])
    }
}

/// Once a row is chosen the others dim; while open, or with nothing to answer in, none do.
final class DecisionGridChoiceTests: XCTestCase {
    func testADEV229_onlyTheRowsNotChosenDim() {
        XCTAssertEqual((0..<3).map { TradeOffGridView.dimmed(row: $0, in: .chosen(2)) }, [true, false, true])
        XCTAssertFalse(TradeOffGridView.dimmed(row: 0, in: .open))
        XCTAssertFalse(TradeOffGridView.dimmed(row: 0, in: .readOnly))
        XCTAssertFalse(TradeOffGridView.dimmed(row: 0, in: nil))
        XCTAssertTrue(TradeOffGridView.dimmed(row: 0, in: .answeredInWords))
    }
}
