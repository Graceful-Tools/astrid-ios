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
    /// WHERE this control is drawn. Required rather than defaulted, for the same reason
    /// `TaskLeadingControl.kind` requires the mode: the board and the panel disagree about
    /// exactly one thing, and a default would let a new call site pick the panel's answer
    /// silently — which is how the board came to complete tasks again (task f9d7ed42).
    let surface: TaskLeadingControlSurface
    let onPriority: (Task.Priority) -> Void
    let onAssignee: (String?) -> Void
    let onToggleComplete: () -> Void

    @State private var isPresented = false
    /// Confirming completion of a task assigned to someone else (AITD-363).
    @State private var isConfirmingCompletion = false
    @StateObject private var userSettings = UserSettingsService.shared

    private var kind: TaskLeadingControl {
        TaskLeadingControl.kind(assigneeId: task.assigneeId,
                                currentUserId: AuthManager.shared.userId,
                                displayMode: displayMode)
    }

    private var displayMode: TaskDisplayMode {
        TaskDisplayMode(stored: userSettings.settings.taskDisplayMode)
    }

    /// Asked of the SHARED rule rather than spelled here, so the board card, the list row and
    /// this panel cannot answer it three different ways (task f9d7ed42). What that rule says
    /// for this surface, and why, lives with the rule.
    ///
    /// The whole action rather than a `tapCompletes` boolean (AITD-363): someone else's photo
    /// in the panel now asks before completing, and a boolean carrying two answers would have
    /// folded that third one silently back into "open the picker" — the Mac quietly doing
    /// something else than the phone for the same task, which is what sharing the rule prevents.
    private var tapAction: TaskLeadingControlAction {
        TaskLeadingControl.action(surface: surface, kind: kind, displayMode: displayMode)
    }

    var body: some View {
        Button {
            switch tapAction {
            case .complete:          onToggleComplete()
            case .openPicker:        isPresented = true
            case .confirmCompletion: isConfirmingCompletion = true
            }
        } label: { face }
            .buttonStyle(.plain)
            .macPointingHand()
            .help(helpText)
            .accessibilityLabel(helpText)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { picker }
            // "Complete this task?" / "Assigned to {name}" — it NAMES the assignee, because a
            // dialog asking about "this task" over an unlabelled photo is the blind confirm
            // that teaches people to accept without reading.
            .confirmationDialog(NSLocalizedString("tasks.confirm_complete_title", comment: ""),
                                isPresented: $isConfirmingCompletion) {
                Button(NSLocalizedString("tasks.complete_task", comment: "")) { onToggleComplete() }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(String(format: NSLocalizedString("tasks.confirm_complete_assigned", comment: ""),
                            assigneeDisplayName))
            }
    }

    /// Who the confirmation names. Resolved through the SHARED resolver — the same one the face
    /// above uses — so the dialog names the person whose photo was actually tapped.
    private var assigneeDisplayName: String {
        guard case .avatar(let userId) = kind,
              let user = AssigneeResolver.resolve(id: userId,
                                                  members: members.compactMap(\.user),
                                                  taskAssignee: task.assignee,
                                                  agents: AIAgentCache.shared.load() ?? [])
        else { return NSLocalizedString("assignee.unassigned", comment: "") }
        return user.displayName
    }

    /// Say what the click does. It used to always read "Priority", which was already only
    /// a third of the truth and is simply wrong when the click completes the task.
    private var helpText: String {
        switch tapAction {
        case .complete, .confirmCompletion:
            return task.completed
                ? NSLocalizedString("mac.mark_incomplete", comment: "")
                : NSLocalizedString("tasks.complete_task", comment: "")
        case .openPicker:
            return NSLocalizedString("tasks.priority", comment: "")
        }
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
            ForEach(Array(MacLeadingPicker.sections(for: displayMode, surface: surface).enumerated()), id: \.offset) { _, section in
                switch section {
                case .priority:
                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("tasks.priority", comment: ""))
                            .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                        // The real buttons, in their priority colours — not a Menu,
                        // which AppKit would draw in the system's own style and lose
                        // the colours that ARE the information.
                        // Per-tap callback, NOT `.onChange(of: priority)`: watching for a
                        // value change swallowed the tap that picked the priority the task
                        // already had — no save, and the popover sat there looking dead
                        // (task a6cd1367).
                        MacPriorityPicker(selection: $priority, onSelect: { newValue in
                            onPriority(newValue)
                            isPresented = false
                        })
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
                case .projectState:
                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("board.project_state", comment: ""))
                            .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                        MacProjectStateSection(task: task, onMoved: { isPresented = false })
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

/// The board-column choice inside the quick changer (task 729a190e).
///
/// Self-contained rather than another callback threaded through every construction of the
/// leading control: both the board card and the detail panel build that control, and neither
/// of them has anything to add to this decision.
///
/// It does NOT invent a list of states. The columns come from `getProjectBoardColumns`, the
/// same derivation the board itself uses, so a renamed "Ready" reads the same in both places —
/// and the write goes through `MacBoardMove.plan`, so dropping a task on Done from here
/// completes it exactly as dragging it there does. A second implementation of "what moving to
/// Done means" is how the two surfaces start disagreeing about completion.
struct MacProjectStateSection: View {
    let task: Task
    let onMoved: () -> Void

    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared

    /// Every state EXCEPT Done (task 7574067b) — the same filter iOS uses, so the two
    /// pickers cannot come to disagree about what a state is.
    private var columns: [ProjectBoardColumn] {
        ProjectStatePicker.columns(from: getProjectBoardColumns(listService.lists))
    }

    private var currentColumnId: String {
        getTaskProjectColumnId(task, lists: listService.lists)
    }

    var body: some View {
        // Wrapping, like every other chip row in the detail — a project can have more
        // columns than fit on one line, and truncating them hides states you can move to.
        FlowLayout(spacing: 6, rowSpacing: 6) {
            ForEach(columns) { column in
                Button { move(to: column) } label: {
                    Text(column.name)
                        .font(MacTypography.label)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(column.id == currentColumnId
                                  ? Theme.accent.opacity(0.22) : Theme.bgTertiary))
                        .foregroundStyle(column.id == currentColumnId
                                         ? Theme.accent : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .macPointingHand()
                .accessibilityLabel(column.name)
            }
        }
    }

    private func move(to column: ProjectBoardColumn) {
        onMoved()
        guard column.id != currentColumnId else { return }
        let plan = planProjectColumnMove(task: task, column: column, lists: listService.lists)
        MacActions.perform("Move task") {
            // Same sequencer as the iOS picker (AITD-352), including ASTRID.md rule 2 —
            // completion only ever through `completeTask`. The Mac discards the returned task:
            // its detail view is handed one derived from the observed `TaskService` and redraws
            // on its own, which is exactly why this bug was iOS-only.
            _ = try await ProjectStateMove.apply(
                plan: plan,
                update: { ids, role in
                    try await taskService.updateTask(taskId: task.id, listIds: ids,
                                                     task: task, statusRole: role)
                },
                complete: { flag in
                    try await taskService.completeTask(id: task.id, completed: flag, task: task)
                }
            )
        }
    }
}
#endif
