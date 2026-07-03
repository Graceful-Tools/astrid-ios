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

    /// remoteId → remoteContainerId (pending remote deletions)
    var pending: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Remote ids we deleted/closed because the local task was deleted —
    /// pull-create must never re-import these.
    var tombstonedRemoteIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: tombstoneKey) ?? []) }
        nonmutating set {
            UserDefaults.standard.set(Array(newValue.suffix(cap)), forKey: tombstoneKey)
        }
    }

    func recordPending(remoteId: String, containerId: String) {
        var p = pending
        p[remoteId] = containerId
        pending = p
        tombstonedRemoteIds.insert(remoteId)
    }

    func clearPending(remoteId: String) {
        var p = pending
        p.removeValue(forKey: remoteId)
        pending = p
    }
}
