import XCTest
@testable import Astrid_App

/// Blocker #3: a dependency chain (upload → comment) must be enqueued atomically
/// — persisted in one journal write — so an interruption can't leave the upload
/// queued but the comment lost.
final class OutboxAtomicBatchTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-batch-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: url) }

    private func entry(_ id: String, dependsOn: [String] = []) -> OutboxEntry {
        OutboxEntry(id: id, kind: "k", payload: Data(), clientRequestId: "c-\(id)",
                    dependsOn: dependsOn, status: .pending, attempts: 0, nextAttemptAt: t0,
                    lastError: nil, createdAt: t0, updatedAt: t0)
    }

    func testBatchPersistsWholeChainTogether() async {
        // Handler holds the entries pending so they remain in the journal.
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: ["k": { _, _ in .retryable("hold") }],
            now: { self.t0 }
        )
        await runner.enqueueBatch([entry("upload"), entry("comment", dependsOn: ["upload"])])

        // A fresh store (simulating a relaunch immediately after enqueue) must see
        // BOTH entries — the chain was persisted as a unit.
        let reloaded = OutboxStore(fileURL: url).load()
        XCTAssertEqual(Set(reloaded.map { $0.id }), ["upload", "comment"])
    }

    func testBatchIsIdempotentOnIds() async {
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: ["k": { _, _ in .retryable("hold") }],
            now: { self.t0 }
        )
        await runner.enqueueBatch([entry("a")])
        await runner.enqueueBatch([entry("a"), entry("b")])  // "a" already present
        let ids = await runner.snapshot().map { $0.id }.sorted()
        XCTAssertEqual(ids, ["a", "b"], "re-enqueuing an existing id doesn't duplicate it")
    }
}
