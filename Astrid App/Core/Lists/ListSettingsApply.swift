//  ListSettingsApply.swift
//  The mirror of `ListSettingsPayload`: that one turns two lists into the `updates` dictionary to
//  send, this one applies such a dictionary back onto a list to produce the optimistic copy the UI
//  shows before the server answers.
//
//  Extracted from `ListService.updateListAdvanced` (AITD-410), where it was ~37 lines of
//  near-identical `if let` statements in the middle of a method that also does caching, CoreData
//  and networking. That is the same shape, in the same feature, that hid a missing field until
//  someone audited it (545812e6) — and the argument `ListSettingsPayload` already made: a field
//  forgotten in a wall of near-identical `if`s is invisible, while the same omission in a pure
//  function is one absent test.
//
//  Keeping the two halves as separate pure functions also makes them checkable against each
//  other: anything `ListSettingsPayload` can emit, this should be able to apply.

import Foundation

enum ListSettingsApply {

    /// `list` with every recognised key in `updates` applied to it. Unknown keys are ignored, and
    /// an absent key leaves its field alone — the same "omitted means don't touch" rule the server
    /// follows, so the optimistic copy matches what the server will do with the same body.
    static func applying(_ updates: [String: Any], to list: TaskList) -> TaskList {
        var updated = list

        if let name = updates["name"] as? String { updated.name = name }
        if let description = updates["description"] as? String { updated.description = description }
        if let color = updates["color"] as? String { updated.color = color }
        if let imageUrl = updates["imageUrl"] as? String { updated.imageUrl = imageUrl }
        if let privacy = updates["privacy"] as? String, let privacyEnum = TaskList.Privacy(rawValue: privacy) {
            updated.privacy = privacyEnum
        }
        if let publicListType = updates["publicListType"] as? String { updated.publicListType = publicListType }
        if let isFavorite = updates["isFavorite"] as? Bool { updated.isFavorite = isFavorite }
        if let showSubtasks = updates["showSubtasks"] as? Bool { updated.showSubtasks = showSubtasks }

        // List defaults. `defaultDueTime` and `defaultAssigneeId` test for the KEY rather than for a
        // castable value, because both are clearable: the sheet sends `NSNull()` to mean "clear
        // this", which casts to nil, and `as? String` alone cannot tell that apart from an absent
        // key. Getting this wrong leaves the old value on screen until the next fetch.
        if let defaultPriority = updates["defaultPriority"] as? Int { updated.defaultPriority = defaultPriority }
        if let defaultRepeating = updates["defaultRepeating"] as? String { updated.defaultRepeating = defaultRepeating }
        if let defaultIsPrivate = updates["defaultIsPrivate"] as? Bool { updated.defaultIsPrivate = defaultIsPrivate }
        if let defaultDueDate = updates["defaultDueDate"] as? String { updated.defaultDueDate = defaultDueDate }
        if updates.keys.contains("defaultDueTime") { updated.defaultDueTime = updates["defaultDueTime"] as? String }
        if updates.keys.contains("defaultAssigneeId") { updated.defaultAssigneeId = updates["defaultAssigneeId"] as? String }

        // Virtual list settings
        if let isVirtual = updates["isVirtual"] as? Bool { updated.isVirtual = isVirtual }
        if let virtualListType = updates["virtualListType"] as? String { updated.virtualListType = virtualListType }

        // Sort and filter settings
        if let sortBy = updates["sortBy"] as? String { updated.sortBy = sortBy }
        if let filterPriority = updates["filterPriority"] as? String { updated.filterPriority = filterPriority }
        if let filterAssignee = updates["filterAssignee"] as? String { updated.filterAssignee = filterAssignee }
        if let filterDueDate = updates["filterDueDate"] as? String { updated.filterDueDate = filterDueDate }
        if let filterCompletion = updates["filterCompletion"] as? String { updated.filterCompletion = filterCompletion }
        if let filterRepeating = updates["filterRepeating"] as? String { updated.filterRepeating = filterRepeating }
        if let filterAssignedBy = updates["filterAssignedBy"] as? String { updated.filterAssignedBy = filterAssignedBy }
        if let filterInLists = updates["filterInLists"] as? String { updated.filterInLists = filterInLists }

        return updated
    }
}
