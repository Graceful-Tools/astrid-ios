//  MacQuickAdd.swift
//  Astrid for Mac — pure quick-add helper for the task table (task 76817a57).
//
//  Turns raw quick-add text into TaskService.createTask arguments, preserving the shared
//  SmartTaskParser (dates/priority/#lists/repeat). Returns nil for empty input — that is what
//  makes an abandoned draft create nothing (the old flow eagerly created a junk "New Task").

#if os(macOS)
import Foundation

enum MacQuickAdd {
    struct CreateArgs {
        let title: String
        let listIds: [String]
        let priority: Int?
        let whenDate: Date?          // smart-parsed dates are all-day (mirrors iOS QuickAdd)
        let repeating: String?
        let repeatingData: CustomRepeatingPattern?
        var assigneeId: String?      // from the list's default assignee
        var isPrivate: Bool?         // from the list's default privacy
    }

    /// Build create args from raw quick-add text. Returns nil when there is nothing to
    /// commit (empty/whitespace) or no destination list — abandoned drafts create nothing.
    /// `smartEnabled` gates the shared SmartTaskParser (the user's Smart Task Creation setting).
    /// Whether the ⊕ button should be live: there is something other than whitespace to create.
    /// Pure so the button's enabled state is testable (task 022701f3).
    static func isCommittable(_ rawText: String) -> Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// - Parameter selectionIsVirtual: true for My Tasks (and saved filters). A virtual selection
    ///   is NOT a real list, so it must never be attached as a list id — iOS does the same: a task
    ///   added from My Tasks belongs to no list unless the text names one with #list, and shows up
    ///   there because My Tasks lists what is mine or unassigned.
    /// - Parameter priorityOverride: what the user picked on the quick-add checkbox. It beats the
    ///   list default; typed text beats it in turn, so the last thing the user expressed wins.
    static func makeArgs(rawText: String, selectedListId: String?, lists: [TaskList],
                         smartEnabled: Bool = true,
                         selectionIsVirtual: Bool = false,
                         priorityOverride: Int? = nil,
                         currentUserId: String? = nil) -> CreateArgs? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedListId else { return nil }
        let realListId = selectionIsVirtual ? nil : selectedListId
        // Defaults come from the destination list — a virtual selection (My Tasks) has none.
        let defaultsList = realListId.flatMap { id in lists.first { $0.id == id } }

        guard smartEnabled else {
            return applyingDefaults(
                CreateArgs(title: trimmed, listIds: realListId.map { [$0] } ?? [],
                           priority: nil, whenDate: nil, repeating: nil, repeatingData: nil),
                from: defaultsList, priorityOverride: priorityOverride,
                currentUserId: currentUserId)
        }

        let parsed = SmartTaskParser.parse(trimmed, lists: lists)
        let title = parsed.title.isEmpty ? trimmed : parsed.title

        // Include the currently selected REAL list, plus any #lists the parser found.
        var listIds = parsed.listIds
        if let realListId, !listIds.contains(realListId) { listIds.insert(realListId, at: 0) }

        return applyingDefaults(
            CreateArgs(title: title, listIds: listIds, priority: parsed.priority,
                       whenDate: parsed.dueDateTime, repeating: parsed.repeating?.rawValue,
                       repeatingData: parsed.customRepeatingData),
            from: defaultsList, priorityOverride: priorityOverride, currentUserId: currentUserId)
    }

    /// Fill only the gaps the user left, using the SHARED `NewTaskDefaults` (the same resolution iOS
    /// uses) — a default must never overwrite something they typed or chose.
    private static func applyingDefaults(_ args: CreateArgs, from list: TaskList?,
                                         priorityOverride: Int?,
                                         currentUserId: String?) -> CreateArgs {
        var out = args
        // Priority: typed > checkbox override > list default.
        if out.priority == nil {
            let resolved = priorityOverride ?? NewTaskDefaults.priority(list?.defaultPriority)
            out = CreateArgs(title: out.title, listIds: out.listIds, priority: resolved,
                             whenDate: out.whenDate, repeating: out.repeating,
                             repeatingData: out.repeatingData,
                             assigneeId: out.assigneeId, isPrivate: out.isPrivate)
        }
        guard let list else { return out }
        if out.whenDate == nil {
            out = CreateArgs(title: out.title, listIds: out.listIds, priority: out.priority,
                             whenDate: NewTaskDefaults.dueDate(from: list.defaultDueDate,
                                                            time: list.defaultDueTime),
                             repeating: out.repeating, repeatingData: out.repeatingData,
                             assigneeId: out.assigneeId, isPrivate: out.isPrivate)
        }
        if out.repeating == nil {
            out = CreateArgs(title: out.title, listIds: out.listIds, priority: out.priority,
                             whenDate: out.whenDate,
                             repeating: NewTaskDefaults.repeating(list.defaultRepeating),
                             repeatingData: out.repeatingData,
                             assigneeId: out.assigneeId, isPrivate: out.isPrivate)
        }
        out.assigneeId = NewTaskDefaults.assignee(list.defaultAssigneeId, currentUserId: currentUserId)
        out.isPrivate = list.defaultIsPrivate
        return out
    }

    /// Build create args for a GLOBAL quick-add (the ⌥Space window and the menu-bar), which has no
    /// "current list" context. Uses the parser's #list(s) when present, otherwise falls back to the
    /// first available list — unlike `makeArgs`, it does NOT force-add a selected list (Task fa267754).
    /// Returns nil for empty input or when there is no list to add to.
    static func makeGlobalArgs(rawText: String, lists: [TaskList], smartEnabled: Bool = true,
                               currentUserId: String? = nil) -> CreateArgs? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lists.isEmpty else { return nil }

        // The list's defaults apply here too (Task 3d47cb62). This path used to create the task
        // raw, so a task added from the menu bar started differently from the identical task added
        // in the list — same destination, two answers. Defaults come from the DESTINATION list,
        // which is whatever the text named, not simply the first list.
        func defaults(for listIds: [String]) -> TaskList? {
            listIds.first.flatMap { id in lists.first { $0.id == id } }
        }

        guard smartEnabled else {
            let listIds = [lists[0].id]
            return applyingDefaults(
                CreateArgs(title: trimmed, listIds: listIds,
                           priority: nil, whenDate: nil, repeating: nil, repeatingData: nil),
                from: defaults(for: listIds), priorityOverride: nil, currentUserId: currentUserId)
        }

        let parsed = SmartTaskParser.parse(trimmed, lists: lists)
        let title = parsed.title.isEmpty ? trimmed : parsed.title
        let listIds = parsed.listIds.isEmpty ? [lists[0].id] : parsed.listIds

        return applyingDefaults(
            CreateArgs(
                title: title,
                listIds: listIds,
                priority: parsed.priority,
                whenDate: parsed.dueDateTime,
                repeating: parsed.repeating?.rawValue,
                repeatingData: parsed.customRepeatingData
            ),
            from: defaults(for: listIds), priorityOverride: nil, currentUserId: currentUserId)
    }
}
#endif
