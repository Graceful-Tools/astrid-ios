import Foundation

/// The `CDTaskList.syncStatus` values, and the one rule that was wrong about them (AITD-410).
///
/// `syncPendingLists` selected rows with `syncStatus == "pending"` but wrote `"failed"` when an
/// attempt threw — so the row dropped out of its own retry predicate and was never tried again.
/// One transient failure stranded an offline-created list permanently, and because
/// `updatePendingListsCount` used the same predicate, `pendingListsCount` fell to zero and the
/// 60-second retry timer stopped firing too.
///
/// `ListMemberService` already had the missing half — a sweep that rehabilitates `"failed"` back
/// to `"pending"` — which is what makes this a plain bug rather than a design choice. Rather than
/// copy that second sweep, the selection itself is widened: `"failed"` stays a distinct status
/// (it records that an attempt was made and lost) but it is still *unsynced*, so it is still
/// retried.
enum ListSyncStatus {
    static let synced = "synced"
    static let pending = "pending"
    static let failed = "failed"

    /// Statuses a retry sweep must keep selecting. `"failed"` belongs here: it means "tried and
    /// did not land", which is a reason to try again, not a reason to stop.
    static let unsynced: [String] = [pending, failed]

    static func isUnsynced(_ status: String) -> Bool {
        unsynced.contains(status)
    }
}
