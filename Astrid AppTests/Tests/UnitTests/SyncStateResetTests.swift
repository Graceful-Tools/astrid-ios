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
}
