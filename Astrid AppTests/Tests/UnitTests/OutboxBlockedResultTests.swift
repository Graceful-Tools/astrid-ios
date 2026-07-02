import XCTest
@testable import Astrid_App

/// `.blocked` = waiting on LOCAL state (temp task id unresolved, attachment still
/// uploading). Unlike `.retryable`, it must NOT consume attempts — a local block
/// can outlast the whole backoff window (a long offline stretch), and burning
/// attempts there dead-letters a perfectly good write. This was a real dropped
/// sync caught in the production soak.
final class OutboxBlockedResultTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var url: URL!

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock(); private var t: Date
        init(_ t: Date) { self.t = t }
        var now: Date { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
    }

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-blocked-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: url) }

    private func entry(_ id: String) -> OutboxEntry {
        OutboxEntry(id: id, kind: "k", payload: Data(), clientRequestId: "c-\(id)",
                    dependsOn: [], status: .pending, attempts: 0, nextAttemptAt: t0,
                    lastError: nil, createdAt: t0, updatedAt: t0)
    }

    func testBlockedNeverConsumesAttemptsOrDeadLetters() async {
        let clock = TestClock(t0)
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: ["k": { _, _ in .blocked("waiting on local state") }],
            now: { clock.now },
            scheduleWakeup: { _, _ in }   // drains driven manually below
        )
        await runner.enqueue(entry("a"))

        // Far more drains than maxAttempts — a retryable would dead-letter well
        // before this; blocked must survive them all with attempts untouched.
        for _ in 0..<(OutboxScheduler.maxAttempts * 3) {
            clock.advance(61)   // past the fixed re-check delay
            await runner.drain()
        }

        let e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .pending, "blocked entries stay pending forever")
        XCTAssertEqual(e?.attempts, 0, "blocked must not consume attempts")
        XCTAssertEqual(e?.lastError, "waiting on local state")
    }

    func testBlockedSucceedsOnceUnblocked() async {
        let clock = TestClock(t0)
        let gate = OutboxRunnerTestsAttemptCounter()
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: url),
            handlers: ["k": { _, _ in
                // Blocked for the first 5 drains, then the local state resolves.
                let n = await gate.next()
                return n <= 5 ? .blocked("still waiting") : .success([:])
            }],
            now: { clock.now },
            scheduleWakeup: { _, _ in }
        )
        await runner.enqueue(entry("a"))
        for _ in 0..<6 {
            clock.advance(61)
            await runner.drain()
        }
        let e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .completed, "unblocked entry completes normally")
        XCTAssertEqual(e?.attempts, 0)
    }
}
