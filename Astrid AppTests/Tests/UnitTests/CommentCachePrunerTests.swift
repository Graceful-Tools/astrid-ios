//  CommentCachePrunerTests.swift
//  The cached comment list has to SHRINK when the server's does.
//
//  THE BUG (found from Jon's launch log, 2026-09-07): "Comments loaded: 284340 comments for 27
//  tasks in 4451ms" — a 4.5-second startup stall and a 221 MB local store, against a server that
//  held far fewer. `saveCommentsToCoreData` upserts and never deletes, so every comment the client
//  ever saw stayed cached forever. Deleting a comment on the server, or cleaning up a runaway
//  GitHub-sync mirror loop, left the client hydrating rows that no longer exist — and the gap only
//  ever widens.
//
//  The rule is pure and separate from the service for the usual reason: the dangerous half is what
//  it must NOT delete. A prune that takes an offline-created comment with it destroys a write the
//  Outbox has not delivered yet (ASTRID.md rule 6), and that is not a failure any log would show.

import XCTest
@testable import Astrid_App

final class CommentCachePrunerTests: XCTestCase {

    private func row(_ id: String, _ status: String) -> CommentCachePruner.CachedRow {
        CommentCachePruner.CachedRow(id: id, syncStatus: status)
    }

    // MARK: - It prunes

    /// The whole point: a synced row the server no longer lists is gone, and must go locally too.
    func testPrunesSyncedRowsTheServerNoLongerHas() {
        let prune = CommentCachePruner.idsToPrune(
            serverIds: ["a", "b"],
            cached: [row("a", "synced"), row("b", "synced"), row("c", "synced")])

        XCTAssertEqual(prune, ["c"], "A synced comment absent from the server's list is stale cache")
    }

    /// Nothing to do when the cache already matches — the common case must not churn Core Data.
    func testPrunesNothingWhenTheCacheMatchesTheServer() {
        XCTAssertTrue(CommentCachePruner.idsToPrune(
            serverIds: ["a", "b"],
            cached: [row("a", "synced"), row("b", "synced")]).isEmpty)
    }

    /// The runaway case this was written for: tens of thousands of cached rows against a handful
    /// on the server. Everything stale goes in one pass.
    func testPrunesAWholeRunawayBacklog() {
        let cached = (0..<5_000).map { row("junk-\($0)", "synced") } + [row("real", "synced")]

        let prune = CommentCachePruner.idsToPrune(serverIds: ["real"], cached: cached)

        XCTAssertEqual(prune.count, 5_000)
        XCTAssertFalse(prune.contains("real"))
    }

    // MARK: - What it must never take with it

    /// THE DANGEROUS ONE. A pending comment was created offline and has never been sent, so it is
    /// absent from the server's list BY DEFINITION. Pruning on absence alone would delete the
    /// user's unsent write — silently, and with no way to get it back.
    func testNeverPrunesPendingCommentsTheServerHasNotSeenYet() {
        let prune = CommentCachePruner.idsToPrune(
            serverIds: ["a"],
            cached: [row("a", "synced"), row("offline-write", "pending")])

        XCTAssertTrue(prune.isEmpty, "A pending comment is absent from the server because it has not been sent")
    }

    /// A failed write is still a write the user made — it retries, so it must survive too.
    func testNeverPrunesFailedComments() {
        XCTAssertTrue(CommentCachePruner.idsToPrune(
            serverIds: [], cached: [row("retry-me", "failed")]).isEmpty)
    }

    /// Optimistic rows still carrying their temp id are pending by construction, whatever their
    /// status column happens to say mid-reconcile.
    func testNeverPrunesTempIdRows() {
        XCTAssertTrue(CommentCachePruner.idsToPrune(
            serverIds: ["a"], cached: [row("temp_ABC", "synced")]).isEmpty)
    }

    /// An EMPTY server list is the one that could wipe a task clean. It is legitimate — every
    /// comment really was deleted — so synced rows go, but the unsent ones still stay.
    func testAnEmptyServerListClearsSyncedRowsButSparesUnsentOnes() {
        let prune = CommentCachePruner.idsToPrune(
            serverIds: [],
            cached: [row("gone", "synced"), row("mine", "pending"), row("temp_X", "synced")])

        XCTAssertEqual(prune, ["gone"])
    }
}
