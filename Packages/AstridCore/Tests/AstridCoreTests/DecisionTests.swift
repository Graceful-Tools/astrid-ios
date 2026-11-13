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
        let blocks = Decisions.blocks(source: """
            **Decision:** Which way?
            - **A.** Go with the format (recommended)
            - **B.** iOS first
            - **C.** Something else
            """)
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
        let option = DecisionOption(letter: "B", number: 2, label: [], text: "iOS first", recommended: false)
        XCTAssertEqual(option.reply, "2 — iOS first")
    }

    /// AITD-585: options are a numbered list — the cards and the reply carry 1, 2, 3, whatever
    /// marker the asker wrote, and an option may be written `**1.**` as well as `**A.**`.
    func testAITD585_optionsAreNumberedInOrderWhicheverMarkerTheyWereWrittenWith() {
        for source in [
            "**Decision:** Which way?\n- **A.** Go\n- **B.** Wait\n- **C.** Neither",
            "**Decision:** Which way?\n1. **1.** Go\n2. **2.** Wait\n3. **3.** Neither",
            "**Decision:** Which way?\n- **1)** Go\n- **2)** Wait\n- **3)** Neither",
        ] {
            guard case .decision(let decision)? = Decisions.blocks(source: source).first else {
                XCTFail("a decision: \(source)"); continue
            }
            XCTAssertEqual(decision.options.map(\.number), [1, 2, 3], source)
            XCTAssertEqual(decision.options.map(\.reply), ["1 — Go", "2 — Wait", "3 — Neither"], source)
        }
    }

    func testAITD579_theWordsAroundADecisionStayMarkdown() {
        let blocks = Decisions.blocks(source: """
            ## One question

            **Decision:** Which way?
            - **A.** Yes
            - **B.** No

            AGENT-HANDBACK: claude
            """)
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
            let blocks = Decisions.blocks(source: source)
            XCTAssertFalse(blocks.contains { if case .decision = $0 { return true }; return false },
                           source)
        }
    }

    private var lettered: [DecisionOption] {
        ["A", "B", "C"].enumerated().map {
            DecisionOption(letter: $1, number: $0 + 1, label: [], text: "", recommended: false)
        }
    }

    func testAITD579_aReplyChoosesTheOptionItStartsWith() {
        XCTAssertEqual(Decisions.chosenNumber(in: "A", options: lettered), 1)
        XCTAssertEqual(Decisions.chosenNumber(in: "b", options: lettered), 2)
        XCTAssertEqual(Decisions.chosenNumber(in: "C — Something else", options: lettered), 3)
        XCTAssertEqual(Decisions.chosenNumber(in: "  A. go", options: lettered), 1)
        XCTAssertNil(Decisions.chosenNumber(in: "Also, what about D?", options: lettered))
        XCTAssertNil(Decisions.chosenNumber(in: "D", options: lettered))
        XCTAssertNil(Decisions.chosenNumber(in: "Let me think", options: lettered))
    }

    /// AITD-585: a tap now replies "2 — Wait"; a reply in the old letter form still chooses.
    func testAITD585_aReplyStartingWithTheOptionsNumberChoosesIt() {
        XCTAssertEqual(Decisions.chosenNumber(in: "2 — Wait", options: lettered), 2)
        XCTAssertEqual(Decisions.chosenNumber(in: "3", options: lettered), 3)
        XCTAssertEqual(Decisions.chosenNumber(in: "1. go", options: lettered), 1)
        XCTAssertNil(Decisions.chosenNumber(in: "4", options: lettered))
        XCTAssertNil(Decisions.chosenNumber(in: "0", options: lettered))
        XCTAssertNil(Decisions.chosenNumber(in: "2nd thoughts", options: lettered))
        XCTAssertNil(Decisions.chosenNumber(in: "10 minutes", options: lettered))
    }

    // MARK: - AITD-578 trade-off grid

    func testAITD578_aTableOfRatedCellsIsATradeOffGrid() {
        let blocks = Decisions.blocks(source: """
            | Option | Cost | Speed | Risk |
            |---|---|---|---|
            | A. Rust core | ++ one codebase | + fast | ~ new |
            | B. Swift | -- two codebases | - slower | |
            """)
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
        let blocks = Decisions.blocks(source: """
            | Option | Fit |
            |---|---|
            | A | 🟢 good |
            | B | 🟡 |
            | C | 🔴 poor |
            """)
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
            let blocks = Decisions.blocks(source: source)
            guard case .markdown(.table)? = blocks.first else { return XCTFail("\(source): \(blocks)") }
        }
    }

    /// AITD-585: grid rows are numbered like the options, so the asker's own "A." comes off the
    /// row's name, and the criteria columns are lettered A, B, C.
    func testAITD585_gridRowsDropTheirMarkerAndColumnsAreLettered() {
        let blocks = Decisions.blocks(source: """
            | Option | Cost | Travel |
            |---|---|---|
            | A. Lisbon | ~ flights | - long |
            | 2) Cabin | + rental | + 3h |
            | Pizza | ++ cheap | ++ none |
            | B | + x | + y |
            """)
        guard case .tradeOff(let grid)? = blocks.first else { return XCTFail("a grid, got \(blocks)") }
        XCTAssertEqual(grid.rows.map { plain($0.name) }, ["Lisbon", "Cabin", "Pizza", ""])
        XCTAssertEqual((0..<3).map(Decisions.columnLetter), ["A", "B", "C"])
        XCTAssertEqual(Decisions.columnLetter(25), "Z")
        XCTAssertEqual(Decisions.columnLetter(26), "AA")
    }

    // MARK: - AITD-641 the core decides (astrid_rules::decisions)

    /// Core fixture "option label forms": markdown makes `-`, `*` and `1.` three separate lists,
    /// so the Swift recogniser saw a one-option list and drew text. Web and the core draw cards.
    func testAITD641_optionsWrittenWithMixedListMarkersAreOneDecision() {
        let blocks = Decisions.blocks(source: "**Decision:** Pick one\n\n- **A.** dot\n* **B)** paren\n1. **C:** colon\n2. **D** bare")
        guard blocks.count == 1, case .decision(let decision) = blocks[0] else {
            return XCTFail("one decision, got \(blocks)")
        }
        XCTAssertEqual(plain(decision.question), "Pick one")
        XCTAssertEqual(decision.options.map(\.letter), ["A", "B", "C", "D"])
        XCTAssertEqual(decision.options.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(decision.options.map(\.text), ["dot", "paren", "colon", "bare"])
    }

    /// Core fixture near-misses: an example of the format, in code, is not a question.
    func testAITD641_aDecisionWrittenAsCodeStaysCode() {
        for source in [
            "Write it like this:\n\n```markdown\n**Decision:** Pick\n\n- **A.** one\n- **B.** two\n```",
            "**Decision:** Pick\n\n- **100.** a\n- **101.** b",
            "**Decision:** Pick\n\n- **A.** one\n- two",
        ] {
            let blocks = Decisions.blocks(source: source)
            XCTAssertFalse(blocks.contains { if case .decision = $0 { return true }; return false }, source)
        }
    }

    /// The canonical example (docs/DECISIONS.md): the grid after the options is still a grid, and
    /// the option keeps its words as marks while the reply carries them plain.
    func testAITD641_theCanonicalExampleIsCardsThenAGrid() {
        let blocks = Decisions.blocks(source: """
            **Decision:** Where should we hold the team offsite?

            - **1.** **Lisbon** (recommended)
            - **2.** Mountain cabin

            | Option | Cost | Fun |
            |---|---|---|
            | 1. Lisbon | ~ flights for everyone | ++ food, sun, city |
            | 2. Cabin | + one rental | + hiking |
            """)
        guard blocks.count == 2, case .decision(let decision) = blocks[0], case .tradeOff(let grid) = blocks[1] else {
            return XCTFail("a decision then a grid, got \(blocks)")
        }
        XCTAssertEqual(decision.options.map(\.recommended), [true, false])
        XCTAssertEqual(decision.options[0].reply, "1 — Lisbon")
        guard case .text(let run)? = decision.options[0].label.first else { return XCTFail("a label") }
        XCTAssertTrue(run.bold)
        XCTAssertEqual(grid.rows.map { plain($0.name) }, ["Lisbon", "Cabin"])
        XCTAssertEqual(grid.rows[0].cells.map(\.rating), [.mixed, .veryGood])
        XCTAssertEqual(grid.rows[0].cells.map { plain($0.reason) }, ["flights for everyone", "food, sun, city"])
    }

    /// A code span that looks like a rating is code, as on web, which reads the cell's source.
    func testAITD641_aRatingInACodeSpanIsNotARating() {
        let blocks = Decisions.blocks(source: "| a | b |\n|---|---|\n| x | `++` y |")
        guard case .markdown(.table)? = blocks.first else { return XCTFail("a table, got \(blocks)") }
    }

    /// Every reply in the core fixture, against its numbered and lettered option sets. The French
    /// pair already did not answer on Apple; this pins that it matches web and the core.
    func testAITD641_repliesChooseAsTheCoreFixtureSays() {
        let numbered = (1...3).map {
            DecisionOption(letter: "\($0)", number: $0, label: [], text: "", recommended: false)
        }
        let cases: [(String, Int?, Int?)] = [
            ("1 — Lisbon", 1, 1), ("2", 2, 2), ("3.", 3, 3), ("1) sure", 1, 1), ("4", nil, nil),
            ("0", nil, nil), ("2nd thoughts", nil, nil), ("10 minutes", nil, nil),
            ("A — Lisbon", nil, 1), ("b", nil, 2), ("C.", nil, 3), ("A) sure", nil, 1),
            ("Lisbon please", nil, nil), ("AB", nil, nil), ("  a, then b", nil, 1), ("", nil, nil),
            ("Béatrice doit vérifier", nil, nil), ("2ème avis nécessaire", nil, nil),
        ]
        for (reply, byNumber, byLetter) in cases {
            XCTAssertEqual(Decisions.chosenNumber(in: reply, options: numbered), byNumber, reply)
            XCTAssertEqual(Decisions.chosenNumber(in: reply, options: lettered), byLetter, reply)
        }
    }
}
