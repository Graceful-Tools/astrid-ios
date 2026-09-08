//  CommentCachePruner.swift
//  Which cached comments a server fetch makes stale (AITD-333 follow-up, 2026-09-07).
//
//  `CommentService.saveCommentsToCoreData` upserts a task's comments and never deleted any, so the
//  local cache could only ever grow. Jon's launch log showed where that ends: "Comments loaded:
//  284340 comments for 27 tasks in 4451ms" — a 4.5s startup stall over a 221 MB store, against a
//  server holding a fraction of that. A comment deleted server-side, or a runaway GitHub-mirror
//  loop cleaned up centrally, stayed on the client forever.
//
//  A task's comment list from the server is AUTHORITATIVE — both call sites fetch the whole list
//  for one task — so anything synced and absent from it is stale.
//
//  Pure and separate from the service because the important half of this rule is the exception:
//  a comment written offline is absent from the server's list by definition, and pruning on
//  absence alone would delete a write the Outbox has not delivered (ASTRID.md rule 6). That is a
//  data-loss bug no log would ever show, so it is asserted rather than trusted.

import Foundation

enum CommentCachePruner {

    /// The cached row's identity and sync state — just enough to decide, so the rule can be
    /// exercised without Core Data.
    struct CachedRow: Equatable {
        let id: String
        let syncStatus: String

        init(id: String, syncStatus: String) {
            self.id = id
            self.syncStatus = syncStatus
        }
    }

    /// Ids to delete from the cache after an authoritative fetch of one task's comments.
    ///
    /// Only rows that are BOTH already synced and missing from the server's list. A row that is
    /// pending or failed has never been accepted by the server, and an id still carrying its
    /// `temp_` prefix is an optimistic row mid-reconcile — neither is evidence of a deletion,
    /// so neither is ever pruned.
    static func idsToPrune(serverIds: Set<String>, cached: [CachedRow]) -> [String] {
        cached.filter { row in
            row.syncStatus == "synced"
                && !row.id.hasPrefix("temp_")
                && !serverIds.contains(row.id)
        }
        .map(\.id)
    }
}
