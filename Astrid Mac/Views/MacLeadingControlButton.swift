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
        TaskLeadingControl.action(surface: surface, kind: kind, displayMode: displayMode,
                                  currentUserId: AuthManager.shared.userId)
    }

    /// Is this somebody else's task? Decides what the popover carries (AITD-375) — the same
    /// rule the phone uses, from the same place.
    private var isSomeoneElsesTask: Bool {
        TaskLeadingControl.isSomeoneElsesTask(assigneeId: task.assigneeId,
                                              currentUserId: AuthManager.shared.userId)
    }

    var body: some View {
        Button {
            switch tapAction {
            case .complete:   onToggleComplete()
            case .openPicker: isPresented = true
            }
        } label: { face }
            .buttonStyle(.plain)
            .macPointingHand()
            .help(helpText)
            .accessibilityLabel(helpText)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) { picker }
    }

    /// Say what the click does. It used to always read "Priority", which was already only
    /// a third of the truth and is simply wrong when the click completes the task.
    private var helpText: String {
        switch tapAction {
        case .complete:
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
            ForEach(Array(MacLeadingPicker.sections(for: displayMode, surface: surface,
                                                    isSomeoneElses: isSomeoneElsesTask)
                            .enumerated()), id: \.offset) { _, section in
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
                            task: task,
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
                        // Completes, whoever it belongs to (AITD-381). The click that opened this
                        // popover is the one that would otherwise have completed the task, so the
                        // popover is already the deliberate step and a sheet on top of its one
                        // button asked a question that had been answered twice.
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
/// It does NOT invent a list of states. The columns are the core's `taskStatusOptions` — the
/// task's own board, named as the board names them, never Done (CONTRACTS D46) — and the write is
/// the core's move (`TaskService.moveToBoardColumn`), so dropping a task on a state from here does
/// exactly what dragging its card does. A second implementation of "what moving to Done means" is
/// how the two surfaces start disagreeing about completion.
struct MacProjectStateSection: View {
    let task: Task
    let onMoved: () -> Void

    /// The task's columns and which one it is in, from the core — the same answer iOS's picker
    /// reads (AITD-461).
    @ObservedObject private var options = TaskStatusOptions.shared

    private var answer: TaskStatusOptions.Answer? { options.answers[task.id] }
    private var columns: [ProjectBoardColumn] { answer?.columns.map(\.column) ?? [] }
    private var currentColumnId: String? { answer?.current }
    private var askKey: String {
        "\(task.id)|\(task.statusRole ?? "")|\(task.completed)|\(task.listIds ?? [])"
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
        .task(id: askKey) { await options.refresh(task.id) }
    }

    private func move(to column: ProjectBoardColumn) {
        onMoved()
        AppActions.perform("Move task") {
            // The core's move, the task's own board: nothing when it is already there, completion
            // only ever through the completion service (ASTRID.md rule 2). The Mac's detail redraws
            // from the observed `TaskService`, so the returned task is not needed here.
            try await TaskService.shared.moveToBoardColumn(taskId: task.id, columnId: column.id)
            await options.refresh(task.id)
        }
    }
}
#endif
