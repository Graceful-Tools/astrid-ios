//  ListSettingsPayload.swift
//  What the list-settings sheet actually sends: the diff between the list as it was and the list
//  as the user left it (AITD-409).
//
//  This was ~85 lines inlined in `TaskListView.handleListUpdate`, which is how it came to be
//  missing a branch: the admin tab's "Recently completed" picker updated the local model and was
//  then dropped before the request, because nothing here compared it (found while auditing Mac
//  parity, task 545812e6). A field forgotten in a wall of near-identical `if` statements inside a
//  1,700-line view is invisible; the same omission in a pure function is one absent test.
//
//  So the rule this type encodes is worth stating plainly: **only changed keys are sent, and a
//  cleared field must be sent as `NSNull()` rather than omitted.** Swift drops a `nil` value from
//  a dictionary entirely, and an omitted key means "leave it alone" to the server — so clearing a
//  default assignee by assigning `nil` would silently leave the old one in place.

import Foundation

enum ListSettingsPayload {

    /// The `updates` dictionary for `ListService.updateListAdvanced`, carrying only what changed.
    /// Empty means nothing changed and no request should be made.
    static func updates(original: TaskList, updated: TaskList) -> [String: Any] {
        var updates: [String: Any] = [:]

        if updated.name != original.name {
            updates["name"] = updated.name
        }
        if updated.description != original.description {
            updates["description"] = updated.description ?? ""
        }
        if updated.sortBy != original.sortBy {
            updates["sortBy"] = updated.sortBy ?? "manual"
        }
        // Only on an actual change — a rename must not carry a showSubtasks value with it
        // and quietly hide the list's subtasks (ba1deb9d).
        if let value = ListSubtaskVisibility.payloadValue(original: original.showSubtasks,
                                                          edited: updated.showSubtasks) {
            updates["showSubtasks"] = value
        }

        // List defaults
        if updated.defaultPriority != original.defaultPriority {
            updates["defaultPriority"] = updated.defaultPriority ?? 0
        }
        if updated.defaultDueDate != original.defaultDueDate {
            updates["defaultDueDate"] = updated.defaultDueDate ?? "none"
        }
        if updated.defaultDueTime != original.defaultDueTime {
            updates["defaultDueTime"] = updated.defaultDueTime ?? NSNull()
        }
        if updated.defaultIsPrivate != original.defaultIsPrivate {
            updates["defaultIsPrivate"] = updated.defaultIsPrivate ?? true
        }
        if updated.defaultRepeating != original.defaultRepeating {
            updates["defaultRepeating"] = updated.defaultRepeating ?? "never"
        }
        if updated.defaultAssigneeId != original.defaultAssigneeId {
            updates["defaultAssigneeId"] = updated.defaultAssigneeId ?? NSNull()
        }

        // Filters
        if updated.filterPriority != original.filterPriority {
            updates["filterPriority"] = updated.filterPriority ?? "all"
        }
        if updated.filterAssignee != original.filterAssignee {
            updates["filterAssignee"] = updated.filterAssignee ?? "all"
        }
        if updated.filterDueDate != original.filterDueDate {
            updates["filterDueDate"] = updated.filterDueDate ?? "all"
        }
        if updated.filterCompletion != original.filterCompletion {
            updates["filterCompletion"] = updated.filterCompletion ?? "default"
        }
        if updated.filterAssignedBy != original.filterAssignedBy {
            updates["filterAssignedBy"] = updated.filterAssignedBy ?? "all"
        }
        if updated.filterRepeating != original.filterRepeating {
            updates["filterRepeating"] = updated.filterRepeating ?? "all"
        }
        if updated.filterInLists != original.filterInLists {
            updates["filterInLists"] = updated.filterInLists ?? "dont_filter"
        }

        if updated.privacy != original.privacy {
            updates["privacy"] = updated.privacy?.rawValue ?? "PRIVATE"
        }
        if updated.imageUrl != original.imageUrl {
            updates["imageUrl"] = updated.imageUrl ?? NSNull()
        }
        // The branch that was missing (task 545812e6). NSNull is the legacy 24h default, which is
        // a real choice — omitting the key would leave the old window in place.
        if updated.recentlyCompletedWindow != original.recentlyCompletedWindow {
            updates["recentlyCompletedWindow"] = updated.recentlyCompletedWindow?.updatePayloadValue ?? NSNull()
        }

        return updates
    }
}
