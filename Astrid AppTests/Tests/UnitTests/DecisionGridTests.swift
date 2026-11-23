//  DecisionGridTests.swift
//  ADEV-189 (web ADEV-180): a decision's trade-off grid is read and written back exactly as the
//  web does it. Every case comes from `Tests/Fixtures/decision-grid.json`, a verbatim copy of
//  astrid-web `contracts/fixtures/decision-grid.json` (generated from `lib/decision-grid.ts`).
//  When web regenerates it, copy it again; a failure here means iOS would edit a grid differently.

import AstridCore
import XCTest

final class DecisionGridTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Cell: Decodable { let rating: String?; let text: String }
        struct Option: Decodable { let name: String; let cells: [Cell] }
        struct Grid: Decodable { let optionLabel: String; let criteria: [String]; let options: [Option] }
        struct Serialise: Decodable {
            let name: String
            let markdown: String
            let grid: Grid?
            let serialized: String?
        }
        struct Edit: Decodable { let name: String; let grid: Grid; let markdown: String }
        let serialise: [Serialise]
        let edit: Edit
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "decision-grid", withExtension: "json"),
                                "decision-grid.json is missing from the test bundle")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func grid(_ g: Fixture.Grid) -> DecisionGrid {
        DecisionGrid(optionLabel: g.optionLabel, criteria: g.criteria, options: g.options.map { option in
            DecisionGrid.Option(name: option.name,
                                cells: option.cells.map { DecisionGrid.Cell(rating: $0.rating, text: $0.text) })
        })
    }

    func testADEV189_readsEveryFixtureGrid() throws {
        for c in try fixture().serialise {
            XCTAssertEqual(DecisionGrid.parse(c.markdown)?.grid, c.grid.map(grid), c.name)
        }
    }

    func testADEV189_writesEveryFixtureGrid() throws {
        for c in try fixture().serialise {
            guard let expected = c.grid, let serialized = c.serialized else { continue }
            XCTAssertEqual(grid(expected).markdown, serialized, c.name)
        }
    }

    func testADEV189_anEditLeavesTheProseAroundTheGridAlone() throws {
        let f = try fixture()
        let original = try XCTUnwrap(f.serialise.first)
        XCTAssertEqual(DecisionGrid.replace(in: original.markdown, with: grid(f.edit.grid)), f.edit.markdown,
                       f.edit.name)
    }

    func testADEV189_replacingWhereThereIsNoGridIsRefused() {
        XCTAssertNil(DecisionGrid.replace(in: "No table here.", with: DecisionGrid(optionLabel: "Option",
                                                                                    criteria: ["A"], options: [])))
    }

    /// The grid never gets a score column (web ADEV-178): writing adds nothing but the rows.
    func testADEV189_writingAddsNoScoreColumn() {
        let g = DecisionGrid(optionLabel: "Option", criteria: ["Cost"], options: [
            .init(name: "Go", cells: [.init(rating: "++", text: "cheap")]),
        ])
        XCTAssertEqual(g.markdown, "| Option | Cost |\n|---|---|\n| 1. Go | ++ cheap |")
    }

    /// A cell with a rating picked and its words cleared writes just the token.
    func testADEV189_aCellIsItsRatingThenItsWords() {
        XCTAssertEqual(DecisionGrid.Cell(rating: "~", text: "").markdown, "~")
        XCTAssertEqual(DecisionGrid.Cell(rating: nil, text: "").markdown, "")
        XCTAssertEqual(DecisionGrid.Cell(rating: "-", text: "slow").markdown, "- slow")
    }

    /// The tokens a cell may carry, in the order a picker shows them: worst to best, from the core.
    func testADEV189_theRatingPickerOffersTheCoresTokensWorstToBest() {
        XCTAssertEqual(DecisionGrid.ratingTokens, ["--", "-", "~", "+", "++"])
    }
}
