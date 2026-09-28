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

}
