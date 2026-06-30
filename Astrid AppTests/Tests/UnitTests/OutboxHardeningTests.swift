import XCTest
@testable import Astrid_App

/// Blocker #7: journal hardening — pruning, corruption-safe load, and
/// concurrent-drain safety. (File protection is set on write; not unit-tested.)
final class OutboxHardeningTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-harden-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tempDir) }

    private func entry(_ id: String, status: OutboxStatus = .pending,
                       dependsOn: [String] = [], updatedOffset: TimeInterval = 0) -> OutboxEntry {
        OutboxEntry(id: id, kind: "k", payload: Data(), clientRequestId: "c-\(id)",
                    dependsOn: dependsOn, status: status, attempts: 0, nextAttemptAt: t0,
                    lastError: nil, createdAt: t0, updatedAt: t0.addingTimeInterval(updatedOffset))
    }

    // MARK: - Pruning

    func testPrunesOldUnreferencedCompleted() {
        let old = entry("old", status: .completed, updatedOffset: -7200)   // 2h ago
        let kept = OutboxScheduler.pruned([old], now: t0)
        XCTAssertTrue(kept.isEmpty, "an old, unreferenced completed entry is pruned")
    }

    func testKeepsRecentCompleted() {
        let recent = entry("r", status: .completed, updatedOffset: -10)
        XCTAssertEqual(OutboxScheduler.pruned([recent], now: t0).map { $0.id }, ["r"])
    }

    func testKeepsCompletedStillReferencedByPendingDependent() {
        let dep = entry("dep", status: .completed, updatedOffset: -7200)   // old…
        let child = entry("child", dependsOn: ["dep"])                     // …but still needed
        XCTAssertEqual(Set(OutboxScheduler.pruned([dep, child], now: t0).map { $0.id }), ["dep", "child"])
    }

    func testKeepsPendingAndFailed() {
        let p = entry("p")
        let f = entry("f", status: .failedPermanent, updatedOffset: -99999)
        XCTAssertEqual(Set(OutboxScheduler.pruned([p, f], now: t0).map { $0.id }), ["p", "f"])
    }

    // MARK: - Corruption-safe load

    func testCorruptJournalIsPreservedNotDropped() throws {
        let url = tempDir.appendingPathComponent("outbox.json")
        try Data("{ not valid json".utf8).write(to: url)

        let store = OutboxStore(fileURL: url)
        XCTAssertEqual(store.load(), [], "a corrupt journal loads as empty rather than crashing")

        let backup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path),
                      "the corrupt journal is preserved for recovery, not silently dropped")
    }

    func testMissingFileLoadsEmptyWithoutBackup() {
        let url = tempDir.appendingPathComponent("nope.json")
        XCTAssertEqual(OutboxStore(fileURL: url).load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    // MARK: - Concurrent-drain safety

    func testConcurrentDrainsProcessEachEntryOnce() async {
        let counter = OutboxRunnerTestsAttemptCounter()
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: tempDir.appendingPathComponent("c.json")),
            handlers: ["k": { _, _ in
                _ = await counter.next()
                await _Concurrency.Task.yield()   // suspension point to interleave drains
                return .success([:])
            }],
            now: { self.t0 }
        )
        await runner.enqueue(entry("a"))
        await runner.enqueue(entry("b"))

        // Fire two drains concurrently; the single-drain guard must keep each
        // entry from being processed twice.
        async let d1: Void = runner.drain()
        async let d2: Void = runner.drain()
        _ = await (d1, d2)

        let count = await counter.get()
        XCTAssertEqual(count, 2, "two entries, each processed exactly once")
        let snap = await runner.snapshot()
        XCTAssertTrue(snap.allSatisfy { $0.status == .completed })
    }
}
