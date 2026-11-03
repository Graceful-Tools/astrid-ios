import AstridCore
import XCTest

/// AITD-579 (an agent's question as a, b, c cards) and AITD-578 (a trade-off grid of red, yellow
/// and green cells): both are ordinary markdown that the Apple apps recognise and draw richly.
final class DecisionTests: XCTestCase {

    private func plain(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let run): return run.text
            case .reference(_, let label, _): return label
            case .lineBreak: return "\n"
            }
        }.joined()
    }

    // MARK: - AITD-579 decisions

    func testAITD579_aDecisionLineAndLetteredOptionsAreADecision() {
        let blocks = Decisions.blocks(CoreRules.markdown("""
            **Decision:** Which way?
            - **A.** Go with the format (recommended)
            - **B.** iOS first
            - **C.** Something else
            """))
        guard blocks.count == 1, case .decision(let decision) = blocks[0] else {
            return XCTFail("one decision, got \(blocks)")
        }
        XCTAssertEqual(plain(decision.question), "Which way?")
        XCTAssertEqual(decision.options.map(\.letter), ["A", "B", "C"])
        XCTAssertEqual(decision.options.map(\.text), ["Go with the format", "iOS first", "Something else"])
        XCTAssertEqual(decision.options.map(\.recommended), [true, false, false])
        XCTAssertEqual(plain(decision.options[0].label), "Go with the format")
    }

    func testAITD579_tappingAnOptionRepliesWithItsLetterAndWords() {
        let option = DecisionOption(letter: "B", label: [], text: "iOS first", recommended: false)
        XCTAssertEqual(option.reply, "B — iOS first")
    }

    func testAITD579_theWordsAroundADecisionStayMarkdown() {
        let blocks = Decisions.blocks(CoreRules.markdown("""
            ## One question

            **Decision:** Which way?
            - **A.** Yes
            - **B.** No

            AGENT-HANDBACK: claude
            """))
        XCTAssertEqual(blocks.count, 3)
        guard case .markdown(.heading) = blocks[0] else { return XCTFail("heading first") }
        guard case .decision = blocks[1] else { return XCTFail("then the decision") }
        guard case .markdown(.paragraph) = blocks[2] else { return XCTFail("then the handback line") }
    }

    func testAITD579_anOrdinaryListAfterABoldLineIsNotADecision() {
        for source in [
            "**Decision:** Which way?\n- yes\n- no",            // options without letters
            "**Plan:** Which way?\n- **A.** yes\n- **B.** no",  // not a decision line
            "**Decision:** Which way?\n- **A.** only one",      // nothing to choose between
            "**Decision:** Which way?",                          // no options at all
        ] {
            let blocks = Decisions.blocks(CoreRules.markdown(source))
            XCTAssertFalse(blocks.contains { if case .decision = $0 { return true }; return false },
                           source)
        }
    }

    func testAITD579_aReplyChoosesTheOptionItStartsWith() {
        let letters = ["A", "B", "C"]
        XCTAssertEqual(Decisions.chosenLetter(in: "A", letters: letters), "A")
        XCTAssertEqual(Decisions.chosenLetter(in: "b", letters: letters), "B")
        XCTAssertEqual(Decisions.chosenLetter(in: "C — Something else", letters: letters), "C")
        XCTAssertEqual(Decisions.chosenLetter(in: "  A. go", letters: letters), "A")
        XCTAssertNil(Decisions.chosenLetter(in: "Also, what about D?", letters: letters))
        XCTAssertNil(Decisions.chosenLetter(in: "D", letters: letters))
        XCTAssertNil(Decisions.chosenLetter(in: "Let me think", letters: letters))
    }

    // MARK: - AITD-578 trade-off grid

    func testAITD578_aTableOfRatedCellsIsATradeOffGrid() {
        let blocks = Decisions.blocks(CoreRules.markdown("""
            | Option | Cost | Speed | Risk |
            |---|---|---|---|
            | A. Rust core | ++ one codebase | + fast | ~ new |
            | B. Swift | -- two codebases | - slower | |
            """))
        guard blocks.count == 1, case .tradeOff(let grid) = blocks[0] else {
            return XCTFail("one grid, got \(blocks)")
        }
        XCTAssertEqual(grid.header.map(plain), ["Option", "Cost", "Speed", "Risk"])
        XCTAssertEqual(grid.rows.map { plain($0.option) }, ["A. Rust core", "B. Swift"])
        XCTAssertEqual(grid.rows[0].cells.map(\.rating), [.veryGood, .good, .mixed])
        XCTAssertEqual(grid.rows[1].cells.map(\.rating), [.veryPoor, .poor, nil])
        XCTAssertEqual(grid.rows[0].cells.map { plain($0.reason) }, ["one codebase", "fast", "new"])
    }

    func testAITD578_trafficLightEmojiRateACellToo() {
        let blocks = Decisions.blocks(CoreRules.markdown("""
            | Option | Fit |
            |---|---|
            | A | 🟢 good |
            | B | 🟡 |
            | C | 🔴 poor |
            """))
        guard case .tradeOff(let grid)? = blocks.first else { return XCTFail("a grid, got \(blocks)") }
        XCTAssertEqual(grid.rows.map { $0.cells.first?.rating }, [.good, .mixed, .poor])
        XCTAssertEqual(grid.rows.map { plain($0.cells[0].reason) }, ["good", "", "poor"])
    }

    func testAITD578_anOrdinaryTableStaysATable() {
        for source in [
            "| a | b |\n|---|---|\n| x | y |",              // no ratings
            "| a | b |\n|---|---|\n| x | + y |\n| z | w |",  // one unrated cell with words
            "| a | b |\n|---|---|\n| x | -5 |",             // a number, not a rating
            "| a | b |\n|---|---|\n| x | - |\n| y | - |",   // dashes as placeholders
        ] {
            let blocks = Decisions.blocks(CoreRules.markdown(source))
            guard case .markdown(.table)? = blocks.first else { return XCTFail("\(source): \(blocks)") }
        }
    }
}
