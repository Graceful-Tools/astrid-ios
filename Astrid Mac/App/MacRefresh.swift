//  MacRefresh.swift
//  Astrid for Mac — the manual refresh rule (Task 0f525a89).
//
//  The capability existed; the affordance did not. A "Refresh Lists" command was registered in
//  the palette, but you had to know to open the palette and type it — and it only called
//  `ListService.fetchLists()`, so it refreshed the SIDEBAR while leaving stale tasks on screen.
//
//  A real refresh is `SyncManager.performFullSync`: it pushes the outbox first, THEN fetches, so
//  a refresh can never overwrite work that had not been sent yet. (`performQuickSync` only pushes
//  pending operations — it fetches nothing, so it cannot answer "show me what changed".)

#if os(macOS)
import Foundation

enum MacRefresh {
    /// Offline there is nothing to fetch, and a second pass while one is running would just
    /// queue behind `SyncManager`'s own `isSyncing` guard while the control looked live.
    static func isEnabled(isOnline: Bool, isSyncing: Bool) -> Bool {
        isOnline && !isSyncing
    }

    /// The spinner replaces the icon only while a sync is actually in flight.
    static func showsProgress(isSyncing: Bool) -> Bool { isSyncing }
}

/// The refresh nobody asks for: viewing a list, or coming back to the app (AITD-570).
///
/// Opening a list used to call `fetchTasksForListFromServer` and drop the answer. That was a
/// paginated fetch of the whole list on every sidebar click, and it never reached the store, so
/// nothing on screen changed. Viewing now asks for one sync pass, which is a delta
/// (`updatedSince`) and merges into the store. This gate keeps it cheap. Clicking through the
/// sidebar is one pass per `minInterval`, and a pass that just ran for another reason (⌘R,
/// sign-in) counts. The live stream and the core's own timer keep things current between passes.
struct MacViewRefreshGate {
    static let minInterval: TimeInterval = 30

    private var lastAdmitted: Date?

    /// True when this view should start a pass, and if so, records it. A refused view (offline,
    /// mid-sync) records nothing, so coming back online refreshes at once.
    mutating func admit(isOnline: Bool, isSyncing: Bool, lastSync: Date?, now: Date) -> Bool {
        guard MacRefresh.isEnabled(isOnline: isOnline, isSyncing: isSyncing) else { return false }
        let freshest = [lastAdmitted, lastSync].compactMap { $0 }.max()
        if let freshest, now.timeIntervalSince(freshest) < Self.minInterval { return false }
        lastAdmitted = now
        return true
    }
}
#endif
