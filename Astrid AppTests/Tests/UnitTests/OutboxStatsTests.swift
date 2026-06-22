import XCTest
@testable import Astrid_App

/// The Outbox journal stats power the soak readout: during dual-write we watch
/// for dead-lettered (dropped) or stuck-pending entries. A drop is client-side
/// (the runner gives up / never drains), so the journal is the source of truth.
final class OutboxStatsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ id: String, _ status: OutboxStatus) -> OutboxEntry {
        OutboxEntry(
            id: id, kind: "k", payload: Data(), clientRequestId: "c-\(id)",
            dependsOn: [], status: status, attempts: 0, nextAttemptAt: t0,
            lastError: nil, createdAt: t0, updatedAt: t0
        )
    }

    func testCountsByStatus() {
        let stats = OutboxStats(entries: [
            entry("a", .pending), entry("b", .pending),
            entry("c", .running),
            entry("d", .completed),
            entry("e", .failedPermanent),
        ])
        XCTAssertEqual(stats.pending, 2)
        XCTAssertEqual(stats.running, 1)
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.failedPermanent, 1)
        XCTAssertEqual(stats.total, 5)
    }

    func testHealthyWhenNoDeadLettersOrStuck() {
        let stats = OutboxStats(entries: [entry("a", .completed), entry("b", .completed)])
        XCTAssertTrue(stats.isHealthy, "all completed → healthy")
        XCTAssertEqual(stats.failedPermanent, 0)
    }

    func testNotHealthyWithDeadLetter() {
        let stats = OutboxStats(entries: [entry("a", .completed), entry("b", .failedPermanent)])
        XCTAssertFalse(stats.isHealthy, "a dead-lettered entry is a dropped write — not healthy")
    }

    func testEmptyJournalIsHealthy() {
        XCTAssertTrue(OutboxStats(entries: []).isHealthy)
        XCTAssertEqual(OutboxStats(entries: []).total, 0)
    }
}
