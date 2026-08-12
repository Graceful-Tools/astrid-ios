//  MacViewModePickerTests.swift
//  Regression guard for Task 6d709a75 — "remove the list / message / board toggle when there is
//  only one option".
//
//  The toolbar's segmented picker always drew a List tab, added Board only for a list that has
//  one, and added Chat whenever chat was not already a permanent column. On a wide window
//  showing a list with no board, that is a one-tab segmented control: a switch with nothing to
//  switch to.
//
//  Two rules, both pure so they can be checked without a window:
//   • availableModes — what the picker could offer. Chat needs a CHANNEL, not merely the absence
//     of the chat column; Search has no channel, so its Chat tab fell through to the list view.
//   • showsModePicker — draw it only when at least two of those are reachable, and never when
//     the control is not switchable in the first place.

import XCTest
@testable import Astrid_Mac

final class MacViewModePickerTests: XCTestCase {

    private let boardless: String? = nil

    // MARK: - What the picker can offer

    /// Jon's example: a wide window (chat is its own column) on a list with no board. List is the
    /// only thing left.
    func testWideWindowOnABoardlessListHasNothingToSwitchBetween() {
        let modes = MacViewMode.availableModes(isRealList: true, projectId: boardless,
                                               hasChannel: true, chatColumnVisible: true)
        XCTAssertEqual(modes, [.list])
    }

    /// Narrow the window and chat becomes a mode again, so there is a real choice.
    func testNarrowWindowOnABoardlessListOffersListAndChat() {
        let modes = MacViewMode.availableModes(isRealList: true, projectId: boardless,
                                               hasChannel: true, chatColumnVisible: false)
        XCTAssertEqual(modes, [.list, .chat])
    }

    /// Search has no channel at all, so a Chat tab there is a tab that renders the list.
    func testASelectionWithNoChannelIsNotOfferedChat() {
        let modes = MacViewMode.availableModes(isRealList: false, projectId: boardless,
                                               hasChannel: false, chatColumnVisible: false)
        XCTAssertEqual(modes, [.list], "Chat needs a channel, not just a hidden chat column")
    }

    // MARK: - Whether it is drawn

    func testAOneModePickerIsNotDrawn() {
        XCTAssertFalse(MacViewMode.showsModePicker(modes: [.list], isSwitchable: true))
    }

    func testTwoModesAreWorthAPicker() {
        XCTAssertTrue(MacViewMode.showsModePicker(modes: [.list, .chat], isSwitchable: true))
    }

    /// A greyed-out switch is the same complaint as a one-option switch.
    func testAPickerThatCannotBeOperatedIsNotDrawn() {
        XCTAssertFalse(MacViewMode.showsModePicker(modes: [.list, .chat, .board], isSwitchable: false))
    }
}
