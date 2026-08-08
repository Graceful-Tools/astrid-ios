//  MacLeadingControlButton.swift
//  Astrid for Mac — the control at the leading edge of a task, and what it holds.
//
//  It already depicts priority (its colour) and assignee (whose photo it is), so
//  those are the two things it should let you SET. A separate "Priority" row
//  restating both was spending a fifth of a 380pt panel to say what the control
//  beside it was already saying. iOS reached this first (42013da7); this is the
//  Mac inheriting it, down to the same three sections.
//
//  Which state the control depicts comes from the SHARED `TaskLeadingControl`,
//  so a task cannot look like one thing on the Mac and another on the phone.

#if os(macOS)
import SwiftUI

struct MacLeadingControlButton: View {
    let task: Task
    @Binding var priority: Task.Priority
    let members: [ListMember]
    let onPriority: (Task.Priority) -> Void
    let onAssignee: (String?) -> Void
    let onToggleComplete: () -> Void

    @State private var isPresented = false

    private var kind: TaskLeadingControl {
        TaskLeadingControl.kind(assigneeId: task.assigneeId,
                                currentUserId: AuthManager.shared.userId)
    }

    var body: some View {
        Button { isPresented = true } label: { face }
            .buttonStyle(.plain)
            .macPointingHand()
            .help(NSLocalizedString("tasks.priority", comment: ""))
            .accessibilityLabel(NSLocalizedString("tasks.priority", comment: ""))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { picker }
    }

    /// Checkbox, someone else's photo, or the unassigned mark — the same three
    /// states the task row shows.
    @ViewBuilder private var face: some View {
        switch kind {
        case .checkbox:
            MacTaskCheckbox(completed: task.completed, priority: priority,
                            size: MacTaskVisuals.detailCheckboxSize,
                            repeating: MacCheckboxAsset.isRepeating(task.repeating ?? .never))
        case .avatar(let userId):
            // Resolved through the SHARED resolver, so the photo the Mac shows is the
            // one iOS shows for the same task.
            if let user = AssigneeResolver.resolve(id: userId,
                                                   members: members.compactMap(\.user),
                                                   taskAssignee: task.assignee,
                                                   agents: AIAgentCache.shared.load() ?? []) {
                MacAssigneeAvatar(user: user, priority: priority,
                                  size: MacTaskVisuals.detailCheckboxSize)
            } else {
                MacTaskCheckbox(completed: task.completed, priority: priority,
                                size: MacTaskVisuals.detailCheckboxSize,
                                repeating: MacCheckboxAsset.isRepeating(task.repeating ?? .never))
            }
        case .unassigned:
            // The same mark the assignee list uses, so what you PICK is what you SEE.
            Text(TaskLeadingControl.unassignedGlyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacTaskVisuals.priorityColor(priority))
                .frame(width: MacTaskVisuals.detailCheckboxSize,
                       height: MacTaskVisuals.detailCheckboxSize)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 1.5))
                .accessibilityLabel(NSLocalizedString("assignee.unassigned", comment: ""))
        }
    }

    @ViewBuilder private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MacLeadingPicker.sections.enumerated()), id: \.offset) { _, section in
                switch section {
                case .priority:
                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("tasks.priority", comment: ""))
                            .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                        // The real buttons, in their priority colours — not a Menu,
                        // which AppKit would draw in the system's own style and lose
                        // the colours that ARE the information.
                        MacPriorityPicker(selection: $priority)
                            .onChange(of: priority) { _, newValue in
                                onPriority(newValue)
                                isPresented = false
                            }
                    }
                case .assignee:
                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("tasks.assignee", comment: ""))
                            .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                        MacAssigneePicker(
                            options: MacAssigneeOptions.build(
                                members: members,
                                currentUserId: AuthManager.shared.userId,
                                taskAssignee: task.assignee),
                            selectedId: task.assigneeId,
                            priority: priority,
                            onSelect: { onAssignee($0); isPresented = false }
                        )
                    }
                case .complete:
                    Divider()
                    Button {
                        isPresented = false
                        onToggleComplete()
                    } label: {
                        Label(task.completed
                              ? NSLocalizedString("mac.mark_incomplete", comment: "")
                              : NSLocalizedString("tasks.complete_task", comment: ""),
                              systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .macPointingHand()
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
#endif
