import XCTest
@testable import Astrid_App

/// Blocker #1: a retryable failure sets a future nextAttemptAt, but nothing wakes
/// the runner to retry — it stalls until the next enqueue / network event /
/// relaunch. The runner must schedule a wake-up at the earliest future retry.
final class OutboxRetryWakeupTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var tempURL: URL!

    /// Thread-safe, advanceable clock for deterministic timing.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock(); private var t: Date
        init(_ t: Date) { self.t = t }
        var now: Date { lock.lock(); defer { lock.unlock() }; return t }
        func set(_ d: Date) { lock.lock(); t = d; lock.unlock() }
    }

    /// Records scheduled wake-ups so the test can fire them deterministically.
    private final class WakeupSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var dates: [Date] = []
        private var actions: [@Sendable () async -> Void] = []
        func record(_ d: Date, _ a: @escaping @Sendable () async -> Void) {
            lock.lock(); dates.append(d); actions.append(a); lock.unlock()
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return dates.count }
        func date(_ i: Int) -> Date { lock.lock(); defer { lock.unlock() }; return dates[i] }
        func fire(_ i: Int) async { lock.lock(); let a = actions[i]; lock.unlock(); await a() }
    }

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-wakeup-\(UUID().uuidString).json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tempURL) }

    private func entry(_ id: String, kind: String = "k", dependsOn: [String] = []) -> OutboxEntry {
        OutboxEntry(id: id, kind: kind, payload: Data(), clientRequestId: "c-\(id)",
                    dependsOn: dependsOn, status: .pending, attempts: 0,
                    nextAttemptAt: t0, lastError: nil, createdAt: t0, updatedAt: t0)
    }

    // MARK: - Pure: nextWakeupDate

    func testNextWakeupIsEarliestFutureDueEntry() {
        let a = OutboxEntry(id: "a", kind: "k", payload: Data(), clientRequestId: "a", dependsOn: [],
                            status: .pending, attempts: 1, nextAttemptAt: t0.addingTimeInterval(60),
                            lastError: nil, createdAt: t0, updatedAt: t0)
        let b = OutboxEntry(id: "b", kind: "k", payload: Data(), clientRequestId: "b", dependsOn: [],
                            status: .pending, attempts: 1, nextAttemptAt: t0.addingTimeInterval(20),
                            lastError: nil, createdAt: t0, updatedAt: t0)
        XCTAssertEqual(OutboxScheduler.nextWakeupDate([a, b], now: t0, inFlightIds: []),
                       t0.addingTimeInterval(20))
    }

    func testNoWakeupWhenSomethingIsAlreadyRunnable() {
        // a is due now → drain handles it; no timer needed.
        XCTAssertNil(OutboxScheduler.nextWakeupDate([entry("a")], now: t0, inFlightIds: []))
    }

    func testNoWakeupForDependencyBlockedEntry() {
        // c is future-due but its dep isn't complete → it'll be triggered by the
        // dependency's completion, not a timer.
        let c = OutboxEntry(id: "c", kind: "k", payload: Data(), clientRequestId: "c", dependsOn: ["missing"],
                            status: .pending, attempts: 1, nextAttemptAt: t0.addingTimeInterval(30),
                            lastError: nil, createdAt: t0, updatedAt: t0)
        XCTAssertNil(OutboxScheduler.nextWakeupDate([c], now: t0, inFlightIds: []))
    }

    // MARK: - Runner integration

    func testRetryableFailureSchedulesWakeupAndSucceedsOnRetry() async {
        let clock = TestClock(t0)
        let spy = WakeupSpy()
        let attempts = OutboxRunnerTestsAttemptCounter()

        let runner = OutboxRunner(
            store: OutboxStore(fileURL: tempURL),
            handlers: ["k": { _, _ in
                let n = await attempts.next()
                return n == 1 ? .retryable("transient") : .success([:])
            }],
            now: { clock.now },
            scheduleWakeup: { at, action in spy.record(at, action) }
        )

        await runner.enqueue(entry("a"))

        // First attempt failed → pending with a future retry, and a wake-up scheduled.
        var e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .pending)
        XCTAssertEqual(e?.attempts, 1)
        XCTAssertEqual(spy.count, 1, "a retry must be scheduled")
        XCTAssertEqual(spy.date(0), e?.nextAttemptAt)

        // Advance past the retry time and fire the scheduled wake-up.
        clock.set(e!.nextAttemptAt.addingTimeInterval(1))
        await spy.fire(0)

        e = await runner.snapshot().first
        XCTAssertEqual(e?.status, .completed, "the scheduled retry must run and succeed")
    }
}

/// Small actor to count handler invocations across concurrency domains.
actor OutboxRunnerTestsAttemptCounter {
    private var n = 0
    func next() -> Int { n += 1; return n }
}
