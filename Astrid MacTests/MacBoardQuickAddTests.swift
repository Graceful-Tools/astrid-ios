//  MacBoardQuickAddTests.swift
//  Regression guard for Task AITD-431 — "mac app has duplicative 'add a task...' box below all
//  the board lists. Keep the board lists ones, format them like the standard one (use same
//  component). and remove the central one when in board view."
//
//  The board drew TWO ways to add: a plain "+ Add task" field at the foot of every column, and
//  the list's floating quick-add pinned under the whole board (e466eab8). The column field was a
//  bare TextField — no list defaults, no smart parsing, no defaults picker, no ⊕ — so the two
//  also disagreed about what a new task would be. Now every column draws the list's own bar,
//  and the central one is gone from the board.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardQuickAddTests: XCTestCase {

    private func macSource(_ relative: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - Layout

    /// The central bar is gone from the board: `boardColumn` draws the board and nothing under it.
    func testTheBoardNoLongerDrawsTheCentralQuickAdd() throws {
        let source = try macSource("Astrid Mac/App/MacRootView.swift")
        guard let start = source.range(of: "private func boardColumn(") else {
            return XCTFail("MacRootView.boardColumn not found — did it move?")
        }
        let tail = source[start.upperBound...]
        let end = tail.range(of: "\n    /// ")?.lowerBound ?? tail.endIndex
        XCTAssertFalse(String(tail[..<end]).contains("quickAddBar"),
                       "the board's columns each have an add bar; a second one under the board is the duplicate")
    }

    /// One component, both places: the list's bar and every column's bar are the same view.
    func testTheColumnsAndTheListDrawTheSameBar() throws {
        XCTAssertTrue(try macSource("Astrid Mac/App/MacRootView.swift").contains("MacQuickAddBar("),
                      "the list column's quick-add must be the shared bar")
        let board = try macSource("Astrid Mac/Views/MacBoardView.swift")
        XCTAssertTrue(board.contains("MacQuickAddBar("),
                      "each board column must draw the shared bar")
        XCTAssertFalse(board.contains("draftByColumn"),
                       "the column's own bare TextField (and its drafts) is the drift this removes")
    }

    // MARK: - What a column add creates

    private let domain = "list-board"

    private func args(listIds: [String], title: String = "Buy milk") -> MacQuickAdd.CreateArgs {
        MacQuickAdd.CreateArgs(title: title, listIds: listIds, priority: 2, whenDate: nil,
                               repeating: "weekly", repeatingData: nil,
                               assigneeId: "u2", isPrivate: true)
    }

    /// The column decides membership and role; the typed text and the list's defaults decide the
    /// rest. Losing either half makes the column bar worse than the one it replaces.
    func testAColumnAddKeepsTheParsedFieldsAndTakesTheColumnsPlacement() {
        let card = MacBoardAdd.NewCard(listIds: [domain, "status-doing"], statusRole: "doing", complete: false)
        let placed = MacBoardAdd.placing(args(listIds: [domain]), in: card)
        XCTAssertEqual(placed.listIds, [domain, "status-doing"])
        XCTAssertEqual(placed.title, "Buy milk")
        XCTAssertEqual(placed.priority, 2)
        XCTAssertEqual(placed.repeating, "weekly")
        XCTAssertEqual(placed.assigneeId, "u2")
        XCTAssertEqual(placed.isPrivate, true)
    }

    /// A #list typed into a column's bar still adds that list — smart parsing is part of what the
    /// column gains by sharing the bar.
    func testATypedListIsKeptAlongsideTheColumnsLists() {
        let card = MacBoardAdd.NewCard(listIds: [domain], statusRole: nil, complete: false)
        let placed = MacBoardAdd.placing(args(listIds: [domain, "list-errands"]), in: card)
        XCTAssertEqual(placed.listIds, [domain, "list-errands"],
                       "the column's lists first, then any the text named — once each")
    }
}
#endif
