//  MacDraftDefaultsPicker.swift
//  Astrid for Mac — the "what will this task start as" options popover (AITD-387).
//
//  ONE PICKER, TWO PLACES. The add bar at the bottom of a list has always had it; the global
//  ⌥Space window had nothing, so the same act — typing a task and pressing Return — offered
//  priority and assignee in one place and not the other. Jon, AITD-387: the quick-add window
//  "should have all the same options as the add task input".
//
//  It was a private `@ViewBuilder` inside MacRootView. Copying it into the quick-add window would
//  have made two pickers to keep in step, which is the thing ASTRID.md rule 8 is about — so it
//  moved here instead and MacRootView now uses this one too.
//
//  THE VIEW IS DUMB ON PURPOSE. It is handed its choices rather than reaching into
//  ListMemberService, because the two callers disagree about where choices come from: the add bar
//  offers the current list's members, and the quick-add window has no list at all. Resolving that
//  in here would mean the view knowing what My Tasks is.

#if os(macOS)
import SwiftUI

/// Someone the next task can be assigned to.
struct MacAssigneeChoice: Identifiable, Equatable {
    let id: String
    let label: String
}

/// The pure half — what the picker offers and what it calls the default.
///
/// Separated from the view so it can be tested: "which name does the default row show" was the
/// part that used to be wrong in a way no build error would catch.
enum MacDraftDefaults {

    /// What the "list default" row should SAY, rather than an abstract "List default" the user
    /// then has to guess at.
    ///
    /// `defaultAssigneeId` is the destination list's default; My Tasks has no list, so it passes
    /// nil and gets "Unassigned" — which is the truth there, and is also why a task added from
    /// the quick-add window shows up in My Tasks at all ("mine or unassigned").
    static func defaultAssigneeLabel(defaultAssigneeId: String?,
                                     currentUserId: String?,
                                     members: [MacAssigneeChoice]) -> String {
        let id = NewTaskDefaults.assignee(defaultAssigneeId, currentUserId: currentUserId)
        guard let id, !id.isEmpty else { return NSLocalizedString("assignee.unassigned", comment: "") }
        if id == currentUserId { return NSLocalizedString("lists.me", comment: "") }
        return members.first { $0.id == id }?.label ?? NSLocalizedString("lists.me", comment: "")
    }

    /// Who the picker offers, beyond "default" and "unassigned".
    ///
    /// With a list, that is its members. WITHOUT one (My Tasks) it is just you — a task with no
    /// list has no membership to draw names from, and offering an empty picker would be a control
    /// that does nothing. Being able to say "this one is mine" is the point of the option there.
    static func assigneeChoices(members: [MacAssigneeChoice],
                                currentUserId: String?,
                                hasList: Bool) -> [MacAssigneeChoice] {
        if hasList { return members }
        guard let currentUserId, !currentUserId.isEmpty else { return [] }
        return [MacAssigneeChoice(id: currentUserId,
                                  label: NSLocalizedString("lists.me", comment: ""))]
    }
}

/// Override the defaults for the NEXT task only — the same idea as iOS's quick-add picker.
struct MacDraftDefaultsPicker: View {
    /// nil = use the default. Set by the priority row.
    @Binding var priorityOverride: Int?
    /// nil = use the default, "unassigned" = explicitly nobody, else a user id.
    @Binding var assigneeOverride: String?

    /// The priority currently in force — the override if there is one, else the destination's.
    let resolvedPriority: Task.Priority
    /// What the default row says the default actually is.
    let defaultAssigneeLabel: String
    /// Who can be picked, from `MacDraftDefaults.assigneeChoices`.
    let assigneeChoices: [MacAssigneeChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("tasks.priority", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)
            // The SAME styled picker the task detail uses — ○ ! !! !!! in their priority colours,
            // not plain text buttons.
            MacPriorityPicker(selection: Binding(
                get: { resolvedPriority },
                set: { priorityOverride = $0.rawValue }
            ))
            Text(NSLocalizedString("tasks.assignee", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)
            Picker("", selection: Binding(
                get: { assigneeOverride ?? "" },
                set: { assigneeOverride = $0.isEmpty ? nil : $0 }
            )) {
                Text(String(format: NSLocalizedString("mac.list_default_is", comment: ""),
                            defaultAssigneeLabel)).tag("")
                Text(NSLocalizedString("assignee.unassigned", comment: "")).tag("unassigned")
                ForEach(assigneeChoices) { choice in Text(choice.label).tag(choice.id) }
            }
            .labelsHidden()
            Divider()
            Button(NSLocalizedString("mac.list_default", comment: "")) {
                priorityOverride = nil
                assigneeOverride = nil
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
#endif
