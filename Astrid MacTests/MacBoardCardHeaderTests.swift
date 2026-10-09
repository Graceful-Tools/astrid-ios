//  MacBoardCardHeaderTests.swift
//  Regression guards for two board-card reports from 2026-10-09:
//
//  AITD-470 — "[mac] board add vertical ... on open card like on web". Web's open card carries a
//  ⋮ (TaskActionMenu, compact) beside its caret; the Mac card's actions were reachable only by
//  right-click, which nothing on the card advertises.
//
//  AITD-471 — "[mac] cannot edit task title on board cards". The open card's editor is built
//  with `showsTitle: false` because the card face already shows the title — but the face drew it
//  as a plain `Text` whose click COLLAPSED the card, so no surface on the board could change a
//  title. Even the menu's Rename only expanded the card, into an editor with no title field.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardCardHeaderTests: XCTestCase {

    // MARK: AITD-470 — the ⋮ on an open card

    func testAnOpenCardOffersTheActionsMenuBesideTheCaret() {
        XCTAssertEqual(MacBoardExpand.headerControls(expanded: true), [.actionsMenu, .collapse])
    }

    func testAClosedCardKeepsJustTheCaret() {
        // Web shows the ⋮ only on the open card; a closed one stays a quiet face.
        XCTAssertEqual(MacBoardExpand.headerControls(expanded: false), [.collapse])
    }

    func testTheMenuIsTheSameActionsAsRightClick() {
        // The ⋮ renders the shared model, so it cannot become a third, drifting menu.
        XCTAssertEqual(MacBoardCardActionsMenu.items, MacTaskRowMenu.items(for: .boardCard))
    }

    // MARK: AITD-471 — editing the title on a card

    func testTheOpenCardsTitleIsAField() {
        XCTAssertTrue(MacBoardExpand.titleIsEditable(expanded: true))
        XCTAssertFalse(MacBoardExpand.titleIsEditable(expanded: false))
    }

    func testClickingTheTitleOpensButNeverCollapses() {
        // A click into the field to place the caret used to close the card under it.
        XCTAssertEqual(MacBoardExpand.titleTap(current: nil, tapped: "a"), "a")
        XCTAssertEqual(MacBoardExpand.titleTap(current: "a", tapped: "a"), "a")
        XCTAssertEqual(MacBoardExpand.titleTap(current: "b", tapped: "a"), "a")
        // The caret still toggles.
        XCTAssertNil(MacBoardExpand.toggle(current: "a", tapped: "a"))
    }

    func testTitleSaveRule() {
        XCTAssertEqual(MacTaskTitleEdit.titleToSave(draft: "  New name ", current: "Old"), "New name")
        XCTAssertNil(MacTaskTitleEdit.titleToSave(draft: "Old", current: "Old"), "unchanged → no write")
        XCTAssertNil(MacTaskTitleEdit.titleToSave(draft: "   ", current: "Old"), "never blank a title")
    }
}
#endif
