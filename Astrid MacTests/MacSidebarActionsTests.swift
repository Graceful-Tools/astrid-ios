//  MacSidebarActionsTests.swift
//  Regression tests for Task 0fc546a8 — "[mac] move add list above the lists in the sidebar and
//  out of the header; same for public lists".
//
//  Both lived as unlabelled toolbar icons (a bare + and a globe). iOS puts Add List as the first
//  row of the Your Lists section and surfaces public lists in the sidebar too.
//  AITD-569 then moved the Public Lists entry down to the bottom of the public lists.

import XCTest
@testable import Astrid_Mac

final class MacSidebarActionsTests: XCTestCase {

    /// Add List sits ABOVE the lists, as the first row iOS uses.
    func testAddListComesBeforeTheLists() {
        XCTAssertEqual(MacSidebarActions.aboveLists.map(\.id), ["sidebar.newList"])
    }

    /// AITD-569: the Public Lists entry point sits at the BOTTOM of the popular public lists, not
    /// at the top of your own lists, where it pushed them down and read as one of them.
    func testPublicListsEntryComesAfterThePublicLists_AITD569() {
        XCTAssertEqual(MacSidebarActions.afterPublicLists.map(\.id), ["sidebar.publicLists"])
        XCTAssertFalse(MacSidebarActions.aboveLists.contains { $0.id == "sidebar.publicLists" },
                       "the browse row is back above your lists")
    }

    /// They are labelled now, from the SHARED iOS keys — a toolbar glyph told you nothing.
    func testLabelsComeFromTheSharedKeysAndAreLocalized() {
        XCTAssertEqual(MacSidebarActions.addList.title, NSLocalizedString("navigation.add_list", comment: ""))
        XCTAssertEqual(MacSidebarActions.browsePublicLists.title, NSLocalizedString("navigation.public_lists", comment: ""))
        for action in MacSidebarActions.aboveLists + MacSidebarActions.afterPublicLists {
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertNotEqual(action.title, action.titleKey, "\(action.id) shows a raw key")
        }
    }

    /// The identifier several UI tests click to create a list must survive the move.
    func testTheNewListIdentifierIsPreserved() {
        XCTAssertTrue(MacSidebarActions.aboveLists.contains { $0.id == "sidebar.newList" },
                      "UI tests click sidebar.newList; dropping it breaks them for unrelated reasons")
    }

    func testEachActionHasASymbol() {
        for action in MacSidebarActions.aboveLists + MacSidebarActions.afterPublicLists { XCTAssertFalse(action.symbol.isEmpty) }
    }
}
