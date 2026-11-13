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
        var whenTime: Date? = nil    // a list default with a time: a timed task, not all-day
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
    ///   there because it is assigned to its creator and My Tasks lists what is assigned to me.
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

    /// Fill only the gaps the user left, asking astrid-core's `quickAddDefaults` (the same rule iOS
    /// and the web use) — a default must never overwrite something they typed or chose.
    ///
    /// NO DESTINATION LIST is My Tasks (AITD-387): there are no list defaults to apply, but the
    /// CREATOR default is not a list default, so a task typed into the quick-add window still
    /// starts as yours — exactly as the same text typed into the add bar of an unopinionated list
    /// does. Left nil, every quick-added task would be nobody's, which since AITD-382 is also a
    /// task you cannot tick off in one tap.
    private static func applyingDefaults(_ args: CreateArgs, from list: TaskList?,
                                         priorityOverride: Int?,
                                         currentUserId: String?) -> CreateArgs {
        // Priority: typed > checkbox override > list default.
        let chosenPriority = args.priority ?? priorityOverride
        let defaults = ListQuickAddDefaults.resolve(list, currentUserId: currentUserId,
                                                    priority: chosenPriority)
        var out = CreateArgs(title: args.title, listIds: args.listIds,
                             priority: chosenPriority ?? (defaults.priority > 0 ? defaults.priority : nil),
                             whenDate: args.whenDate, repeating: args.repeating,
                             repeatingData: args.repeatingData,
                             assigneeId: defaults.assigneeId, isPrivate: args.isPrivate,
                             whenTime: args.whenTime)
        guard list != nil else { return out }
        if out.whenDate == nil, let due = defaults.dueDateTime {
            // createTask reads a date alone as all-day and a time as a timed task.
            out = CreateArgs(title: out.title, listIds: out.listIds, priority: out.priority,
                             whenDate: due, repeating: out.repeating,
                             repeatingData: out.repeatingData,
                             assigneeId: out.assigneeId, isPrivate: out.isPrivate,
                             whenTime: defaults.isAllDay ? nil : due)
        }
        if out.repeating == nil {
            out = CreateArgs(title: out.title, listIds: out.listIds, priority: out.priority,
                             whenDate: out.whenDate, repeating: defaults.repeating,
                             repeatingData: out.repeatingData,
                             assigneeId: out.assigneeId, isPrivate: out.isPrivate,
                             whenTime: out.whenTime)
        }
        out.isPrivate = list?.defaultIsPrivate
        return out
    }

    /// Build create args for a GLOBAL quick-add (the ⌥Space window and the menu-bar), which has no
    /// "current list" context. Uses the parser's #list(s) when present, and otherwise adds to MY
    /// TASKS — unlike `makeArgs`, it does NOT force-add a selected list (Task fa267754).
    /// Returns nil only for empty input: an abandoned draft creates nothing.
    ///
    /// IT USED TO FALL BACK TO `lists[0]` (AITD-387). That is not a destination anyone chose — it
    /// is whichever list the service happened to hand over first, so for this account every task
    /// typed into the ⌥Space window landed in "Astrid iOS To-do". Jon: "for some reason it always
    /// adds it to AStrid iOS-To. it should be to my tasks by default." The rule was invisible and
    /// the result looked arbitrary, which is the worst combination for a capture box you are
    /// supposed to type into without thinking.
    ///
    /// MY TASKS IS NOT A REAL LIST, so the task is created with NO list ids — the same thing
    /// `makeArgs` does for a virtual selection, and the same thing iOS does. It appears in My
    /// Tasks because it starts assigned to you and that view is "assigned to me" (CONTRACTS D25), not because it was
    /// filed anywhere. It is also where the Mac already lands at launch
    /// (`MacLaunchSelection.landingListId`), so the default destination is now the view you are
    /// most likely looking at rather than an alphabetical accident.
    ///
    /// A consequence worth stating: with no list there are no list defaults to apply — no default
    /// assignee, repeat, privacy or due date. That is not an omission. Inheriting them from a list
    /// the user never named is the bug.
    static func makeGlobalArgs(rawText: String, lists: [TaskList], smartEnabled: Bool = true,
                               priorityOverride: Int? = nil,
                               currentUserId: String? = nil) -> CreateArgs? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // No `!lists.isEmpty` any more: that guard existed only because the fallback needed
        // `lists[0]` to exist. My Tasks needs nothing, and a new account with no lists yet must
        // still be able to capture a thought (AITD-387).
        guard !trimmed.isEmpty else { return nil }

        // The list's defaults apply here too (Task 3d47cb62). This path used to create the task
        // raw, so a task added from the menu bar started differently from the identical task added
        // in the list — same destination, two answers. Defaults come from the DESTINATION list,
        // which is whatever the text named, not simply the first list.
        func defaults(for listIds: [String]) -> TaskList? {
            listIds.first.flatMap { id in lists.first { $0.id == id } }
        }

        guard smartEnabled else {
            let listIds: [String] = []   // My Tasks — see above (AITD-387)
            return applyingDefaults(
                CreateArgs(title: trimmed, listIds: listIds,
                           priority: nil, whenDate: nil, repeating: nil, repeatingData: nil),
                from: defaults(for: listIds), priorityOverride: priorityOverride,
                currentUserId: currentUserId)
        }

        let parsed = SmartTaskParser.parse(trimmed, lists: lists)
        let title = parsed.title.isEmpty ? trimmed : parsed.title
        // Whatever the text named, and nothing if it named nothing (AITD-387).
        let listIds = parsed.listIds

        return applyingDefaults(
            CreateArgs(
                title: title,
                listIds: listIds,
                priority: parsed.priority,
                whenDate: parsed.dueDateTime,
                repeating: parsed.repeating?.rawValue,
                repeatingData: parsed.customRepeatingData
            ),
            from: defaults(for: listIds), priorityOverride: priorityOverride,
            currentUserId: currentUserId)
    }
}
#endif
