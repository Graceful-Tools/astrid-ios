//  ListCachePlanTests.swift
//  AITD-324 — the rules behind caching a fetched list collection.
//
//  `MacRootView` called `fetchLists()` at launch, right after the full sync had already fetched
//  the same collection. It read as one redundant round trip, but `SyncManager.performFullSync`
//  assigned `listService.lists` and persisted NOTHING: `fetchLists()` was the only thing in the
//  app that wrote lists to CoreData and pruned the ones the server had stopped returning. So the
//  caching moved into `ListService.cacheListsLocally`, which both fetch paths call, and the launch
//  fetch went.
//
//  These pin the decisions that moved. They are pure on purpose: `cacheListsLocally` reaches the
//  app's real persistent store, so a test that called it would be pruning the store the running
//  app uses.

import XCTest
@testable import Astrid_App

final class ListCachePlanTests: XCTestCase {

    private func list(_ id: String) -> TaskList { TaskList(id: id, name: id) }

    // MARK: - What gets held and written

    func testEverythingInTheResponseIsCachedWhenNothingWasDeletedLocally() {
        let fetched = [list("a"), list("b")]

        XCTAssertEqual(ListCachePlan.inMemory(merged: fetched, deletedIds: []).map(\.id), ["a", "b"])
        XCTAssertEqual(ListCachePlan.persistable(serverLists: fetched, deletedIds: []).map(\.id), ["a", "b"])
    }

    /// Task c6615a5d: a fetch that started before a local delete is stale by the time it lands.
    /// The rule has to hold on BOTH halves — `performFullSync` filters neither its response nor
    /// the merged view it builds from it, so the caching layer is what stops the resurrection.
    func testAListDeletedLocallyIsNeitherHeldNorWrittenBackByAStaleResponse() {
        let stale = [list("kept"), list("deleted-here")]

        XCTAssertEqual(ListCachePlan.inMemory(merged: stale, deletedIds: ["deleted-here"]).map(\.id),
                       ["kept"], "a stale response must not put the list back on screen")
        XCTAssertEqual(ListCachePlan.persistable(serverLists: stale, deletedIds: ["deleted-here"]).map(\.id),
                       ["kept"], "…nor write it back to CoreData, where the next launch reads it")
    }

    func testAPendingLocalListSurvivesTheDeletionFilter() {
        let pending = list("\(SyncOrphanPrune.localIdPrefix)new")
        let merged = [list("a"), pending]

        XCTAssertEqual(ListCachePlan.inMemory(merged: merged, deletedIds: ["other"]).map(\.id),
                       ["a", pending.id])
    }

    // MARK: - What the response says is gone

    func testACachedListMissingFromTheResponseIsStale() {
        XCTAssertEqual(ListCachePlan.stale(cachedIds: ["keep", "gone"], serverIds: ["keep"]), ["gone"])
    }

    /// The dangerous half. A list created offline is absent from every response by definition, so
    /// pruning it would destroy work that has never been sent.
    func testAListCreatedOfflineIsNeverStale() {
        let offline = "\(SyncOrphanPrune.localIdPrefix)new"
        XCTAssertEqual(ListCachePlan.stale(cachedIds: [offline, "gone"], serverIds: []), ["gone"])
    }

    func testAnEmptyResponseStalesEverySyncedList() {
        XCTAssertEqual(ListCachePlan.stale(cachedIds: ["a", "b"], serverIds: []).sorted(), ["a", "b"])
    }

    func testNothingIsStaleWhenTheResponseCarriesEverything() {
        XCTAssertTrue(ListCachePlan.stale(cachedIds: ["a", "b"], serverIds: ["a", "b"]).isEmpty)
    }
}
