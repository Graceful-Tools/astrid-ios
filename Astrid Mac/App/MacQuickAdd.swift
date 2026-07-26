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
    }

    /// Build create args from raw quick-add text. Returns nil when there is nothing to
    /// commit (empty/whitespace) or no destination list — abandoned drafts create nothing.
    /// `smartEnabled` gates the shared SmartTaskParser (the user's Smart Task Creation setting).
    /// Whether the ⊕ button should be live: there is something other than whitespace to create.
    /// Pure so the button's enabled state is testable (task 022701f3).
    static func isCommittable(_ rawText: String) -> Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func makeArgs(rawText: String, selectedListId: String?, lists: [TaskList],
                         smartEnabled: Bool = true) -> CreateArgs? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let selectedListId else { return nil }

        guard smartEnabled else {
            return CreateArgs(title: trimmed, listIds: [selectedListId],
                              priority: nil, whenDate: nil, repeating: nil, repeatingData: nil)
        }

        let parsed = SmartTaskParser.parse(trimmed, lists: lists)
        let title = parsed.title.isEmpty ? trimmed : parsed.title

        // Always include the currently selected list, plus any #lists the parser found.
        var listIds = parsed.listIds
        if !listIds.contains(selectedListId) { listIds.insert(selectedListId, at: 0) }

        return CreateArgs(
            title: title,
            listIds: listIds,
            priority: parsed.priority,
            whenDate: parsed.dueDateTime,
            repeating: parsed.repeating?.rawValue,
            repeatingData: parsed.customRepeatingData
        )
    }

    /// Build create args for a GLOBAL quick-add (the ⌥Space window and the menu-bar), which has no
    /// "current list" context. Uses the parser's #list(s) when present, otherwise falls back to the
    /// first available list — unlike `makeArgs`, it does NOT force-add a selected list (Task fa267754).
    /// Returns nil for empty input or when there is no list to add to.
    static func makeGlobalArgs(rawText: String, lists: [TaskList], smartEnabled: Bool = true) -> CreateArgs? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lists.isEmpty else { return nil }

        guard smartEnabled else {
            return CreateArgs(title: trimmed, listIds: [lists[0].id],
                              priority: nil, whenDate: nil, repeating: nil, repeatingData: nil)
        }

        let parsed = SmartTaskParser.parse(trimmed, lists: lists)
        let title = parsed.title.isEmpty ? trimmed : parsed.title
        let listIds = parsed.listIds.isEmpty ? [lists[0].id] : parsed.listIds

        return CreateArgs(
            title: title,
            listIds: listIds,
            priority: parsed.priority,
            whenDate: parsed.dueDateTime,
            repeating: parsed.repeating?.rawValue,
            repeatingData: parsed.customRepeatingData
        )
    }
}
#endif
