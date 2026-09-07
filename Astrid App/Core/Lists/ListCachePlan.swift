import Foundation

/// What a freshly-fetched list collection means for the local caches (AITD-324).
///
/// `ListService.cacheListsLocally` is the only thing that writes the list cache, and both fetch
/// paths — `fetchLists()` and `SyncManager.performFullSync` — go through it. Its decisions live
/// here, apart from the CoreData writes, because `ListService` is a `@MainActor` singleton whose
/// caching path reaches the app's real persistent store: a test that exercised it directly would
/// be writing to (and pruning) the store the running app uses. Pure functions are the only layer
/// where these rules can be pinned safely.
enum ListCachePlan {

    /// Rows to hold in memory. A list deleted locally is dropped even when the response still
    /// carries it: a fetch that started before the delete is stale by the time it lands
    /// (task c6615a5d).
    static func inMemory(merged: [TaskList], deletedIds: Set<String>) -> [TaskList] {
        guard !deletedIds.isEmpty else { return merged }
        return merged.filter { !deletedIds.contains($0.id) }
    }

    /// Rows to write to CoreData — the server's own response, under the same deletion rule.
    static func persistable(serverLists: [TaskList], deletedIds: Set<String>) -> [TaskList] {
        guard !deletedIds.isEmpty else { return serverLists }
        return serverLists.filter { !deletedIds.contains($0.id) }
    }

    /// Cached ids the response says are gone. `GET /api/v1/lists` returns the whole collection,
    /// so absence really does mean deleted elsewhere — except for a list created offline, which
    /// no response can contain because it has never been sent.
    static func stale(cachedIds: some Sequence<String>, serverIds: Set<String>) -> [String] {
        cachedIds.filter { !serverIds.contains($0) && !$0.hasPrefix(SyncOrphanPrune.localIdPrefix) }
    }

    /// The array the sidebar shows: the server's collection in `ListOrdering`'s order, with any
    /// not-yet-synced local list kept on top so a list you just made does not sort itself out of
    /// sight while it waits for an id.
    ///
    /// AITD-326: `SyncManager.performFullSync` used to build this itself, with a second copy of
    /// the comparator `ListOrdering` exists to be the only one of (task 63e75630) — and with no
    /// deletion filter, so a sync could put a locally-deleted list back on screen. Pass
    /// `serverLists` through `persistable(serverLists:deletedIds:)` first; both fetch paths reach
    /// this through `ListService.applyFetchedLists`.
    static func merged(serverLists: [TaskList], pendingLists: [TaskList]) -> [TaskList] {
        var result = serverLists.sorted(by: ListOrdering.isOrderedBefore)
        for pending in pendingLists where !result.contains(where: { $0.id == pending.id }) {
            result.insert(pending, at: 0)
        }
        return result
    }
}
