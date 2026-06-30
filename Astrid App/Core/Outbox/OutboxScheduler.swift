import Foundation

/// Pure scheduling policy for the Outbox: backoff, permanent-failure
/// classification, dependency gating, and run ordering. No I/O, no state — the
/// `OutboxRunner` holds the journal and applies these decisions. Kept pure so
/// the highest-risk logic (a bug breaks every offline write) is fully testable.
enum OutboxScheduler {

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
}
