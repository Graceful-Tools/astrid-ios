import Foundation

/// Durable persistence for the temp→real task-id map.
///
/// Offline-created tasks get a temporary id (`temp_<uuid>`); when they sync,
/// TaskService records `temp → realServerId` so pending children (a photo/comment
/// queued against the temp id, in the legacy path AND the Outbox) can re-target
/// the real task. That map used to live only in memory, so a relaunch between the
/// task syncing and a child syncing stranded the child. Persisting it survives
/// relaunch.
enum TempTaskMappingStore {
    static let key = "tempTaskIdMapping"
    /// Cap so the store can't grow without bound; oldest-inserted are dropped.
    static let maxEntries = 500

    /// Durable store key for the comment temp→real map (offline-created comment
    /// edited before its create drained — the edit's updateComment entry must
    /// resolve the temp id after a relaunch that happens once the create has
    /// already completed, so the in-memory map is gone). Same shape as tasks.
    static let commentKey = "tempCommentIdMapping"

    static func load(_ defaults: UserDefaults = .standard, key: String = key) -> [String: String] {
        (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    static func save(_ map: [String: String], to defaults: UserDefaults = .standard, key: String = key) {
        defaults.set(map, forKey: key)
    }

    /// Returns the map with `temp → real` recorded, bounded to `maxEntries`.
    /// Pure so it's unit-testable.
    static func recording(_ map: [String: String], temp: String, real: String) -> [String: String] {
        guard temp.hasPrefix("temp_"), temp != real else { return map }
        var updated = map
        updated[temp] = real
        if updated.count > maxEntries {
            // Drop excess (never the just-added one); the map is a best-effort
            // cache and stale temp ids are harmless once their children synced.
            let dropCount = updated.count - maxEntries
            for key in updated.keys.filter({ $0 != temp }).prefix(dropCount) {
                updated.removeValue(forKey: key)
            }
        }
        return updated
    }
}
