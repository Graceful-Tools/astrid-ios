//  MacTaskRowMenuTests.swift
//  Astrid for Mac — AITD-372: a board card offers the same right-click actions as a list row.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacTaskRowMenuTests: XCTestCase {

    private func list(_ id: String, _ name: String) -> TaskList {
        TaskList(id: id, name: name)
    }

    /// AITD-372. Right-click on a board card did nothing at all — the card carried no
    /// `.contextMenu`, while the list row carried nine actions. Jon: "make right click for
    /// extra actions work on task row on board mode just like list mode".
    ///
    /// The two surfaces render from ONE item list rather than two copies of a menu, so this
    /// asserts the thing that actually has to stay true: whatever a list row offers, a board
    /// card offers, in the same order.
    ///
    /// Containment rather than equality since AITD-377 — a card offers one thing a row has no
    /// meaning for. It still fails if a row-only action is ever added, which is the point.
    func testBoardCardOffersEveryListRowAction_AITD372() {
        let card = MacTaskRowMenu.items(for: .boardCard)
        let row = MacTaskRowMenu.items(for: .listRow)
        XCTAssertEqual(card.filter { row.contains($0) }, row,
                       "a board card must still offer every list-row action, in the same order")
    }

    /// AITD-377 / AWTD-872, Jon: "move expand button on board tsk view to inside the ... menu.
    /// currently it is too cluttered. do the same thing across iOS and web."
    ///
    /// Full screen leads the card's menu, the position web gave it. It is a view control used
    /// occasionally, not the card's primary gesture, so it is the one that leaves the gutter —
    /// while collapse stays a button, because it undoes the click that expanded the card.
    func testBoardCardMenuLeadsWithFullScreen_AITD377() {
        XCTAssertEqual(MacTaskRowMenu.items(for: .boardCard).first, .fullScreen)
    }

    /// ...and a list row never offers it. A row has no inline expansion, so "full screen" would
    /// be an action with no subject there.
    func testListRowHasNoFullScreenItem_AITD377() {
        XCTAssertFalse(MacTaskRowMenu.items(for: .listRow).contains(.fullScreen))
    }

    /// The order is part of the contract — Delete last and destructive, after a divider, so a
    /// muscle-memory click near the bottom of the menu cannot land on it by surprise.
    func testItemOrderPutsDeleteLastAfterADivider() {
        let items = MacTaskRowMenu.items(for: .listRow)
        XCTAssertEqual(items.last, .delete)
        XCTAssertEqual(items.dropLast().last, .divider)
        XCTAssertEqual(items.first, .toggleComplete)
        // The card's menu leads with full screen, so its first SHARED item is still Complete.
        XCTAssertEqual(MacTaskRowMenu.items(for: .boardCard).dropFirst().first, .toggleComplete)
    }

    /// The leading item names the action it performs, not the state it is in.
    func testCompleteLabelFlipsWithTheTaskState() {
        XCTAssertEqual(MacTaskRowMenu.completeLabelKey(completed: false), "reminders.complete")
        XCTAssertEqual(MacTaskRowMenu.completeLabelKey(completed: true), "mac.mark_incomplete")
    }

    /// "Move to list" must not offer the list the task is already in — moving a task to where
    /// it already is is a write that does nothing, and it makes the menu longer for no reason.
    func testMoveTargetsExcludeTheCurrentList() {
        let lists = [list("a", "Work"), list("b", "Home"), list("c", "Errands")]
        let targets = MacTaskRowMenu.moveTargets(lists: lists, currentListId: "b")
        XCTAssertEqual(targets.map(\.id), ["a", "c"])
    }

    /// With no list in context (a saved/virtual selection) every list is a valid destination.
    func testMoveTargetsKeepEveryListWhenThereIsNoCurrentList() {
        let lists = [list("a", "Work"), list("b", "Home")]
        XCTAssertEqual(MacTaskRowMenu.moveTargets(lists: lists, currentListId: nil).map(\.id),
                       ["a", "b"])
    }
}
#endif
