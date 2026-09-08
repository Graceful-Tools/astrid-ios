//  PersistedDefaultsCachesTests.swift
//  Task AITD-342 — caches that were a UserDefaults key rather than a value in memory.
//
//  The counting UserDefaults is the point. "Is this faster?" is not a thing a unit test can
//  answer, but "does asking this question touch the defaults plist at all?" is, and that is the
//  property that was actually wrong: `TaskService.updateTask` deserialised a 500-element array
//  and built a Set from it to answer one membership question, on every single task update.

import XCTest
@testable import Astrid_App

/// Counts what actually reaches the defaults store.
private final class CountingDefaults: UserDefaults {
    var reads = 0
    var writes = 0

    override func stringArray(forKey defaultName: String) -> [String]? {
        reads += 1
        return super.stringArray(forKey: defaultName)
    }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        reads += 1
        return super.dictionary(forKey: defaultName)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        writes += 1
        super.removeObject(forKey: defaultName)
    }
}

final class PersistedDefaultsCachesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: CountingDefaults!

    override func setUpWithError() throws {
        suiteName = "AITD342.\(UUID().uuidString)"
        defaults = try XCTUnwrap(CountingDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - The membership question (TaskService.updateTask's hot path)

    func testMembershipChecksNeverTouchTheDefaultsStore() {
        let ring = PersistedIdRing(key: "ids", cap: 500, defaults: defaults)
        ring.record((0..<500).map { "task-\($0)" })

        let readsAfterLoad = defaults.reads
        for index in 0..<1_000 {
            _ = ring.contains("task-\(index % 500)")
        }

        XCTAssertEqual(defaults.reads, readsAfterLoad,
                       "1000 membership checks must cost zero plist reads — this ran once per "
                       + "task update against a 500-element array (AITD-342)")
    }

    func testTheRingLoadsExactlyOnce() {
        _ = PersistedIdRing(key: "ids", cap: 500, defaults: defaults)
        XCTAssertEqual(defaults.reads, 1, "load once at init, then never again")
    }

    // MARK: - A sync pass is O(1) writes

    func testMergingNLinksCostsOneWrite() {
        let cache = PersistedStringDictionary(key: "links", defaults: defaults)
        let writesAfterLoad = defaults.writes

        var updates: [String: String] = [:]
        for index in 0..<300 { updates["task-\(index)"] = "remote-\(index)|repo" }
        cache.merge(updates)

        XCTAssertEqual(defaults.writes - writesAfterLoad, 1,
                       "a whole sync pass persists once, not once per link")
        XCTAssertEqual(cache["task-299"], "remote-299|repo")
    }

    func testWritingTheSameValueAgainPersistsNothing() {
        let cache = PersistedStringDictionary(key: "links", defaults: defaults)
        cache["a"] = "1"
        let writes = defaults.writes
        cache["a"] = "1"
        XCTAssertEqual(defaults.writes, writes, "an unchanged value is not a write")
    }

    func testMergingNothingNewPersistsNothing() {
        let cache = PersistedStringDictionary(key: "links", defaults: defaults)
        cache.merge(["a": "1"])
        let writes = defaults.writes
        cache.merge(["a": "1"])
        XCTAssertEqual(defaults.writes, writes)
    }

    // MARK: - Persistence and semantics are unchanged

    func testTheDictionarySurvivesAReload() {
        PersistedStringDictionary(key: "links", defaults: defaults).merge(["a": "1", "b": "2"])
        let reloaded = PersistedStringDictionary(key: "links", defaults: defaults)
        XCTAssertEqual(reloaded.all, ["a": "1", "b": "2"])
    }

    func testTheRingSurvivesAReload() {
        PersistedIdRing(key: "ids", cap: 10, defaults: defaults).record(["x", "y"])
        let reloaded = PersistedIdRing(key: "ids", cap: 10, defaults: defaults)
        XCTAssertTrue(reloaded.contains("x"))
        XCTAssertTrue(reloaded.contains("y"))
    }

    /// The reason the ledger is an ordered array and not a Set: at the cap, eviction must drop
    /// the OLDEST entries. A Set round-trip evicts arbitrarily and can drop the id just recorded,
    /// which is the deleted-task-reappears bug this whole ledger exists to prevent.
    func testEvictionDropsTheOldestAndNeverTheIdJustRecorded() {
        let ring = PersistedIdRing(key: "ids", cap: 3, defaults: defaults)
        ring.record(["a", "b", "c"])
        ring.record(["d"])

        XCTAssertFalse(ring.contains("a"), "oldest evicted")
        XCTAssertTrue(ring.contains("d"), "the id just recorded must survive")
        XCTAssertEqual(ring.ids, ["b", "c", "d"])
    }

    func testRecordingIsIdempotentAndDoesNotRefreshPosition() {
        let ring = PersistedIdRing(key: "ids", cap: 3, defaults: defaults)
        ring.record(["a", "b", "c"])
        let writes = defaults.writes
        ring.record(["a"])
        XCTAssertEqual(defaults.writes, writes, "re-recording a known id changes nothing")

        ring.record(["d"])
        XCTAssertFalse(ring.contains("a"),
                       "re-recording must not extend an id's life at an older entry's expense")
    }

    func testRemoveTakesAnIdOutOfMembership() {
        let ring = PersistedIdRing(key: "ids", cap: 10, defaults: defaults)
        ring.record(["a", "b"])
        ring.remove("a")
        XCTAssertFalse(ring.contains("a"))
        XCTAssertTrue(ring.contains("b"))
        XCTAssertEqual(PersistedIdRing(key: "ids", cap: 10, defaults: defaults).ids, ["b"],
                       "the removal is persisted, not just forgotten in memory")
    }

    func testRemovingSomethingAbsentPersistsNothing() {
        let ring = PersistedIdRing(key: "ids", cap: 10, defaults: defaults)
        ring.record(["a"])
        let writes = defaults.writes
        ring.remove("nope")
        XCTAssertEqual(defaults.writes, writes)
    }

    /// The append rule is lifted verbatim from `TaskService.appendingDeletedIds`, so it must
    /// still agree with it.
    func testAppendingMatchesTheLedgerRuleItReplaces() {
        XCTAssertEqual(PersistedIdRing.appending(["a", "b"], ["b", "c"], cap: 10),
                       TaskService.appendingDeletedIds(["a", "b"], ["b", "c"], cap: 10))
        XCTAssertEqual(PersistedIdRing.appending(["a", "b", "c"], ["d"], cap: 2),
                       TaskService.appendingDeletedIds(["a", "b", "c"], ["d"], cap: 2))
    }
}
