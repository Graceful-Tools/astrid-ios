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

    /// The `updateTask` entry for `taskId`, or nil with a description of what the journal DID
    /// hold (task e12b5390).
    ///
    /// It used to poll a hundred times "because enqueue is fire-and-forget onto the runner
    /// actor". That is no longer true and has not been for a while: `TaskService.updateTask`
    /// AWAITS `OutboxManager.enqueueUpdateTask`, which awaits `runner.persistEnqueue`, so the
    /// entry is in the journal before the call returns. The poll could therefore never have
    /// fixed anything — it could only hide which of two very different things went wrong.
    ///
    /// This failed one full predeploy run on 2026-08-16 and has not been seen since, including
    /// six consecutive full-suite runs on 2026-08-18. So rather than guess at a fix, the failure
    /// now says what it saw: an entry with the wrong taskId (a temp→real resolution nobody
    /// expected), or no updateTask entries at all (the enqueue genuinely did not happen).
    /// The short retry stays as a safety net for a loaded machine, but a miss is now reported
    /// rather than merely returned.
    private func journalEntry(taskId: String) async -> (payload: UpdateTaskOutboxPayload?, diagnosis: String) {
        var lastSeen: [String] = []
        for attempt in 0..<25 {
            let entries = await OutboxManager.shared.journalSnapshot()
            let updates = entries.filter { $0.kind == "updateTask" }
            lastSeen = updates.map { entry in
                guard let payload = try? JSONDecoder().decode(UpdateTaskOutboxPayload.self,
                                                              from: entry.payload)
                else { return "<undecodable \(entry.id.prefix(8))>" }
                return "\(payload.taskId) [\(entry.status)]"
            }
            for entry in updates {
                if let payload = try? JSONDecoder().decode(UpdateTaskOutboxPayload.self, from: entry.payload),
                   payload.taskId == taskId {
                    return (payload, attempt == 0 ? "found immediately" : "found after \(attempt) retries")
                }
            }
            try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        return (nil, lastSeen.isEmpty
                ? "the journal held NO updateTask entries at all — the enqueue did not happen"
                : "the journal held \(lastSeen.count) updateTask entries, none for this task: \(lastSeen)")
    }

    /// Run the write and say so if it THROWS, which is the other story a bare `try await` hides:
    /// the test reports a raw NSError with no indication that the journal was never reached.
    private func performWrite(_ what: String, _ write: () async throws -> Void) async {
        do { try await write() }
        catch { XCTFail("\(what) threw before the journal was ever read: \(error)") }
    }

    func testCompletingTempTaskEnqueuesUpdateOutboxEntry() async throws {
        let tempId = "temp_\(UUID().uuidString)"
        let tempTask = Task(id: tempId, title: "Backfill import", listIds: [])
        let backdated = Date(timeIntervalSince1970: 1_700_000_000)

        await performWrite("completeTask on a temp id") {
            _ = try await TaskService.shared.completeTask(
                id: tempId, completed: true, task: tempTask,
                source: .google, completedAt: backdated)
        }

        let (maybePayload, diagnosis) = await journalEntry(taskId: tempId)
        let payload = try XCTUnwrap(
            maybePayload,
            "completing a temp task must enqueue an updateTask Outbox entry — " +
            "without it the completion never reaches the server (the Google " +
            "backfill 'completed tasks arrive open' bug). \(diagnosis)")
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

        await performWrite("updateTask on a temp id") {
            _ = try await TaskService.shared.updateTask(
                taskId: tempId, title: "Edited while in flight", task: tempTask)
        }

        let (maybeEditPayload, diagnosis) = await journalEntry(taskId: tempId)
        let payload = try XCTUnwrap(
            maybeEditPayload,
            "editing a temp task must enqueue an updateTask Outbox entry, or the edit never "
            + "reaches the server. \(diagnosis)")
        XCTAssertEqual(payload.updates.title, "Edited while in flight")
    }

    /// The diagnosis has to actually SAY something, or the next occurrence is as unactionable
    /// as the first one was (task e12b5390). A missing entry must name what the journal held
    /// instead — that is the whole point of the change.
    func testAMissingEntryExplainsWhatTheJournalHeldInstead() async throws {
        let (payload, diagnosis) = await journalEntry(taskId: "temp_definitely-not-enqueued")
        XCTAssertNil(payload)
        XCTAssertTrue(diagnosis.contains("NO updateTask entries")
                      || diagnosis.contains("none for this task"),
                      "a miss must describe the journal, got: \(diagnosis)")
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
