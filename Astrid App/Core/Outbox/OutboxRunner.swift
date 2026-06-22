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

    init(
        store: OutboxStore,
        handlers: [String: OutboxHandler] = [:],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.handlers = handlers
        self.now = now
        self.entries = store.load()
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
