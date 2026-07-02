import Foundation

/// A snapshot of the Outbox journal, used for the dual-write soak readout.
///
/// During the soak we want one question answered: did the Outbox drop anything?
/// A drop manifests as a `failedPermanent` (dead-lettered) entry or an entry
/// stuck `pending`/`running` long after it was created. `isHealthy` is the quick
/// "safe to deprecate legacy" signal.
struct OutboxStats: Equatable {
    var pending: Int = 0
    var running: Int = 0
    var completed: Int = 0
    var failedPermanent: Int = 0

    /// Cumulative counts across the app's lifetime (persisted). The live journal
    /// prunes completed entries, so these are what the soak actually watches:
    /// `lifetimeCompleted` should climb and `lifetimeDeadLettered` must stay 0.
    var lifetimeCompleted: Int = 0
    var lifetimeDeadLettered: Int = 0

    /// Details of dead-lettered entries still in the journal (failedPermanent is
    /// never pruned), newest first — "kind: lastError". This is the debugging
    /// readout for a non-zero dropped count.
    var deadLetterDetails: [String] = []

    var total: Int { pending + running + completed + failedPermanent }

    /// No dead-lettered (dropped) entries, ever. Pending/running are transient
    /// and fine; a permanent failure is the thing that would block deprecation.
    var isHealthy: Bool { failedPermanent == 0 && lifetimeDeadLettered == 0 }

    init(pending: Int = 0, running: Int = 0, completed: Int = 0, failedPermanent: Int = 0,
         lifetimeCompleted: Int = 0, lifetimeDeadLettered: Int = 0) {
        self.pending = pending
        self.running = running
        self.completed = completed
        self.failedPermanent = failedPermanent
        self.lifetimeCompleted = lifetimeCompleted
        self.lifetimeDeadLettered = lifetimeDeadLettered
    }

    init(entries: [OutboxEntry]) {
        for entry in entries {
            switch entry.status {
            case .pending: pending += 1
            case .running: running += 1
            case .completed: completed += 1
            case .failedPermanent: failedPermanent += 1
            }
        }
        deadLetterDetails = entries
            .filter { $0.status == .failedPermanent }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { "\($0.kind): \($0.lastError ?? "unknown error")" }
    }
}
