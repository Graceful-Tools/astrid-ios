import Foundation

/// Pure scheduling policy for the Outbox: backoff, permanent-failure
/// classification, dependency gating, and run ordering. No I/O, no state — the
/// `OutboxRunner` holds the journal and applies these decisions. Kept pure so
/// the highest-risk logic (a bug breaks every offline write) is fully testable.
nonisolated enum OutboxScheduler {

    /// Give up (dead-letter) after this many failed attempts.
    static let maxAttempts = 8
    /// First retry waits this long; doubles each attempt up to `maxBackoff`.
    static let baseBackoff: TimeInterval = 2
    /// Backoff is clamped here so a long-failing entry still retries periodically.
    static let maxBackoff: TimeInterval = 300

    /// Exponential backoff for the Nth failed attempt (attempts >= 1).
    static func backoffDelay(attempts: Int) -> TimeInterval {
        let exponent = Double(max(0, attempts - 1))
        return min(baseBackoff * pow(2.0, exponent), maxBackoff)
    }

    /// When an entry that has failed `attempts` times may next run.
    static func nextAttemptDate(now: Date, attempts: Int) -> Date {
        now.addingTimeInterval(backoffDelay(attempts: attempts))
    }

    /// HTTP statuses that won't succeed on retry — dead-letter immediately.
    /// Mirrors the per-service permanent-error sets (403/404/410) plus auth
    /// (401) and validation (400/422).
    static func isPermanentFailure(httpStatus: Int) -> Bool {
        [400, 401, 403, 404, 410, 422].contains(httpStatus)
    }

    /// True once an entry has burned through all its attempts.
    static func shouldDeadLetter(attempts: Int) -> Bool {
        attempts >= maxAttempts
    }

    /// All of an entry's dependencies have completed.
    static func dependenciesSatisfied(_ entry: OutboxEntry, completedIds: Set<String>) -> Bool {
        entry.dependsOn.allSatisfy { completedIds.contains($0) }
    }

    /// Whether a single entry may run right now.
    static func isRunnable(
        _ entry: OutboxEntry,
        now: Date,
        completedIds: Set<String>,
        inFlightIds: Set<String>
    ) -> Bool {
        entry.status == .pending
            && now >= entry.nextAttemptAt
            && !inFlightIds.contains(entry.id)
            && dependenciesSatisfied(entry, completedIds: completedIds)
    }

    /// How long a completed entry is retained before pruning (for inspection /
    /// late-arriving dependents). Referenced completed entries are always kept.
    static let completedRetention: TimeInterval = 3600

    /// Drops completed entries that are old AND no longer referenced by a pending
    /// or running entry's dependencies, so the journal doesn't grow without bound.
    /// Everything else (pending/running/failedPermanent, recent or still-needed
    /// completed) is kept.
    static func pruned(_ entries: [OutboxEntry], now: Date) -> [OutboxEntry] {
        let referencedDeps = Set(
            entries
                .filter { $0.status == .pending || $0.status == .running }
                .flatMap { $0.dependsOn }
        )
        return entries.filter { entry in
            guard entry.status == .completed else { return true }
            if referencedDeps.contains(entry.id) { return true }
            return entry.updatedAt > now.addingTimeInterval(-completedRetention)
        }
    }

    /// Ids of pending entries that can never run — a dependency has permanently
    /// failed or doesn't exist (and isn't completed) — so they must be
    /// dead-lettered instead of hanging pending forever. Propagates transitively:
    /// a dependent of a stranded entry is itself stranded.
    static func strandedEntryIds(_ entries: [OutboxEntry]) -> Set<String> {
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let completedIds = Set(entries.filter { $0.status == .completed }.map { $0.id })
        var stranded: Set<String> = []
        var changed = true
        while changed {
            changed = false
            for entry in entries where entry.status == .pending && !stranded.contains(entry.id) {
                for dep in entry.dependsOn {
                    let depEntry = byId[dep]
                    let depFailed = depEntry?.status == .failedPermanent || stranded.contains(dep)
                    let depMissing = depEntry == nil && !completedIds.contains(dep)
                    if depFailed || depMissing {
                        stranded.insert(entry.id)
                        changed = true
                        break
                    }
                }
            }
        }
        return stranded
    }

    /// Ids of pending TASK temp-id consumers (updateTask/deleteTask on a
    /// not-yet-synced task) whose producing createTask entry has permanently
    /// failed — they can never resolve their temp id, so they'd sit `.blocked`
    /// forever (the strandedEntryIds check only sees explicit dependsOn edges,
    /// which these don't have). Dead-letter them instead.
    static func tempStrandedEntryIds(_ entries: [OutboxEntry]) -> Set<String> {
        let failedCreateTempIds = Set(
            entries
                .filter { $0.kind == "createTask" && $0.status == .failedPermanent }
                .compactMap { $0.tempId }
        )
        guard !failedCreateTempIds.isEmpty else { return [] }
        return Set(
            entries
                .filter { entry in
                    entry.status == .pending
                        && entry.kind != "createTask"
                        && (entry.tempId.map { failedCreateTempIds.contains($0) } ?? false)
                }
                .map { $0.id }
        )
    }

    /// Normalizes journal entries loaded from disk. An entry persisted as
    /// `.running` was in flight when the app was killed (a concurrent
    /// enqueue can persist the journal mid-handler); on relaunch it's neither
    /// runnable nor pruned nor stranded, so it wedges forever. Reset it to
    /// `.pending` so it retries — replay is safe because every kind is
    /// server-idempotent by clientRequestId.
    static func recoveredOnLoad(_ entries: [OutboxEntry]) -> [OutboxEntry] {
        entries.map { entry in
            guard entry.status == .running else { return entry }
            var e = entry
            e.status = .pending
            return e
        }
    }

    /// When the runner should next wake itself to retry. Returns the earliest
    /// future `nextAttemptAt` among pending, dependency-satisfied entries — or
    /// nil if something is already runnable (drain handles it now) or nothing is
    /// waiting on the clock (dependency-blocked entries are triggered by their
    /// dependency completing, not a timer).
    static func nextWakeupDate(
        _ entries: [OutboxEntry],
        now: Date,
        inFlightIds: Set<String>
    ) -> Date? {
        let completedIds = Set(entries.filter { $0.status == .completed }.map { $0.id })
        if entries.contains(where: { isRunnable($0, now: now, completedIds: completedIds, inFlightIds: inFlightIds) }) {
            return nil
        }
        return entries
            .filter {
                $0.status == .pending
                    && !inFlightIds.contains($0.id)
                    && dependenciesSatisfied($0, completedIds: completedIds)
                    && $0.nextAttemptAt > now
            }
            .map { $0.nextAttemptAt }
            .min()
    }

    /// The entries that should be dispatched now, oldest first. Completion is
    /// derived from the journal itself so dependency edges resolve against the
    /// current state.
    static func runnableEntries(
        _ entries: [OutboxEntry],
        now: Date,
        inFlightIds: Set<String>
    ) -> [OutboxEntry] {
        let completedIds = Set(entries.filter { $0.status == .completed }.map { $0.id })
        return entries
            .filter { isRunnable($0, now: now, completedIds: completedIds, inFlightIds: inFlightIds) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Selects at most one oldest runnable entry per serialization lane. This
    /// permits bounded concurrency across unrelated entities while preserving
    /// implicit FIFO ordering for repeated writes to the same entity.
    static func concurrentBatch(
        _ runnable: [OutboxEntry],
        limit: Int,
        serializationKey: (OutboxEntry) -> String
    ) -> [OutboxEntry] {
        guard limit > 0 else { return [] }
        var keys: Set<String> = []
        var batch: [OutboxEntry] = []
        for entry in runnable.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = serializationKey(entry)
            guard keys.insert(key).inserted else { continue }
            batch.append(entry)
            if batch.count == limit { break }
        }
        return batch
    }

    /// Stable implicit-ordering lane for production entries. Explicit
    /// dependencies still gate execution separately; this key preserves FIFO
    /// for repeated writes to the same task/comment/channel.
    static func serializationKey(for entry: OutboxEntry) -> String {
        if let tempId = entry.tempId { return "task:\(tempId)" }
        let decoder = JSONDecoder()
        switch entry.kind {
        case "createTask":
            if let payload = try? decoder.decode(CreateTaskOutboxPayload.self, from: entry.payload),
               let tempId = payload.tempId { return "task:\(tempId)" }
        case "updateTask":
            if let payload = try? decoder.decode(UpdateTaskOutboxPayload.self, from: entry.payload) {
                return "task:\(payload.taskId)"
            }
        case "deleteTask":
            if let payload = try? decoder.decode(DeleteTaskOutboxPayload.self, from: entry.payload) {
                return "task:\(payload.taskId)"
            }
        case "createComment":
            if let payload = try? decoder.decode(CreateCommentOutboxPayload.self, from: entry.payload) {
                return "task-comments:\(payload.taskId)"
            }
        case "updateComment":
            if let payload = try? decoder.decode(UpdateCommentOutboxPayload.self, from: entry.payload) {
                return "comment:\(payload.commentId)"
            }
        case "deleteComment":
            if let payload = try? decoder.decode(DeleteCommentOutboxPayload.self, from: entry.payload) {
                return "comment:\(payload.commentId)"
            }
        case "sendChatMessage":
            if let payload = try? decoder.decode(SendChatMessageOutboxPayload.self, from: entry.payload) {
                return "channel:\(payload.channelId)"
            }
        case "uploadAttachment":
            if let payload = try? decoder.decode(UploadAttachmentOutboxPayload.self, from: entry.payload) {
                return "upload:\(payload.localPath)"
            }
        default:
            break
        }
        return "entry:\(entry.id)"
    }
}
