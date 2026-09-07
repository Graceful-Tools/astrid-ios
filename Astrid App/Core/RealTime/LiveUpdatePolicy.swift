//  LiveUpdatePolicy.swift
//  Whether an SSE payload may be applied to the local cache.
//
//  Task 63e75630 (AITD-314). Before this, `task_*` and `list_*` events were decoded and delivered
//  to handler arrays that nothing had ever subscribed to — a collaborator's edit cost the victim a
//  triple parse and changed nothing on screen until the 60 s full pull.
//
//  Wiring the handlers up is the easy half. The hard half is that a live event is exactly the case
//  where `updateTaskInCache`'s unconditional overwrite is wrong: an event can arrive AFTER a local
//  edit the server has not seen yet, and it can arrive for a task the user just deleted. These
//  rules deliberately mirror `TaskService.mergeAndSortTasksInBackground`, which already decides the
//  same question for the 60 s pull — if the two disagreed, a row would flip between them.

import Foundation

enum LiveUpdatePolicy {

    enum Decision: Equatable {
        case apply
        /// The local copy carries an edit newer than this event.
        case ignoreStale
        /// The user deleted this locally; a late event must not resurrect it.
        case ignoreLocallyDeleted
        /// A temp id never comes from the server — it is ours, mid-create.
        case ignoreTemporaryId
    }

    /// Prefix marking an offline-created, not-yet-synced id. Reused from `SyncOrphanPrune`
    /// rather than re-declared — a second copy is how the two rules drift apart.
    static let temporaryIdPrefix = SyncOrphanPrune.localIdPrefix

    // MARK: - Tasks

    static func taskUpsert(incoming: Task, cached: Task?, locallyDeletedIds: Set<String>) -> Decision {
        if incoming.id.hasPrefix(temporaryIdPrefix) { return .ignoreTemporaryId }
        if locallyDeletedIds.contains(incoming.id) { return .ignoreLocallyDeleted }

        if let cached {
            let localUpdated = cached.updatedAt ?? .distantPast
            let remoteUpdated = incoming.updatedAt ?? .distantPast
            // Strictly newer only: an equal timestamp means the server has this edit, so take the
            // server copy (it may carry fields the local one does not).
            if localUpdated > remoteUpdated { return .ignoreStale }
        }

        return .apply
    }

    static func taskDelete(id: String) -> Decision {
        id.hasPrefix(temporaryIdPrefix) ? .ignoreTemporaryId : .apply
    }

    // MARK: - Lists

    static func listUpsert(incoming: TaskList, cached: TaskList?) -> Decision {
        if incoming.id.hasPrefix(temporaryIdPrefix) { return .ignoreTemporaryId }

        if let cached {
            let localUpdated = cached.updatedAt ?? .distantPast
            let remoteUpdated = incoming.updatedAt ?? .distantPast
            if localUpdated > remoteUpdated { return .ignoreStale }
        }

        return .apply
    }

    static func listDelete(id: String) -> Decision {
        id.hasPrefix(temporaryIdPrefix) ? .ignoreTemporaryId : .apply
    }
}
