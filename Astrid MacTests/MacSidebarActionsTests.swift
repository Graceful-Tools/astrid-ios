//  MacSidebarActionsTests.swift
//  Regression tests for Task 0fc546a8 — "[mac] move add list above the lists in the sidebar and
//  out of the header; same for public lists".
//
//  Both lived as unlabelled toolbar icons (a bare + and a globe). iOS puts Add List as the first
//  row of the Your Lists section and surfaces public lists in the sidebar too.

import XCTest
@testable import Astrid_Mac

final class MacSidebarActionsTests: XCTestCase {

    /// Actions sit ABOVE the lists, in the order iOS uses.
    func testActionsComeBeforeTheListsAndInOrder() {
        XCTAssertEqual(MacSidebarActions.all.map(\.id), ["sidebar.newList", "sidebar.publicLists"])
        XCTAssertTrue(MacSidebarActions.appearAboveLists)
    }

    /// They are labelled now, from the SHARED iOS keys — a toolbar glyph told you nothing.
    func testLabelsComeFromTheSharedKeysAndAreLocalized() {
        XCTAssertEqual(MacSidebarActions.all[0].title, NSLocalizedString("navigation.add_list", comment: ""))
        XCTAssertEqual(MacSidebarActions.all[1].title, NSLocalizedString("navigation.public_lists", comment: ""))
        for action in MacSidebarActions.all {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertNotEqual(action.title, action.titleKey, "\(action.id) shows a raw key")
        }
    }

    /// The identifier several UI tests click to create a list must survive the move.
    func testTheNewListIdentifierIsPreserved() {
        XCTAssertTrue(MacSidebarActions.all.contains { $0.id == "sidebar.newList" },
                      "UI tests click sidebar.newList; dropping it breaks them for unrelated reasons")
    }

    func testEachActionHasASymbol() {
        for action in MacSidebarActions.all { XCTAssertFalse(action.symbol.isEmpty) }
    }
}
