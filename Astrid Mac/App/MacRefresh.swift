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
#endif
