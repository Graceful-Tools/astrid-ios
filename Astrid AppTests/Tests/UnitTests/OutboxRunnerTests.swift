import XCTest
@testable import Astrid_App

/// Tests for the OutboxRunner drain loop: success, retry/backoff, permanent
/// dead-letter, dependency ordering, missing handler, and persistence.
final class OutboxRunnerTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempURL: URL!

    /// Records the order handlers were invoked in (thread-safe via actor).
    private actor Recorder {
        private(set) var order: [String] = []
        func record(_ id: String) { order.append(id) }
    }

    private actor ConcurrencyProbe {
        private var active = 0
        private(set) var peak = 0
        func enter() { active += 1; peak = max(peak, active) }
        func leave() { active -= 1 }
    }

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-runner-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func entry(
        _ id: String, kind: String = "k", dependsOn: [String] = [], tempId: String? = nil
    ) -> OutboxEntry {
        OutboxEntry(
            id: id, kind: kind, payload: Data(), clientRequestId: "crid-\(id)",
            dependsOn: dependsOn, status: .pending, attempts: 0,
            nextAttemptAt: fixedNow, lastError: nil, createdAt: fixedNow, updatedAt: fixedNow,
            tempId: tempId
        )
    }

    private func makeRunner(_ handlers: [String: OutboxHandler]) -> OutboxRunner {
        OutboxRunner(store: OutboxStore(fileURL: tempURL), handlers: handlers, now: { self.fixedNow })
    }

    func testSuccessMarksCompleted() async {
        let rec = Recorder()
        let runner = makeRunner(["k": { e, _ in await rec.record(e.id); return .success([:]) }])
        await runner.enqueue(entry("a"))

        let snap = await runner.snapshot()
        XCTAssertEqual(snap.first?.status, .completed)
        let order = await rec.order
        XCTAssertEqual(order, ["a"])
    }

    func testPersistEnqueuePersistsWithoutDraining() async {
        // The durability contract behind OutboxManager awaiting the persist
        // before it treats an optimistic write as committed: the entry must be
        // on disk (survives a crash) but the handler must NOT have run yet.
        let rec = Recorder()
        let runner = makeRunner(["k": { e, _ in await rec.record(e.id); return .success([:]) }])
        await runner.persistEnqueue([entry("a")])

        let order = await rec.order
        XCTAssertEqual(order, [], "persistEnqueue must journal only, never drain")

        // A fresh runner over the same store file recovers the entry — proof it
        // was durably persisted before the call returned.
        let reloaded = OutboxRunner(store: OutboxStore(fileURL: tempURL), handlers: [:], now: { self.fixedNow })
        let snap = await reloaded.snapshot()
        XCTAssertEqual(snap.map(\.id), ["a"], "entry must be persisted before the drain runs")
        XCTAssertEqual(snap.first?.status, .pending)
    }

    func testRetryableFailureBacksOffAndStaysPending() async {
        let runner = makeRunner(["k": { _, _ in .retryable("network") }])
        await runner.enqueue(entry("a"))

        let e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .pending)
        XCTAssertEqual(e?.attempts, 1)
        XCTAssertEqual(e?.lastError, "network")
        XCTAssertGreaterThan(e?.nextAttemptAt ?? fixedNow, fixedNow, "must back off into the future")
    }

    func testPermanentFailureDeadLetters() async {
        let runner = makeRunner(["k": { _, _ in .permanent("403") }])
        await runner.enqueue(entry("a"))
        let e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .failedPermanent)
        XCTAssertEqual(e?.lastError, "403")
    }

    func testMissingHandlerDeadLetters() async {
        let runner = makeRunner([:])  // no handler for kind "k"
        await runner.enqueue(entry("a"))
        let status = await runner.snapshot().first?.status
        XCTAssertEqual(status, .failedPermanent)
    }

    func testDependentRunsOnlyAfterDependencyCompletes() async {
        let rec = Recorder()
        let runner = makeRunner(["k": { e, _ in await rec.record(e.id); return .success([:]) }])
        await runner.enqueue(entry("a"))
        await runner.enqueue(entry("b", dependsOn: ["a"]))

        let order = await rec.order
        XCTAssertEqual(order, ["a", "b"], "dependency must run before its dependent")
        let snap = await runner.snapshot()
        XCTAssertTrue(snap.allSatisfy { $0.status == .completed })
    }

    func testDependentBlockedWhenDependencyFailsRetryable() async {
        let rec = Recorder()
        let runner = makeRunner([
            "dep": { e, _ in await rec.record(e.id); return .retryable("boom") },
            "child": { e, _ in await rec.record(e.id); return .success([:]) }
        ])
        await runner.enqueue(entry("a", kind: "dep"))
        await runner.enqueue(entry("b", kind: "child", dependsOn: ["a"]))

        let order = await rec.order
        XCTAssertEqual(order, ["a"], "dependent must NOT run while its dependency is unmet")
        let b = await runner.snapshot().first { $0.id == "b" }
        XCTAssertEqual(b?.status, .pending)
    }

    func testJournalPersistsAcrossRunnerInstances() async {
        let runner = makeRunner(["k": { _, _ in .success([:]) }])
        await runner.enqueue(entry("a"))

        // A fresh store reading the same file should see the completed entry.
        let reloaded = OutboxStore(fileURL: tempURL).load()
        XCTAssertEqual(reloaded.first?.id, "a")
        XCTAssertEqual(reloaded.first?.status, .completed)
    }

    func testDistinctEntityLanesRunConcurrently() async {
        let probe = ConcurrencyProbe()
        let runner = makeRunner(["k": { _, _ in
            await probe.enter()
            try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
            await probe.leave()
            return .success([:])
        }])
        await runner.persistEnqueue([
            entry("a", tempId: "task-a"), entry("b", tempId: "task-b")
        ])
        await runner.drain()
        let peak = await probe.peak
        XCTAssertEqual(peak, 2)
    }

    func testSameEntityLaneRemainsSerial() async {
        let probe = ConcurrencyProbe()
        let runner = makeRunner(["k": { _, _ in
            await probe.enter()
            try? await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
            await probe.leave()
            return .success([:])
        }])
        await runner.persistEnqueue([
            entry("a", tempId: "same-task"), entry("b", tempId: "same-task")
        ])
        await runner.drain()
        let peak = await probe.peak
        XCTAssertEqual(peak, 1)
    }
}
