import XCTest
@testable import Astrid_App

/// `ListSettingsApply` is the mirror of `ListSettingsPayload`, extracted out of
/// `ListService.updateListAdvanced` (AITD-410). These pin the two rules that were invisible while
/// it was a wall of `if let`s inside a 1,000-line service: an absent key must leave its field
/// alone, and a cleared field must actually clear.
final class ListSettingsApplyTests: XCTestCase {

    private func list(_ id: String = "list-1") -> TaskList {
        TaskList(id: id, name: "Groceries")
    }

    func testAITD410_anAbsentKeyLeavesItsFieldAlone() {
        var original = list()
        original.sortBy = "manual"
        original.defaultAssigneeId = "user-1"

        let updated = ListSettingsApply.applying(["name": "Errands"], to: original)

        XCTAssertEqual(updated.name, "Errands")
        XCTAssertEqual(updated.sortBy, "manual", "an omitted key means 'leave it alone'")
        XCTAssertEqual(updated.defaultAssigneeId, "user-1")
    }

    /// The sheet sends `NSNull()` to mean "clear this field". `NSNull` casts to nil through
    /// `as? String`, so a branch testing the cast rather than the KEY cannot tell a cleared field
    /// from an absent one — and the old value would sit on screen until the next fetch.
    func testAITD410_anExplicitNullClearsTheFieldRatherThanBeingIgnored() {
        var original = list()
        original.defaultAssigneeId = "user-1"
        original.defaultDueTime = "09:00"

        let updated = ListSettingsApply.applying(
            ["defaultAssigneeId": NSNull(), "defaultDueTime": NSNull()], to: original)

        XCTAssertNil(updated.defaultAssigneeId, "an explicitly cleared assignee must actually clear")
        XCTAssertNil(updated.defaultDueTime)
    }

    func testAITD410_unknownKeysAreIgnored() {
        let updated = ListSettingsApply.applying(["somethingElse": "x"], to: list())
        XCTAssertEqual(updated.name, "Groceries")
    }

    func testAITD410_appliesFiltersAndDefaults() {
        let updated = ListSettingsApply.applying([
            "filterPriority": "high",
            "filterCompletion": "all",
            "defaultPriority": 2,
            "showSubtasks": false,
        ], to: list())

        XCTAssertEqual(updated.filterPriority, "high")
        XCTAssertEqual(updated.filterCompletion, "all")
        XCTAssertEqual(updated.defaultPriority, 2)
        XCTAssertEqual(updated.showSubtasks, false)
    }

    /// The property that keeps the two halves honest: anything `ListSettingsPayload` emits for an
    /// edit, applying that same dictionary must reproduce. A field added to one and forgotten in
    /// the other fails here rather than going missing in the app.
    func testAITD410_applyingThePayloadReproducesTheEdit() {
        var original = list()
        original.defaultAssigneeId = "user-1"
        original.sortBy = "manual"

        var edited = original
        edited.name = "Errands"
        edited.sortBy = "dueDate"
        edited.defaultAssigneeId = nil
        edited.filterPriority = "high"

        let updates = ListSettingsPayload.updates(original: original, updated: edited)
        let applied = ListSettingsApply.applying(updates, to: original)

        XCTAssertEqual(applied.name, edited.name)
        XCTAssertEqual(applied.sortBy, edited.sortBy)
        XCTAssertEqual(applied.filterPriority, edited.filterPriority)
        XCTAssertNil(applied.defaultAssigneeId, "the cleared assignee must survive the round trip")
    }
}
