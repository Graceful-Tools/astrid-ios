import Foundation

/// Outcome a handler reports for an Outbox entry.
enum OutboxResult: Equatable {
    /// Succeeded, optionally producing output for dependents (e.g. the real
    /// fileId an attachment upload yields). Pass `[:]` when there's no output.
    case success([String: String])
    case retryable(String)   // transient (network/5xx) — back off and retry
    case permanent(String)   // auth/validation/not-found — dead-letter, don't retry
}

/// Resolved outputs of an entry's dependencies, handed to its handler so it can
/// fill in values produced upstream (e.g. read the uploaded fileId).
struct OutboxContext {
    /// dependency entry id → that entry's `result` output.
    let dependencyOutputs: [String: [String: String]]

    /// First value for `key` across all dependencies (dependencies of one entry
    /// don't produce colliding keys in practice).
    func value(_ key: String) -> String? {
        for (_, output) in dependencyOutputs {
            if let value = output[key] { return value }
        }
        return nil
    }
}

/// Performs one Outbox operation. Self-contained: everything it needs is in the
/// entry's payload plus its dependencies' outputs. `@Sendable` so it can run off
/// the actor.
typealias OutboxHandler = @Sendable (OutboxEntry, OutboxContext) async -> OutboxResult

/// Schedules `action` to run at approximately `at`. Injectable so tests can fire
/// wake-ups deterministically; production uses a `Task.sleep` timer.
typealias OutboxWakeupScheduler = @Sendable (_ at: Date, _ action: @escaping @Sendable () async -> Void) -> Void

/// The single drain loop for all offline-first writes. Replaces the per-service
/// sync runners: one in-flight guard, one backoff curve, one dependency graph,
/// one dead-letter path.
///
/// An `actor` so the journal is mutated serially without locks. Handlers are
/// registered per `kind`; services enqueue self-contained entries and read
/// optimistic state from their own caches. Drain runs runnable entries oldest
/// first, then loops so a completion can unblock its dependents in the same pass
/// (this is what makes "comment waits for its attachment" correct by
/// construction rather than by observer wiring).
actor OutboxRunner {

    private var entries: [OutboxEntry]
    private let store: OutboxStore
    private var handlers: [String: OutboxHandler]
    private var inFlight: Set<String> = []
    private let now: @Sendable () -> Date
    private let scheduleWakeup: OutboxWakeupScheduler
    /// The time we've already scheduled a wake-up for, so we don't pile up timers.
    private var pendingWakeupAt: Date?

    init(
        store: OutboxStore,
        handlers: [String: OutboxHandler] = [:],
        now: @escaping @Sendable () -> Date = { Date() },
        scheduleWakeup: @escaping OutboxWakeupScheduler = OutboxRunner.defaultWakeupScheduler
    ) {
        self.store = store
        self.handlers = handlers
        self.now = now
        self.scheduleWakeup = scheduleWakeup
        self.entries = store.load()
    }

    /// Production wake-up: a one-shot `Task.sleep` timer.
    static let defaultWakeupScheduler: OutboxWakeupScheduler = { at, action in
        let delay = max(0, at.timeIntervalSinceNow)
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await action()
        }
    }

    func register(kind: String, handler: @escaping OutboxHandler) {
        handlers[kind] = handler
    }

    /// Current journal — for inspection/tests.
    func snapshot() -> [OutboxEntry] { entries }

    /// Journal counts by status — powers the dual-write soak readout.
    func stats() -> OutboxStats { OutboxStats(entries: entries) }

    /// Add an entry (idempotent on id) and drain.
    func enqueue(_ entry: OutboxEntry) async {
        if !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
            persist()
        }
        await drain()
    }

    /// Dispatch every runnable entry, looping while progress is made so newly
    /// completed entries can unblock dependents within the same drain.
    func drain() async {
        while true {
            let runnable = OutboxScheduler.runnableEntries(entries, now: now(), inFlightIds: inFlight)
            guard !runnable.isEmpty else { break }

            var progressed = false
            for entry in runnable {
                guard entries.contains(where: { $0.id == entry.id }) else { continue }

                guard let handler = handlers[entry.kind] else {
                    update(entry.id) { $0.status = .failedPermanent; $0.lastError = "no handler for kind \(entry.kind)" }
                    progressed = true
                    continue
                }

                // Hand the handler its dependencies' produced outputs.
                let dependencyOutputs = Dictionary(uniqueKeysWithValues:
                    entry.dependsOn.compactMap { depId -> (String, [String: String])? in
                        guard let dep = entries.first(where: { $0.id == depId }) else { return nil }
                        return (depId, dep.result ?? [:])
                    }
                )
                let context = OutboxContext(dependencyOutputs: dependencyOutputs)

                update(entry.id) { $0.status = .running }
                inFlight.insert(entry.id)
                let result = await handler(entry, context)
                inFlight.remove(entry.id)

                switch result {
                case .success(let output):
                    update(entry.id) {
                        $0.status = .completed
                        $0.lastError = nil
                        $0.result = output.isEmpty ? nil : output
                    }
                case .permanent(let message):
                    update(entry.id) { $0.status = .failedPermanent; $0.lastError = message }
                case .retryable(let message):
                    update(entry.id) { e in
                        e.attempts += 1
                        e.lastError = message
                        if OutboxScheduler.shouldDeadLetter(attempts: e.attempts) {
                            e.status = .failedPermanent
                        } else {
                            e.status = .pending
                            e.nextAttemptAt = OutboxScheduler.nextAttemptDate(now: now(), attempts: e.attempts)
                        }
                    }
                }
                progressed = true
            }

            persist()
            if !progressed { break }
        }

        // Nothing more is runnable now — if entries are waiting on backoff, wake
        // ourselves to retry them instead of stalling until the next event.
        scheduleNextWakeupIfNeeded()
    }

    /// Schedules a single timer for the earliest future retry. Coalesces: won't
    /// stack a later/duplicate wake-up on top of one already pending.
    private func scheduleNextWakeupIfNeeded() {
        guard let at = OutboxScheduler.nextWakeupDate(entries, now: now(), inFlightIds: inFlight) else { return }
        if let already = pendingWakeupAt, already <= at { return }
        pendingWakeupAt = at
        scheduleWakeup(at) { [self] in await self.handleWakeup() }
    }

    private func handleWakeup() async {
        pendingWakeupAt = nil
        await drain()
    }

    // MARK: - Journal mutation

    private func update(_ id: String, _ mutate: (inout OutboxEntry) -> Void) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[idx]
        mutate(&entry)
        entry.updatedAt = now()
        entries[idx] = entry
    }

    private func persist() {
        try? store.save(entries)
    }
}
