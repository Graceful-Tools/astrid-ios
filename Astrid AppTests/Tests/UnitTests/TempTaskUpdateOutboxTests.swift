import XCTest
@testable import Astrid_App

/// Locks the fix for the "hundreds of completed Google tasks arrive open" bug.
///
/// The Google backfill imports a completed task as create-then-complete. The
/// completion lands while the task still has its optimistic `temp_` id, so it
/// goes through `TaskService.updateTask(taskId: temp_…)`. That path used to
/// return early WITHOUT enqueueing an Outbox entry ("edits are saved locally,
/// legacy sync will replay them") — but the legacy replay was deleted with the
/// Outbox cutover, so the completion never reached the server: the task stayed
/// open on the server/web and reverted to open locally on the next fetch.
///
/// The contract now: updating a temp task ALWAYS enqueues an `updateTask`
/// Outbox entry keyed on the temp id. `UpdateTaskOutboxHandler` resolves
/// temp→real via the mapping (recorded when the create drains) and returns
/// `.blocked` until then — no attempt burn, correct ordering, no lost write.
@MainActor
final class TempTaskUpdateOutboxTests: XCTestCase {

    private func journalEntry(taskId: String) async -> UpdateTaskOutboxPayload? {
        // enqueue is fire-and-forget onto the runner actor — poll briefly.
        for _ in 0..<100 {
            let entries = await OutboxManager.shared.journalSnapshot()
            for entry in entries where entry.kind == "updateTask" {
                if let payload = try? JSONDecoder().decode(UpdateTaskOutboxPayload.self, from: entry.payload),
                   payload.taskId == taskId {
                    return payload
                }
            }
            try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    func testCompletingTempTaskEnqueuesUpdateOutboxEntry() async throws {
        let tempId = "temp_\(UUID().uuidString)"
        let tempTask = Task(id: tempId, title: "Backfill import", listIds: [])
        let backdated = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await TaskService.shared.completeTask(
            id: tempId, completed: true, task: tempTask,
            source: .google, completedAt: backdated)

        let maybePayload = await journalEntry(taskId: tempId)
        let payload = try XCTUnwrap(
            maybePayload,
            "completing a temp task must enqueue an updateTask Outbox entry — " +
            "without it the completion never reaches the server (the Google " +
            "backfill 'completed tasks arrive open' bug)")
        XCTAssertEqual(payload.updates.completed, true)
        XCTAssertEqual(payload.source, "google")
        XCTAssertEqual(payload.updates.completedAt, ISO8601DateFormatter().string(from: backdated),
                       "backdated completedAt must survive onto the wire payload")
        XCTAssertEqual(payload.updates.completedSource, "google")
    }

    func testEditingTempTaskEnqueuesUpdateOutboxEntry() async throws {
        // Same contract for plain edits: an offline-created task edited before
        // its create drains must not lose the edit server-side.
        let tempId = "temp_\(UUID().uuidString)"
        let tempTask = Task(id: tempId, title: "Original", listIds: [])

        _ = try await TaskService.shared.updateTask(
            taskId: tempId, title: "Edited while in flight", task: tempTask)

        let maybeEditPayload = await journalEntry(taskId: tempId)
        let payload = try XCTUnwrap(maybeEditPayload)
        XCTAssertEqual(payload.updates.title, "Edited while in flight")
    }

    func testBlockedTempUpdateDoesNotBurnAttempts() async throws {
        // The handler must hold the entry (.blocked), not fail it, while the
        // temp→real mapping is missing.
        let tempId = "temp_\(UUID().uuidString)"
        let payload = UpdateTaskOutboxPayload(
            taskId: tempId,
            updates: UpdateTaskRequest(completed: true),
            source: "google")
        let entry = OutboxEntry(
            id: UUID().uuidString, kind: "updateTask",
            payload: try JSONEncoder().encode(payload),
            clientRequestId: UUID().uuidString, dependsOn: [], status: .pending,
            attempts: 0, nextAttemptAt: Date(), lastError: nil,
            createdAt: Date(), updatedAt: Date())

        let result = await UpdateTaskOutboxHandler.handle(entry)
        guard case .blocked = result else {
            return XCTFail("expected .blocked while temp id unmapped, got \(result)")
        }
    }
}
