//  ChatMessageCachePruner.swift
//  Which cached chat messages a server page makes stale (task AITD-354).
//
//  `ChatService.saveMessagesToCoreData` upserts and never deletes, so `CDChatMessage` could only
//  grow: every list chat and every agent reply, kept forever, and a message deleted server-side
//  stayed on the client. That is the shape that took the comment store to 284,340 rows / 221 MB
//  on Jon's Mac before `CommentCachePruner` (beed6a7) capped it.
//
//  It is NOT the same rule, and the difference is the whole file.
//
//  `CommentCachePruner` may treat absence as deletion because a task's comment fetch returns the
//  WHOLE list. Chat is paginated — `getChatMessages(channelId:before:limit: 50)`, with `hasMore`
//  and a `before` cursor that `loadOlderMessages` pages backwards with. Copying the comment rule
//  here would delete every cached message older than the newest fifty on every refresh, silently
//  destroying the offline history the cache exists to hold.
//
//  So the rule is bounded by the page's own time window: inside it the page is authoritative,
//  outside it we know nothing and touch nothing.
import Foundation

enum ChatMessageCachePruner {

    /// A cached row's identity and sync state — just enough to decide, so the rule can be
    /// exercised without Core Data.
    struct CachedRow: Equatable {
        let id: String
        let syncStatus: String
        let createdAt: Date?

        init(id: String, syncStatus: String, createdAt: Date?) {
            self.id = id
            self.syncStatus = syncStatus
            self.createdAt = createdAt
        }
    }

    /// What one fetch actually told us.
    struct Page: Equatable {
        /// Ids the server returned for this channel.
        let ids: Set<String>
        /// `createdAt` of the oldest message in the page — the lower bound of what it can speak
        /// for. Nil when the page is empty.
        let oldest: Date?
        /// `createdAt` of the newest message in the page — the UPPER bound. Both bounds are
        /// needed: `loadOlderMessages` pages BACKWARDS, so a page can sit entirely below what is
        /// already cached, and a lower bound alone would let it prune everything above it. A
        /// message newer than the page also arrives legitimately over SSE mid-fetch.
        let newest: Date?
        /// True when this page is the entire channel: the first page (no `before` cursor) with
        /// nothing older behind it. Only then is absence anywhere evidence of deletion.
        let coversWholeChannel: Bool

        init(ids: Set<String>, oldest: Date?, newest: Date?, coversWholeChannel: Bool) {
            self.ids = ids
            self.oldest = oldest
            self.newest = newest
            self.coversWholeChannel = coversWholeChannel
        }
    }

    /// Ids to delete from the cache after `page` was fetched for one channel.
    ///
    /// A row is pruned only when ALL of these hold:
    ///   * it is `synced` — pending or failed has never been accepted by the server, so its
    ///     absence is not evidence of anything (ASTRID.md rule 6: never drop an undelivered write);
    ///   * its id has no `temp_` prefix — an optimistic row mid-reconcile;
    ///   * the server did not return it; and
    ///   * it falls INSIDE the window the page can speak for — between its oldest and newest
    ///     messages inclusive — unless the page is the whole channel.
    ///
    /// A row with no `createdAt` cannot be placed in the window, so it is pruned only when the
    /// page covers the whole channel. Keeping an extra row costs disk; deleting a live one costs
    /// the user their history.
    static func idsToPrune(page: Page, cached: [CachedRow]) -> [String] {
        // An empty page is not evidence that a channel was emptied unless it is the whole
        // channel — a `before` cursor past the beginning legitimately returns nothing.
        guard page.coversWholeChannel || page.oldest != nil else { return [] }

        return cached.filter { row in
            guard row.syncStatus == "synced", !row.id.hasPrefix("temp_") else { return false }
            guard !page.ids.contains(row.id) else { return false }
            if page.coversWholeChannel { return true }
            guard let oldest = page.oldest, let newest = page.newest,
                  let created = row.createdAt else { return false }
            return created >= oldest && created <= newest
        }
        .map(\.id)
    }
}
