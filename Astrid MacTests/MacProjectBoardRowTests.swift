//  MacProjectBoardRowTests.swift
//  ADEV-59: "[mac] make project board view fixed height per list (e.g. 3-4 tasks) using the same
//  format as the list board view with add task at bottom of each list."
//
//  Each row was a bare strip of cards under one header row of column names: no column panels, no
//  counts, no Add a task, and a row as tall as its longest column. Now a row IS the list's board —
//  the same `MacBoardView` — asked for that list's row of the project, at a fixed height.

import XCTest
@testable import Astrid_Mac

final class MacProjectBoardRowTests: XCTestCase {

    private func projectBoardSource() throws -> String {
        try RepositoryLocator.source(at: "Astrid Mac/Views/MacProjectBoardView.swift")
    }

    func testEachListRowIsTheListBoardItself_ADEV59() throws {
        let source = try projectBoardSource()
        XCTAssertTrue(source.contains("MacBoardView("), "a row draws the list board's own columns")
        XCTAssertTrue(source.contains("rowOfProjectId: projectId"), "under the project's columns")
        XCTAssertFalse(source.contains("private func card("), "no second card of its own")
        XCTAssertFalse(source.contains("columnHeaders"), "each column carries its own header and count")
    }

    func testARowHasAFixedHeight_ADEV59() throws {
        let source = try projectBoardSource()
        XCTAssertTrue(source.contains("columnHeight: MacLayout.projectBoardRowHeight"))
        // Three or four cards between the column's header and its Add a task bar.
        XCTAssertGreaterThanOrEqual(MacLayout.projectBoardRowHeight, 300)
        XCTAssertLessThanOrEqual(MacLayout.projectBoardRowHeight, 400)
    }

    func testTheListBoardCanBeAskedForAProjectRowAtAFixedHeight_ADEV59() throws {
        let source = try RepositoryLocator.source(at: "Astrid Mac/Views/MacBoardView.swift")
        XCTAssertTrue(source.contains("var rowOfProjectId: String?"))
        XCTAssertTrue(source.contains("var columnHeight: CGFloat?"))
        XCTAssertTrue(source.contains("BoardModel.Query(listId: listId, rowOfProjectId: rowOfProjectId, doneSince:"))
    }
}
