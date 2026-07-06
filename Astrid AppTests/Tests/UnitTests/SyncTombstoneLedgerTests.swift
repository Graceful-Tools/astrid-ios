import XCTest
@testable import Astrid_App

/// Locks the fix for tombstone resurrection (review 0d70b056): merging the
/// server's tombstone set (up to its cap) must NOT evict this device's own
/// local-delete tombstones — otherwise a locally-deleted task can resurrect
/// via completed-backfill (a GitHub twin is only closed, not deleted).
final class SyncTombstoneLedgerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "TombstoneLedgerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // The ledger reads UserDefaults.standard directly; use a real ledger and
    // clean up its keys after. Isolate by unique provider names per test.
    private func ledger() -> SyncDeletionLedger { SyncDeletionLedger(provider: "test-\(UUID().uuidString)") }
    private func cleanup(_ l: SyncDeletionLedger) { for k in l.storageKeys { UserDefaults.standard.removeObject(forKey: k) } }

    func testLocalTombstoneSurvivesLargeServerMerge() {
        let l = ledger(); defer { cleanup(l) }
        l.recordTombstone("local-mine")
        // Merge far more server tombstones than the LOCAL cap (500) — under the
        // old shared-array design this would evict "local-mine".
        l.mergeServerTombstones((0..<2000).map { "server-\($0)" })

        XCTAssertTrue(l.tombstonedRemoteIds.contains("local-mine"),
                      "local tombstone must survive a large server merge")
        XCTAssertTrue(l.tombstonedRemoteIds.contains("server-1999"))
        XCTAssertEqual(l.tombstonedRemoteIds.filter { $0 == "local-mine" }.count, 1)
    }

    func testServerStoreIsSeparateAndUnioned() {
        let l = ledger(); defer { cleanup(l) }
        l.recordTombstone("a")
        l.mergeServerTombstones(["b", "c"])
        XCTAssertEqual(l.tombstonedRemoteIds, ["a", "b", "c"])
    }

    func testMergeIsIdempotentAndCoversNewServerKey() {
        let l = ledger(); defer { cleanup(l) }
        l.mergeServerTombstones(["x"])
        l.mergeServerTombstones(["x", "y"])
        XCTAssertEqual(l.tombstonedRemoteIds, ["x", "y"])
        // The new server store key is part of storageKeys → covered by sign-out reset.
        XCTAssertTrue(l.storageKeys.contains { $0.hasPrefix("syncServerTombstones.") })
    }
}
