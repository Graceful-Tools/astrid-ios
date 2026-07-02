import Foundation

/// Outcome a handler reports for an Outbox entry.
enum OutboxResult: Equatable {
    /// Succeeded, optionally producing output for dependents (e.g. the real
    /// fileId an attachment upload yields). Pass `[:]` when there's no output.
    case success([String: String])
    case retryable(String)   // transient (network/5xx) — back off and retry
    case permanent(String)   // auth/validation/not-found — dead-letter, don't retry
    /// Waiting on LOCAL state (a temp task id not yet resolved, an attachment
    /// still uploading). Unlike `retryable`, this does NOT consume an attempt —
    /// local blocks can outlast the whole backoff window (e.g. a long offline
    /// stretch) and must never dead-letter. Re-checked on every drain and on a
    /// fixed short timer.
    case blocked(String)
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
    /// Single-drain guard.
    private var isDraining = false
    private var redrainRequested = false

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
    // Persisted lifetime counters for the soak readout (the live journal prunes
    // completed entries, so a snapshot alone can't answer "did we drop anything").
    static let lifetimeCompletedKey = "outboxLifetimeCompleted"
    static let lifetimeDeadLetteredKey = "outboxLifetimeDeadLettered"

    nonisolated static func bumpLifetime(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    func stats() -> OutboxStats {
        var s = OutboxStats(entries: entries)
        s.lifetimeCompleted = UserDefaults.standard.integer(forKey: Self.lifetimeCompletedKey)
        s.lifetimeDeadLettered = UserDefaults.standard.integer(forKey: Self.lifetimeDeadLetteredKey)
        return s
    }

    /// Add an entry (idempotent on id) and drain.
    func enqueue(_ entry: OutboxEntry) async {
        await enqueueBatch([entry])
    }

    /// Add several entries atomically — appended and persisted in a single
    /// journal write — so an interruption can't leave a dependency chain
    /// half-enqueued (e.g. the upload saved but its dependent comment lost).
    func enqueueBatch(_ newEntries: [OutboxEntry]) async {
        var added = false
        for entry in newEntries where !entries.contains(where: { $0.id == entry.id }) {
            entries.append(entry)
            added = true
        }
        if added { persist() }
        await drain()
    }

    /// Single-drain guard: serialize drain passes. A concurrent caller (a wake-up
    /// timer firing during an enqueue, etc.) requests a re-drain instead of
    /// running a second loop alongside the first.
    func drain() async {
        if isDraining {
            redrainRequested = true
            return
        }
        isDraining = true
        defer { isDraining = false }
        repeat {
            redrainRequested = false
            await drainOnce()
        } while redrainRequested
        scheduleNextWakeupIfNeeded()
    }

    /// Dispatch every runnable entry, looping while progress is made so newly
    /// completed entries can unblock dependents within the same drain.
    private func drainOnce() async {
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
                    Self.bumpLifetime(Self.lifetimeCompletedKey)
                case .permanent(let message):
                    update(entry.id) { $0.status = .failedPermanent; $0.lastError = message }
                    Self.bumpLifetime(Self.lifetimeDeadLetteredKey)
                case .retryable(let message):
                    var deadLettered = false
                    update(entry.id) { e in
                        e.attempts += 1
                        e.lastError = message
                        if OutboxScheduler.shouldDeadLetter(attempts: e.attempts) {
                            e.status = .failedPermanent
                            deadLettered = true
                        } else {
                            e.status = .pending
                            e.nextAttemptAt = OutboxScheduler.nextAttemptDate(now: now(), attempts: e.attempts)
                        }
                    }
                    if deadLettered { Self.bumpLifetime(Self.lifetimeDeadLetteredKey) }
                case .blocked(let message):
                    // Waiting on local state — no attempt consumed, can never
                    // dead-letter. Re-check in 60s (plus on every event-driven drain).
                    update(entry.id) { e in
                        e.lastError = message
                        e.status = .pending
                        e.nextAttemptAt = now().addingTimeInterval(60)
                    }
                }
                progressed = true
            }

            persist()
            if !progressed { break }
        }

        // Dead-letter entries stranded by a permanently-failed/missing dependency
        // so they don't hang pending forever.
        let stranded = OutboxScheduler.strandedEntryIds(entries)
        if !stranded.isEmpty {
            for id in stranded {
                update(id) { entry in
                    entry.status = .failedPermanent
                    if entry.lastError == nil { entry.lastError = "dependency permanently failed or missing" }
                }
                Self.bumpLifetime(Self.lifetimeDeadLetteredKey)
            }
            persist()
        }

        // Prune old, unreferenced completed entries so the journal stays bounded.
        let before = entries.count
        entries = OutboxScheduler.pruned(entries, now: now())
        if entries.count != before { persist() }
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
