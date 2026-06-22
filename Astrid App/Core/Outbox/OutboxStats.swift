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

    var total: Int { pending + running + completed + failedPermanent }

    /// No dead-lettered (dropped) entries. Pending/running are transient and
    /// fine; a permanent failure is the thing that would block deprecation.
    var isHealthy: Bool { failedPermanent == 0 }

    init(pending: Int = 0, running: Int = 0, completed: Int = 0, failedPermanent: Int = 0) {
        self.pending = pending
        self.running = running
        self.completed = completed
        self.failedPermanent = failedPermanent
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
    }
}
