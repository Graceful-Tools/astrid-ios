//  ListSubtaskVisibilityTests.swift
//  Regression guard for Task ba1deb9d — per-list show/hide subtasks (iOS/Mac).
//
//  The Swift twin of astrid-web's `lib/list-subtask-visibility.ts`. Two controls answer different
//  questions and the combination is the whole feature:
//
//    - the USER setting `subtaskDisplay` — WHERE subtasks appear at all ('indented' inline, or
//      'under_parent' meaning detail view only). The broader of the two.
//    - the LIST setting `showSubtasks` — whether THIS list shows them inline.
//
//  The asymmetry is the point: a list can opt OUT, but cannot opt back IN over a user who has
//  chosen detail-only, because that choice is about the product rather than one list.
//
//  `nil` means SHOW. Every list decoded by a build that predates the field reads back nil, and
//  treating that as "hide" would silently empty all of them at once.

import XCTest
@testable import Astrid_App

final class ListSubtaskVisibilityTests: XCTestCase {

    // MARK: - The list's half

    func testAListWithNoOpinionShowsSubtasks() {
        XCTAssertTrue(ListSubtaskVisibility.listShowsSubtasks(nil),
                      "Absent means SHOW — a list fetched before the field existed must not empty")
    }

    func testAListThatSaysTrueShowsSubtasks() {
        XCTAssertTrue(ListSubtaskVisibility.listShowsSubtasks(true))
    }

    func testOnlyAnExplicitFalseHidesThem() {
        XCTAssertFalse(ListSubtaskVisibility.listShowsSubtasks(false))
    }

    // MARK: - Combined with the user setting

    /// The default combination: nothing set anywhere, subtasks splice inline as they always have.
    func testDefaultsSpliceInline() {
        XCTAssertTrue(ListSubtaskVisibility.shouldSplice(listShowSubtasks: nil, subtaskDisplay: nil))
        XCTAssertTrue(ListSubtaskVisibility.shouldSplice(listShowSubtasks: nil, subtaskDisplay: "indented"))
    }

    /// A list can opt OUT.
    func testAListCanTurnItsOwnSubtasksOff() {
        XCTAssertFalse(ListSubtaskVisibility.shouldSplice(listShowSubtasks: false, subtaskDisplay: "indented"))
    }

    /// A list CANNOT opt back in over a detail-only user — the more restrictive setting wins, and
    /// the user's is the one that cannot be overridden.
    func testAListCannotOverrideADetailOnlyUser() {
        for listSetting: Bool? in [nil, true, false] {
            XCTAssertFalse(
                ListSubtaskVisibility.shouldSplice(listShowSubtasks: listSetting,
                                                   subtaskDisplay: "under_parent"),
                "under_parent wins whatever the list says (list=\(String(describing: listSetting)))")
        }
    }

    /// A display mode this build does not recognise must behave like 'indented', not like hidden —
    /// a future mode must not blank out every list on an older client.
    func testAnUnrecognisedDisplayModeStillSplices() {
        XCTAssertTrue(ListSubtaskVisibility.shouldSplice(listShowSubtasks: nil, subtaskDisplay: "some_future_mode"))
        XCTAssertTrue(ListSubtaskVisibility.shouldSplice(listShowSubtasks: true, subtaskDisplay: ""))
    }

    // MARK: - What goes on the wire

    /// The guard that matters: an unrelated edit must not carry a showSubtasks value along with
    /// it, or renaming a list would silently hide its subtasks.
    func testAnUnchangedSettingIsNotSent() {
        for value: Bool? in [nil, true, false] {
            XCTAssertNil(ListSubtaskVisibility.payloadValue(original: value, edited: value),
                         "no change means the key is omitted (value=\(String(describing: value)))")
        }
    }

    func testTurningItOffSendsFalse() {
        XCTAssertEqual(ListSubtaskVisibility.payloadValue(original: nil, edited: false), false)
        XCTAssertEqual(ListSubtaskVisibility.payloadValue(original: true, edited: false), false)
    }

    func testTurningItBackOnSendsTrue() {
        XCTAssertEqual(ListSubtaskVisibility.payloadValue(original: false, edited: true), true)
    }

    /// Editing back to "no opinion" still has to say something, and the value that means no
    /// opinion is true — absent means show.
    func testClearingTheSettingSendsTrueRatherThanNull() {
        XCTAssertEqual(ListSubtaskVisibility.payloadValue(original: false, edited: nil), true)
    }

    // MARK: - The model carries it

    /// Decoding is half the job; 2e41c645 was a field decoded but never stored.
    func testTaskListDecodesShowSubtasksFromTheWire() throws {
        let json = #"{"id":"l1","name":"Groceries","privacy":"PRIVATE","showSubtasks":false}"#
        let list = try JSONDecoder().decode(TaskList.self, from: Data(json.utf8))
        XCTAssertEqual(list.showSubtasks, false)
    }

    /// A payload from before the field shipped leaves it nil, which means SHOW.
    func testAListWithoutTheFieldDecodesToNil() throws {
        let json = #"{"id":"l1","name":"Groceries","privacy":"PRIVATE"}"#
        let list = try JSONDecoder().decode(TaskList.self, from: Data(json.utf8))
        XCTAssertNil(list.showSubtasks)
        XCTAssertTrue(ListSubtaskVisibility.listShowsSubtasks(list.showSubtasks))
    }
}
