//  ListDeletedOnWebTests.swift
//  Regression guard for Task 53071260 — "List deleted on web didn't get deleted on iOS".
//
//  `ListService.fetchLists` cached a response by upserting every list it returned and removing
//  nothing. A list deleted on web vanished from the in-memory array, so it looked fixed — but
//  its Core Data row survived, and `loadCachedLists` reads every row on launch with no
//  predicate. Relaunching brought the list back.
//
//  The delete half of caching is the dangerous half: a list created offline is absent from every
//  server response by definition, and pruning it would destroy work that was never synced. These
//  pin both directions — what must go, and what must survive.

import XCTest
@testable import Astrid_App

final class ListDeletedOnWebTests: XCTestCase {

    private func cached(_ id: String, _ status: String?) -> SyncOrphanPrune.Cached {
        SyncOrphanPrune.Cached(id: id, syncStatus: status)
    }

    // MARK: - What must go

    /// The bug: a synced list the server has stopped returning was deleted elsewhere.
    func testAListDeletedOnWebIsDroppedFromTheCache() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("keep", "synced"), cached("deleted-on-web", "synced")],
            serverIds: ["keep"])
        XCTAssertEqual(orphans, ["deleted-on-web"])
    }

    /// A queued delete whose list is already gone server-side has nothing left to do.
    func testAPendingDeleteThatTheServerHasAlreadyHonouredIsCleanedUp() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("going", "pending_delete")], serverIds: [])
        XCTAssertEqual(orphans, ["going"])
    }

    /// An empty response means every synced list is gone — the account was emptied elsewhere.
    func testAnEmptyResponsePrunesEverySyncedList() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("a", "synced"), cached("b", "synced")], serverIds: [])
        XCTAssertEqual(orphans, ["a", "b"])
    }

    // MARK: - What must survive (deleting these is data loss)

    /// A list created offline has never been sent, so no response can contain it.
    func testAListCreatedOfflineSurvivesAFetchThatCannotKnowAboutIt() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("local-only", "pending")], serverIds: ["something-else"])
        XCTAssertEqual(orphans, [], "A pending create is not a deletion")
    }

    /// Optimistic ids are exchanged for a server id only once the create lands.
    func testATempIdSurvivesEvenIfItsStatusLooksSynced() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("temp_abc123", "synced")], serverIds: [])
        XCTAssertEqual(orphans, [], "temp_ ids predate the server knowing anything")
    }

    /// An unrecognised state is not evidence of deletion; leave it alone.
    func testAnUnknownSyncStatusIsNeverPruned() {
        for status in [nil, "", "pending_list_sync", "conflicted"] {
            XCTAssertEqual(SyncOrphanPrune.orphanIds(cached: [cached("x", status)], serverIds: []),
                           [], "syncStatus \(status ?? "nil") must be left alone")
        }
    }

    /// Present in the response is present, whatever local state says.
    func testAnythingTheServerStillReturnsIsKept() {
        let orphans = SyncOrphanPrune.orphanIds(
            cached: [cached("a", "synced"), cached("b", "pending_delete")],
            serverIds: ["a", "b"])
        XCTAssertEqual(orphans, [])
    }

    // MARK: - The caller

    /// The rule has to be applied where the fetch caches, or it is just a well-tested no-op.
    func testFetchListsAppliesThePruner() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Core/Services/ListService.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("SyncOrphanPrune"),
                      "fetchLists must remove the lists the server stopped returning")
    }

    /// Task c6615a5d-7c1a-41e7-b5c0-825cea0eddb0: a fetch started before a local delete
    /// must not write its stale copy of the deleted list back to Core Data.
    func testRecentlyDeletedListIsExcludedFromThePersistedFetchSnapshot() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Core/Services/ListService.swift"),
            encoding: .utf8)

        XCTAssertTrue(source.contains("let serverIds = Set(liveLists.map"),
                      "pruning must treat recently deleted lists as absent")
        XCTAssertTrue(source.contains("for list in liveLists"),
                      "the cache write must use the deletion-filtered snapshot")
        XCTAssertFalse(source.contains("for list in fetchedLists"),
                       "a stale response must not persist a locally deleted list")
    }
}
