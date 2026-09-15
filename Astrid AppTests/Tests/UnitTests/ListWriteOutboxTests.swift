import XCTest
@testable import Astrid_App

/// A list write that fails against the server must actually be retried (AITD-410).
///
/// `ListService.createList` and `updateListAdvanced` both caught the API failure, kept the
/// optimistic value, logged "Keeping optimistic update - will sync when online" and returned
/// the optimistic object. Nothing kept that promise for updates: `CDTaskList.update(from:)`
/// never touches `syncStatus`, so the row stayed `"synced"` and the pending sweep — whose
/// predicate is `syncStatus == "pending"` — could not see it. The device showed the change
/// indefinitely, the server never learned, and the next `fetchLists()` silently reverted it.
final class ListWriteOutboxTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func updateListEntry(id: String, listId: String, createdOffset: TimeInterval) -> OutboxEntry {
        // Hand-built payload JSON so this test pins the journal's wire shape, not just the
        // encoder that happens to produce it.
        let json = #"{"listId":"\#(listId)","updatesJSON":"{\"name\":\"n\"}"}"#
        return OutboxEntry(
            id: id,
            kind: "updateList",
            payload: Data(json.utf8),
            clientRequestId: "crid-\(id)",
            dependsOn: [],
            status: .pending,
            attempts: 0,
            nextAttemptAt: t0,
            lastError: nil,
            createdAt: t0.addingTimeInterval(createdOffset),
            updatedAt: t0,
            tempId: nil
        )
    }

    /// AITD-410: two queued updates to the SAME list must share a serialization lane, or the
    /// runner dispatches them concurrently and the older one can land last — the user's final
    /// edit silently replaced by the one before it. Without a `case "updateList"` the key falls
    /// through to the `entry:<id>` default, which gives every entry its own lane.
    func testAITD410_updatesToSameListShareASerializationLane() {
        let first = updateListEntry(id: "a", listId: "L1", createdOffset: 0)
        let second = updateListEntry(id: "b", listId: "L1", createdOffset: 10)

        XCTAssertEqual(
            OutboxScheduler.serializationKey(for: first), "list:L1",
            "updateList must serialize per list id")

        let batch = OutboxScheduler.concurrentBatch(
            [first, second], limit: 4,
            serializationKey: OutboxScheduler.serializationKey(for:))

        XCTAssertEqual(batch.map(\.id), ["a"],
                       "only the oldest update for a given list may be dispatched at a time")
    }

    /// AITD-410: two updates to DIFFERENT lists are unrelated and must still run concurrently —
    /// the lane must key on the list id, not on the kind.
    func testAITD410_updatesToDifferentListsRunConcurrently() {
        let one = updateListEntry(id: "a", listId: "L1", createdOffset: 0)
        let two = updateListEntry(id: "b", listId: "L2", createdOffset: 10)

        let batch = OutboxScheduler.concurrentBatch(
            [one, two], limit: 4,
            serializationKey: OutboxScheduler.serializationKey(for:))

        XCTAssertEqual(batch.map(\.id).sorted(), ["a", "b"])
    }

    // MARK: - Payload round-trip

    /// AITD-410: `ListSettingsPayload` uses `NSNull()` to mean "clear this field" and an absent
    /// key to mean "leave it alone". A journaled update has to preserve that distinction, or a
    /// replayed write silently stops clearing the field the user cleared.
    func testAITD410_payloadRoundTripsExplicitNullDistinctFromAbsentKey() throws {
        let payload = try XCTUnwrap(UpdateListOutboxPayload(
            listId: "L1",
            updates: ["name": "Groceries", "defaultAssigneeId": NSNull()]))

        let journaled = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(UpdateListOutboxPayload.self, from: journaled)
        let updates = try XCTUnwrap(decoded.updates)

        XCTAssertEqual(decoded.listId, "L1")
        XCTAssertEqual(updates["name"] as? String, "Groceries")
        XCTAssertTrue(updates["defaultAssigneeId"] is NSNull,
                      "an explicitly cleared field must survive the journal as null, not vanish")
        XCTAssertFalse(updates.keys.contains("color"),
                       "an absent key must stay absent — the server reads it as 'leave alone'")
    }

    /// AITD-410: a body that cannot be serialized must be refused at enqueue time. Journaling it
    /// would write an entry that can only ever dead-letter on its first run.
    func testAITD410_payloadRefusesUnserializableUpdates() {
        XCTAssertNil(UpdateListOutboxPayload(listId: "L1", updates: ["when": Date()]))
    }

    /// AITD-410: the settings sheet's real diff must survive journaling intact.
    func testAITD410_payloadCarriesARealSettingsDiff() throws {
        var original = TaskList(id: "L1", name: "Old")
        original.defaultAssigneeId = "user-1"
        var edited = original
        edited.name = "New"
        edited.defaultAssigneeId = nil

        let updates = ListSettingsPayload.updates(original: original, updated: edited)
        let payload = try XCTUnwrap(UpdateListOutboxPayload(listId: "L1", updates: updates))
        let replayed = try XCTUnwrap(payload.updates)

        XCTAssertEqual(replayed["name"] as? String, "New")
        XCTAssertTrue(replayed["defaultAssigneeId"] is NSNull)
    }

    // MARK: - The create path's retry predicate

    /// AITD-410: `syncPendingLists` selected `syncStatus == "pending"` but wrote `"failed"` on a
    /// lost attempt, so the row fell out of its own retry predicate and the offline-created list
    /// was stranded permanently. "Tried and did not land" is a reason to retry, not to stop.
    func testAITD410_failedListIsStillSelectedForRetry() {
        XCTAssertTrue(ListSyncStatus.isUnsynced(ListSyncStatus.pending))
        XCTAssertTrue(ListSyncStatus.isUnsynced(ListSyncStatus.failed),
                      "a failed attempt must remain retryable, not be dropped from the sweep")
        XCTAssertFalse(ListSyncStatus.isUnsynced(ListSyncStatus.synced))
    }
}
