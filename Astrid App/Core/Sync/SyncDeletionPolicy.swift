import Foundation

/// Pure deletion-sync rules shared by the external sync workers. Developed
/// red-green; spec in `SyncDeletionPolicyTests`.
///
/// Two invariants:
/// - Remote deletions are TOMBSTONE-driven (the app captured the link when the
///   user deleted the task), never inferred from a task being absent — absence
///   can mean "not loaded".
/// - Local deletions from remote absence require a COMPLETE remote listing:
///   a failed fetch (nil) or a truncated page must never mass-delete local
///   tasks. Explicit deleted flags (Google's `deleted=1`) work regardless.
enum SyncDeletionPolicy {
    struct Link: Equatable {
        let taskId: String
        let remoteId: String
    }

    /// Links whose local task the user deleted → delete/close the remote twin.
    static func remoteDeletions(links: [Link], tombstonedTaskIds: Set<String>) -> [Link] {
        links.filter { tombstonedTaskIds.contains($0.taskId) }
    }

    /// Links whose remote item is gone → delete the local twin.
    static func localDeletions(
        links: [Link],
        fullRemoteIds: Set<String>?,
        truncated: Bool,
        explicitlyDeletedRemoteIds: Set<String>
    ) -> [Link] {
        links.filter { link in
            if explicitlyDeletedRemoteIds.contains(link.remoteId) { return true }
            guard let fullRemoteIds, !truncated else { return false }
            return !fullRemoteIds.contains(link.remoteId)
        }
    }
}

/// Apple Reminders: whether to pull field edits (title/notes/due) from a
/// mapped reminder — only when it changed since the stamp we recorded at the
/// last sync (echo/no-op suppression for the EventKit side).
enum AppleEditPull {
    static func shouldPullFields(reminderModified: Date?, lastSyncedReminderStamp: Date?) -> Bool {
        guard let reminderModified else { return false }
        guard let lastSyncedReminderStamp else { return true }
        return reminderModified > lastSyncedReminderStamp
    }
}

/// Device-persisted record of "the user deleted this mirrored task": the
/// server-side task link cascades away with the task row, so the link must be
/// captured AT delete time. Executed (remote delete/close) on the next sync
/// pass; remote ids stay tombstoned so a pull never resurrects the task.
struct SyncDeletionLedger {
    let key: String
    private let tombstoneKey: String
    private let cap = 500

    init(provider: String) {
        key = "syncPendingRemoteDeletes.\(provider)"
        tombstoneKey = "syncDeletedRemoteIds.\(provider)"
    }

    /// Every UserDefaults key this ledger owns — consumed by the sign-out
    /// reset so per-user state can't leak to the next account on the device.
    var storageKeys: [String] { [key, tombstoneKey] }

    /// remoteId → remoteContainerId (pending remote deletions)
    var pending: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Remote ids we deleted/closed because the local task was deleted —
    /// pull-create must never re-import these. Stored as an ORDERED array so
    /// the cap evicts oldest-first (a Set's suffix is hash-ordered and could
    /// evict the id just added).
    var tombstonedRemoteIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? [])
    }

    func recordTombstone(_ remoteId: String) {
        var arr = UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []
        guard !arr.contains(remoteId) else { return }
        arr.append(remoteId)
        if arr.count > cap { arr.removeFirst(arr.count - cap) }
        UserDefaults.standard.set(arr, forKey: tombstoneKey)
    }

    func recordPending(remoteId: String, containerId: String) {
        var p = pending
        p[remoteId] = containerId
        pending = p
        recordTombstone(remoteId)
    }

    func clearPending(remoteId: String) {
        var p = pending
        p.removeValue(forKey: remoteId)
        pending = p
    }
}

/// Completion drift between a linked pair. Completing locally is safe when
/// the local task never recorded a completion (a sync-created row that
/// drifted — the Google flood repair) or is untouched since last sync;
/// UN-completing is destructive and only applies to untouched tasks.
enum CompletionDriftPolicy {
    static func shouldAdoptRemote(
        remoteCompleted: Bool,
        localCompleted: Bool,
        localCompletedAt: Date?,
        localUnchanged: Bool,
        isRepeating: Bool = false
    ) -> Bool {
        guard remoteCompleted != localCompleted else { return false }
        if remoteCompleted {
            // The `localCompletedAt == nil` escape repairs a sync-created row
            // that never recorded a completion (the Google flood). But a
            // repeating task that just rolled forward ALSO has completedAt ==
            // nil and is legitimately incomplete — applying the escape there
            // re-completes it against a stale "still closed" snapshot, forcing
            // a second rollover (due date marches) or reverting an
            // un-completion. For repeating tasks, adopt remote completion ONLY
            // when the local task is genuinely untouched since last sync.
            if isRepeating { return localUnchanged }
            return localUnchanged || localCompletedAt == nil
        }
        return localUnchanged
    }
}

/// Sign-out reset for per-user sync state persisted OUTSIDE CoreData (which
/// the sign-out flow wipes separately). A stale entry here would leak the
/// previous account's links/tombstones — or replay their queued writes —
/// into the next account on a shared device.
enum SyncStateReset {
    static var userDefaultsKeys: [String] {
        SyncDeletionLedger(provider: "github").storageKeys
            + SyncDeletionLedger(provider: "google").storageKeys
            + ["githubTaskLinkCache", "googleTaskLinkCache",
               "recentlyDeletedTaskIds", "recentlyDeletedListIds", "pendingAttachments",
               "tempTaskIdMapping", "tempCommentIdMapping",
               "AppleReminders.linkedLists", "AppleReminders.lastSyncDate"]
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        for key in userDefaultsKeys { defaults.removeObject(forKey: key) }
    }
}
