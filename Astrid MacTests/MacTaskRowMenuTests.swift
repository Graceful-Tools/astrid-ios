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
    func testBoardCardOffersTheSameActionsAsAListRow_AITD372() {
        XCTAssertEqual(MacTaskRowMenu.items(for: .boardCard),
                       MacTaskRowMenu.items(for: .listRow))
    }

    /// The order is part of the contract — Delete last and destructive, after a divider, so a
    /// muscle-memory click near the bottom of the menu cannot land on it by surprise.
    func testItemOrderPutsDeleteLastAfterADivider() {
        let items = MacTaskRowMenu.items(for: .listRow)
        XCTAssertEqual(items.last, .delete)
        XCTAssertEqual(items.dropLast().last, .divider)
        XCTAssertEqual(items.first, .toggleComplete)
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
