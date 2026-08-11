import Foundation

/// Which locally-cached records a FULL server response says are gone (Task 53071260).
///
/// Caching a fetch is two operations, not one: upsert what came back, and remove what did not.
/// `ListService.fetchLists` only ever did the first half, so a list deleted on web kept its
/// Core Data row and came back on the next launch, when `loadCachedLists` reads every row.
///
/// The delete half is the dangerous half, which is why the rule lives here as a pure function
/// instead of as another inline predicate. A record the server has never heard of — one created
/// offline and still queued — is absent from every response by definition. Treating that absence
/// as a deletion would throw away work the user has not synced yet. Absence only means "deleted"
/// for a record the server has already acknowledged.
///
/// `TaskService.saveTasksToCoreData` states the same rule as an NSPredicate for tasks. This is
/// that rule, named and testable; tasks could adopt it rather than restating it.
enum SyncOrphanPrune {

    /// A cached record as the pruner sees it.
    struct Cached: Equatable {
        let id: String
        /// Core Data's `syncStatus`. nil is treated as unknown, and unknown is never pruned.
        let syncStatus: String?

        init(id: String, syncStatus: String?) {
            self.id = id
            self.syncStatus = syncStatus
        }
    }

    /// States in which absence from a full response really does mean "deleted elsewhere".
    ///
    /// `synced` — the server acknowledged it, and now it is not there.
    /// `pending_delete` — we asked for it to go and it is gone; the queued delete has nothing
    /// left to do.
    ///
    /// Everything else is preserved. `pending` above all: that is a local create the server
    /// cannot know about yet.
    static let prunableStatuses: Set<String> = ["synced", "pending_delete"]

    /// Optimistic ids, exchanged for a server id once the create lands. A response that predates
    /// the exchange cannot contain them.
    static let localIdPrefix = "temp_"

    /// The ids to delete locally, given everything cached and the ids the server returned.
    ///
    /// Only ever call this with a response covering the WHOLE collection. Handed a filtered or
    /// paginated one, "not in the response" stops meaning "deleted".
    static func orphanIds(cached: [Cached], serverIds: Set<String>) -> [String] {
        cached.filter { record in
            guard !serverIds.contains(record.id) else { return false }
            guard !record.id.hasPrefix(localIdPrefix) else { return false }
            guard let status = record.syncStatus else { return false }
            return prunableStatuses.contains(status)
        }.map(\.id)
    }
}
