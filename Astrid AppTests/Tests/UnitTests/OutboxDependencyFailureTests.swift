import XCTest
@testable import Astrid_App

/// Blocker #2: a dependent of a permanently-failed (or missing) entry can never
/// run — its dependency will never complete — so it must be dead-lettered, not
/// left pending forever. Failure propagates transitively.
final class OutboxDependencyFailureTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-depfail-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tempURL) }

    private func entry(_ id: String, status: OutboxStatus = .pending, dependsOn: [String] = []) -> OutboxEntry {
        OutboxEntry(id: id, kind: "k", payload: Data(), clientRequestId: "c-\(id)",
                    dependsOn: dependsOn, status: status, attempts: 0, nextAttemptAt: t0,
                    lastError: nil, createdAt: t0, updatedAt: t0)
    }

    // MARK: - Pure: strandedEntryIds

    func testDependentOfFailedEntryIsStranded() {
        let a = entry("a", status: .failedPermanent)
        let b = entry("b", dependsOn: ["a"])
        XCTAssertEqual(OutboxScheduler.strandedEntryIds([a, b]), ["b"])
    }

    func testStrandingIsTransitive() {
        let a = entry("a", status: .failedPermanent)
        let b = entry("b", dependsOn: ["a"])
        let c = entry("c", dependsOn: ["b"])
        XCTAssertEqual(OutboxScheduler.strandedEntryIds([a, b, c]), ["b", "c"])
    }

    func testMissingDependencyStrands() {
        let c = entry("c", dependsOn: ["never-enqueued"])
        XCTAssertEqual(OutboxScheduler.strandedEntryIds([c]), ["c"])
    }

    func testCompletedDependencyDoesNotStrand() {
        let a = entry("a", status: .completed)
        let b = entry("b", dependsOn: ["a"])
        XCTAssertTrue(OutboxScheduler.strandedEntryIds([a, b]).isEmpty)
    }

    func testPendingDependencyDoesNotStrandYet() {
        let a = entry("a")  // still pending — not failed, so b just waits
        let b = entry("b", dependsOn: ["a"])
        XCTAssertTrue(OutboxScheduler.strandedEntryIds([a, b]).isEmpty)
    }

    // MARK: - Runner integration

    func testRunnerDeadLettersStrandedDependents() async {
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: tempURL),
            handlers: [
                "dep": { _, _ in .permanent("403 forbidden") },
                "child": { _, _ in .success([:]) }
            ],
            now: { self.t0 }
        )
        await runner.enqueue(entry("a").with(kind: "dep"))
        await runner.enqueue(entry("b", dependsOn: ["a"]).with(kind: "child"))

        let snap = await runner.snapshot()
        XCTAssertEqual(snap.first { $0.id == "a" }?.status, .failedPermanent)
        XCTAssertEqual(snap.first { $0.id == "b" }?.status, .failedPermanent,
                       "the child of a dead-lettered dependency must not hang pending")
    }
}

private extension OutboxEntry {
    /// Test helper: copy with a different kind.
    func with(kind: String) -> OutboxEntry {
        var c = self; c = OutboxEntry(id: id, kind: kind, payload: payload, clientRequestId: clientRequestId,
            dependsOn: dependsOn, status: status, attempts: attempts, nextAttemptAt: nextAttemptAt,
            lastError: lastError, createdAt: createdAt, updatedAt: updatedAt, result: result); return c
    }
}
