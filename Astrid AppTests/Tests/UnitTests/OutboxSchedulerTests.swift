import XCTest
@testable import Astrid_App

/// Tests for the Outbox's pure scheduling logic — the part that decides what
/// runs, when, in what order, and when to give up. This is the highest-risk
/// piece (a bug here breaks every offline write), so it's pure and exhaustively
/// unit-tested before any I/O or service wiring is added.
///
/// See the "unified Outbox for offline-first writes" task.
final class OutboxSchedulerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(
        id: String,
        kind: String = "createComment",
        dependsOn: [String] = [],
        status: OutboxStatus = .pending,
        attempts: Int = 0,
        nextAttemptOffset: TimeInterval = 0,
        createdOffset: TimeInterval = 0,
        tempId: String? = nil
    ) -> OutboxEntry {
        OutboxEntry(
            id: id,
            kind: kind,
            payload: Data(),
            clientRequestId: "crid-\(id)",
            dependsOn: dependsOn,
            status: status,
            attempts: attempts,
            nextAttemptAt: t0.addingTimeInterval(nextAttemptOffset),
            lastError: nil,
            createdAt: t0.addingTimeInterval(createdOffset),
            updatedAt: t0,
            tempId: tempId
        )
    }

    // MARK: - Liveness recovery (review P1: Outbox liveness triad)

    func testRecoveredOnLoad_resetsRunningToPending() {
        // A crash mid-handler can persist an entry as .running; on relaunch it's
        // neither runnable nor pruned nor stranded → wedged forever.
        let loaded = OutboxScheduler.recoveredOnLoad([
            entry(id: "a", status: .running),
            entry(id: "b", status: .pending),
            entry(id: "c", status: .completed),
            entry(id: "d", status: .failedPermanent),
        ])
        XCTAssertEqual(loaded.first { $0.id == "a" }?.status, .pending)
        XCTAssertEqual(loaded.first { $0.id == "b" }?.status, .pending)
        XCTAssertEqual(loaded.first { $0.id == "c" }?.status, .completed)
        XCTAssertEqual(loaded.first { $0.id == "d" }?.status, .failedPermanent)
    }

    func testTempStranded_deadLettersConsumerOfFailedCreate() {
        // updateTask/deleteTask on a temp task whose createTask dead-lettered
        // would otherwise return .blocked forever (no explicit dependsOn edge).
        let entries = [
            entry(id: "create", kind: "createTask", status: .failedPermanent, tempId: "temp_1"),
            entry(id: "update", kind: "updateTask", status: .pending, tempId: "temp_1"),
            entry(id: "delete", kind: "deleteTask", status: .pending, tempId: "temp_1"),
            entry(id: "other", kind: "updateTask", status: .pending, tempId: "temp_2"),
        ]
        let stranded = OutboxScheduler.tempStrandedEntryIds(entries)
        XCTAssertEqual(stranded, ["update", "delete"])
    }

    func testTempStranded_keepsConsumerWhenCreateStillPending() {
        let entries = [
            entry(id: "create", kind: "createTask", status: .pending, tempId: "temp_1"),
            entry(id: "update", kind: "updateTask", status: .pending, tempId: "temp_1"),
        ]
        XCTAssertTrue(OutboxScheduler.tempStrandedEntryIds(entries).isEmpty)
    }

    func testTempStranded_keepsConsumerWhenCreateSucceeded() {
        // Create completed (temp resolved via mapping) → consumer must run, not strand.
        let entries = [
            entry(id: "create", kind: "createTask", status: .completed, tempId: "temp_1"),
            entry(id: "update", kind: "updateTask", status: .pending, tempId: "temp_1"),
        ]
        XCTAssertTrue(OutboxScheduler.tempStrandedEntryIds(entries).isEmpty)
    }

    // MARK: - Backoff

    func testBackoffGrowsExponentiallyAndIsCapped() {
        let d1 = OutboxScheduler.backoffDelay(attempts: 1)
        let d2 = OutboxScheduler.backoffDelay(attempts: 2)
        let d3 = OutboxScheduler.backoffDelay(attempts: 3)
        XCTAssertLessThan(d1, d2)
        XCTAssertLessThan(d2, d3)
        // Far-future attempt is clamped to the max, never unbounded.
        XCTAssertEqual(OutboxScheduler.backoffDelay(attempts: 100), OutboxScheduler.maxBackoff)
    }

    func testNextAttemptDateIsNowPlusBackoff() {
        let next = OutboxScheduler.nextAttemptDate(now: t0, attempts: 1)
        XCTAssertEqual(next.timeIntervalSince(t0), OutboxScheduler.backoffDelay(attempts: 1), accuracy: 0.001)
    }

    // MARK: - Permanent failure classification

    func testPermanentFailureForAuthValidationNotFound() {
        for code in [400, 401, 403, 404, 410, 422] {
            XCTAssertTrue(OutboxScheduler.isPermanentFailure(httpStatus: code), "\(code) should be permanent")
        }
        for code in [408, 429, 500, 502, 503] {
            XCTAssertFalse(OutboxScheduler.isPermanentFailure(httpStatus: code), "\(code) should be retryable")
        }
    }

    func testDeadLetterAfterMaxAttempts() {
        XCTAssertFalse(OutboxScheduler.shouldDeadLetter(attempts: OutboxScheduler.maxAttempts - 1))
        XCTAssertTrue(OutboxScheduler.shouldDeadLetter(attempts: OutboxScheduler.maxAttempts))
    }

    // MARK: - Dependencies

    func testDependenciesSatisfiedOnlyWhenAllCompleted() {
        let e = entry(id: "c", dependsOn: ["a", "b"])
        XCTAssertFalse(OutboxScheduler.dependenciesSatisfied(e, completedIds: ["a"]))
        XCTAssertTrue(OutboxScheduler.dependenciesSatisfied(e, completedIds: ["a", "b"]))
        XCTAssertTrue(OutboxScheduler.dependenciesSatisfied(entry(id: "x"), completedIds: []))
    }

    // MARK: - Runnable

    func testRunnableRequiresPendingDueNotInFlightDepsMet() {
        let ready = entry(id: "1")
        XCTAssertTrue(OutboxScheduler.isRunnable(ready, now: t0, completedIds: [], inFlightIds: []))

        // Not yet due
        let future = entry(id: "2", nextAttemptOffset: 60)
        XCTAssertFalse(OutboxScheduler.isRunnable(future, now: t0, completedIds: [], inFlightIds: []))

        // In flight
        XCTAssertFalse(OutboxScheduler.isRunnable(ready, now: t0, completedIds: [], inFlightIds: ["1"]))

        // Already running / completed / dead are never runnable
        XCTAssertFalse(OutboxScheduler.isRunnable(entry(id: "3", status: .running), now: t0, completedIds: [], inFlightIds: []))
        XCTAssertFalse(OutboxScheduler.isRunnable(entry(id: "4", status: .completed), now: t0, completedIds: [], inFlightIds: []))
        XCTAssertFalse(OutboxScheduler.isRunnable(entry(id: "5", status: .failedPermanent), now: t0, completedIds: [], inFlightIds: []))

        // Unmet dependency
        let blocked = entry(id: "6", dependsOn: ["nope"])
        XCTAssertFalse(OutboxScheduler.isRunnable(blocked, now: t0, completedIds: [], inFlightIds: []))
    }

    func testRunnableEntriesAreDepsAwareAndOrderedByCreatedAt() {
        // a (older) completed; b depends on a (runnable); c depends on missing (blocked); d ready (newer)
        let a = entry(id: "a", status: .completed, createdOffset: 0)
        let b = entry(id: "b", dependsOn: ["a"], createdOffset: 10)
        let c = entry(id: "c", dependsOn: ["missing"], createdOffset: 5)
        let d = entry(id: "d", createdOffset: 20)

        let runnable = OutboxScheduler.runnableEntries([d, c, b, a], now: t0, inFlightIds: [])
        XCTAssertEqual(runnable.map { $0.id }, ["b", "d"],
                       "only dependency-satisfied pending entries, oldest first")
    }
}
