import XCTest
@testable import Astrid_App

/// Red-green spec for sign-out cleanup of per-user sync state. A stale key
/// here would leak the previous account's links/tombstones — or replay their
/// queued writes — into the next account on a shared device.
final class SyncStateResetTests: XCTestCase {
    func testCoversEveryLedgerStorageKey() {
        let keys = Set(SyncStateReset.userDefaultsKeys)
        for provider in ["github", "google"] {
            for key in SyncDeletionLedger(provider: provider).storageKeys {
                XCTAssertTrue(keys.contains(key), "sign-out reset misses ledger key \(key)")
            }
        }
    }

    func testCoversKnownPerUserSyncKeys() {
        let keys = Set(SyncStateReset.userDefaultsKeys)
        for key in ["githubTaskLinkCache", "googleTaskLinkCache",
                    "recentlyDeletedTaskIds", "recentlyDeletedListIds", "pendingAttachments",
                    "AppleReminders.linkedLists", "AppleReminders.lastSyncDate"] {
            XCTAssertTrue(keys.contains(key), "sign-out reset misses \(key)")
        }
    }

    /// The Swift outbox's temp-id maps have had no writer since the core took the journal over
    /// (checked 2026-10-22, AITD-536). Sign-out still clears them, for installs that wrote them
    /// before — but they are leftovers, not live state, and pinning them beside the live keys
    /// read as if something still used them.
    func testLegacyTempIdMapsAreStillClearedForOldInstalls() {
        let keys = Set(SyncStateReset.userDefaultsKeys)
        for key in ["tempTaskIdMapping", "tempCommentIdMapping"] {
            XCTAssertTrue(keys.contains(key), "an old install's \(key) would survive sign-out")
        }
    }

    func testClearAllRemovesEveryKey() {
        let suite = "SyncStateResetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in SyncStateReset.userDefaultsKeys {
            defaults.set("previous-user-data", forKey: key)
        }
        SyncStateReset.clearAll(defaults: defaults)
        for key in SyncStateReset.userDefaultsKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) survived sign-out")
        }
    }

    func testClearAllRemovesDynamicPerContainerFullPullGates() {
        let suite = "SyncStateResetTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Date(), forKey: "githubLastFullPull:owner/repo")
        defaults.set(Date(), forKey: "googleLastFullPull:tasklist-1")
        defaults.set("keep", forKey: "unrelatedPreference")

        SyncStateReset.clearAll(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "githubLastFullPull:owner/repo"))
        XCTAssertNil(defaults.object(forKey: "googleLastFullPull:tasklist-1"))
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "keep")
    }
}
