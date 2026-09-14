//  ListSettingsPayloadTests.swift
//  AITD-409 — the list-settings diff, now that it is a pure function instead of ~85 lines inlined
//  in `TaskListView.handleListUpdate`.
//
//  The extraction is the point of these tests as much as the coverage is. While this logic lived
//  inside a 1,700-line view it was untestable, and a missing field looked exactly like every other
//  line around it — which is how the admin tab's "Recently completed" picker came to update the
//  local model and then be dropped before the request (task 545812e6). That omission is a one-line
//  test here.

import XCTest
@testable import Astrid_App

final class ListSettingsPayloadTests: XCTestCase {

    private func list(_ id: String = "list-1") -> TaskList {
        TaskList(id: id, name: "Groceries")
    }

    // MARK: - Only what changed

    func testAITD409_NothingChangedSendsNothing() {
        let original = list()
        XCTAssertTrue(ListSettingsPayload.updates(original: original, updated: original).isEmpty,
                      "an empty diff must produce no request at all")
    }

    func testAITD409_OnlyTheChangedKeysAreSent() {
        var updated = list()
        updated.name = "Shopping"

        let updates = ListSettingsPayload.updates(original: list(), updated: updated)
        XCTAssertEqual(Set(updates.keys), ["name"], "a rename must not carry its neighbours along")
        XCTAssertEqual(updates["name"] as? String, "Shopping")
    }

    /// The reason the "only changed keys" rule matters, rather than a nicety: a rename used to
    /// carry a `showSubtasks` value with it and quietly hide the list's subtasks (ba1deb9d).
    func testAITD409_ARenameDoesNotCarryShowSubtasks() {
        var original = list()
        original.showSubtasks = true
        var updated = original
        updated.name = "Shopping"

        let updates = ListSettingsPayload.updates(original: original, updated: updated)
        XCTAssertFalse(updates.keys.contains("showSubtasks"),
                       "unchanged showSubtasks must stay out of the payload")
    }

    // MARK: - Clearing a field is NSNull, never an absent key

    /// Swift drops a `nil` value from a dictionary, and an absent key means "leave it alone" to
    /// the server — so a cleared field sent as `nil` would silently keep its old value. Every
    /// nullable field has to spell the clear as `NSNull()`.
    func testAITD409_ClearingANullableFieldSendsNSNullRatherThanDroppingTheKey() {
        var original = list()
        original.defaultAssigneeId = "user-7"
        original.defaultDueTime = "09:00"
        original.imageUrl = "/uploads/list.png"

        var cleared = original
        cleared.defaultAssigneeId = nil
        cleared.defaultDueTime = nil
        cleared.imageUrl = nil

        let updates = ListSettingsPayload.updates(original: original, updated: cleared)
        for key in ["defaultAssigneeId", "defaultDueTime", "imageUrl"] {
            XCTAssertTrue(updates.keys.contains(key), "\(key) must be present to clear it")
            XCTAssertTrue(updates[key] is NSNull, "\(key) must clear via NSNull, not an absent key")
        }
    }

    func testAITD409_SettingANullableFieldSendsTheValue() {
        var updated = list()
        updated.defaultAssigneeId = "user-7"

        let updates = ListSettingsPayload.updates(original: list(), updated: updated)
        XCTAssertEqual(updates["defaultAssigneeId"] as? String, "user-7")
    }

    // MARK: - The field that was missing

    /// Task 545812e6: this branch did not exist, so choosing a different "Recently completed"
    /// window updated the local model and never reached the server.
    func testAITD409_RecentlyCompletedWindowIsActuallySent() {
        let original = list()
        var updated = original
        updated.recentlyCompletedWindow = .duration(amount: 7, unit: .day)

        let updates = ListSettingsPayload.updates(original: original, updated: updated)
        let sent = updates["recentlyCompletedWindow"] as? [String: Any]
        XCTAssertEqual(sent?["kind"] as? String, "duration", "changing the window must reach the request")
        XCTAssertEqual(sent?["amount"] as? Int, 7)
        XCTAssertEqual(sent?["unit"] as? String, "day")
    }

    func testAITD409_ClearingTheRecentlyCompletedWindowSendsNSNull() {
        var original = list()
        original.recentlyCompletedWindow = .duration(amount: 7, unit: .day)
        var updated = original
        updated.recentlyCompletedWindow = nil

        let updates = ListSettingsPayload.updates(original: original, updated: updated)
        XCTAssertTrue(updates["recentlyCompletedWindow"] is NSNull,
                      "NSNull is the legacy 24h default — omitting the key keeps the old window")
    }

    // MARK: - Defaults for the non-nullable-on-the-wire fields

    /// These fields are optional on the model but must never reach the server as null, so a clear
    /// becomes the documented default rather than `NSNull`.
    func testAITD409_ClearedFiltersFallBackToTheirWireDefaults() {
        var original = list()
        original.filterPriority = "high"
        original.filterCompletion = "completed"
        original.filterInLists = "some"
        original.sortBy = "dueDate"

        var cleared = original
        cleared.filterPriority = nil
        cleared.filterCompletion = nil
        cleared.filterInLists = nil
        cleared.sortBy = nil

        let updates = ListSettingsPayload.updates(original: original, updated: cleared)
        XCTAssertEqual(updates["filterPriority"] as? String, "all")
        XCTAssertEqual(updates["filterCompletion"] as? String, "default")
        XCTAssertEqual(updates["filterInLists"] as? String, "dont_filter")
        XCTAssertEqual(updates["sortBy"] as? String, "manual")
    }

    func testAITD409_PrivacyIsSentAsItsWireValue() {
        var updated = list()
        updated.privacy = .PUBLIC

        let updates = ListSettingsPayload.updates(original: list(), updated: updated)
        XCTAssertEqual(updates["privacy"] as? String, TaskList.Privacy.PUBLIC.rawValue)
    }
}
