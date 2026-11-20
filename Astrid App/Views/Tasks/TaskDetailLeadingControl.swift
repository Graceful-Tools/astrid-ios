//  TaskDetailLeadingControl.swift
//  The control at the leading edge of task details — what it shows, and what it holds.
//
//  Extracted from `TaskDetailViewNew` (AITD-363), which was the largest file in the repo and
//  was about to grow again. The Mac has had this as its own view since `MacLeadingControlButton`,
//  and the two are the same idea on two platforms: one control that already DEPICTS priority
//  (its colour) and assignee (whose photo it is), so those are the two things it lets you SET —
//  plus completion, which is what the checkbox always meant.
//
//  Behaviour is unchanged by the extraction. Which of the three things a tap does is decided by
//  the SHARED `TaskLeadingControl.action(surface:kind:currentUserId:)`, never here, so the row, the
//  board card, this screen and the Mac panel cannot answer it four different ways.

import SwiftUI

struct TaskDetailLeadingControl: View {
    let task: Task
    let isCompleted: Bool
    @Binding var priority: Task.Priority
    @Binding var assigneeId: String?
    let listIds: [String]
    let repeating: Task.Repeating?
    /// Dismiss the keyboard before presenting. Otherwise the popover opens above it and the
    /// picker is squeezed into whatever is left (42013da7). The parent owns the focus state.
    let onWillPresent: () -> Void
    let onSaveAssignee: (String?) async -> Void
    let onToggleCompletion: () -> Void
    let onTaskUpdated: (Task) -> Void

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var showingPicker = false

    var body: some View {
        Button {
            onWillPresent()
            // LIST mode: a checkbox completes the task, which is what a checkbox means
            // (task 729a190e). Opening the picker was once unconditional, so in list mode the
            // most familiar gesture in the app did the one thing it does not normally do.
            //
            // Someone else's task opens the popover instead (AITD-375) — that popover IS the
            // deliberate step, which is why completing from it needs nothing further (AITD-381).
            // The shared rule decides which of the two this is; spelling the conditions here is
            // what let the row and the detail disagree about one task in the first place.
            switch leadingControlAction {
            case .complete:   onToggleCompletion()
            case .openPicker: showingPicker = true
            }
        } label: {
            face
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("taskDetail.leadingControl")
        .popover(isPresented: $showingPicker) {
            pickerContent.presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - What it shows

    /// Checkbox, someone else's photo, or the unassigned mark — the same three states the task
    /// row shows, decided by the same helper (42013da7).
    @ViewBuilder private var face: some View {
        if let assignee = effectiveAssignee, showsAssigneeFace {
            Group {
                if showsRepeatFrame {
                    // Repeating: the photo sits inside the repeat arrows (AITD-602).
                    RepeatFramedMark(priority: priority) {
                        assigneePhoto(assignee, initialsSize: 14)
                    }
                } else {
                    assigneePhoto(assignee, initialsSize: 14)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(priorityColor, lineWidth: 2))
                }
            }
            // Keyed on the assignee: SwiftUI reuses a view whose identity has not changed, which
            // is the other half of "the photo didn't change" (42013da7).
            .id(AssigneeResolver.avatarIdentity(for: assigneeId))
            .accessibilityLabel(Text(assignee.displayName))
        } else if leadingKind == .unassigned {
            // Nobody assigned gets "U", the same mark the assignee list uses (42013da7).
            Group {
                if showsRepeatFrame {
                    RepeatFramedMark(priority: priority) {
                        Text(TaskLeadingControl.unassignedGlyph)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(priorityColor)
                    }
                } else {
                    Text(TaskLeadingControl.unassignedGlyph)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(priorityColor)
                        .frame(width: 34, height: 34)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(priorityColor, lineWidth: 2))
                }
            }
            .accessibilityLabel(Text(NSLocalizedString("assignee.unassigned", comment: "")))
        } else {
            checkboxImage
        }
    }

    /// Whether the face or U is drawn inside the repeat arrows (AITD-602). Uses the EDITED
    /// repeat setting, so changing it here redraws the mark straight away.
    private var showsRepeatFrame: Bool {
        TaskLeadingControl.showsRepeatFrame(kind: leadingKind, repeating: repeating)
    }

    private func assigneePhoto(_ assignee: User, initialsSize: CGFloat) -> some View {
        CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Rectangle().fill(Theme.accent)
                Text(assignee.initials)
                    .font(.system(size: initialsSize, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    private var checkboxImage: some View {
        // check_box[_repeat][_checked]_<priority>
        var imageName = "check_box"
        if repeating != nil && repeating != .never { imageName += "_repeat" }
        if isCompleted { imageName += "_checked" }
        imageName += "_\(priority.rawValue)"

        return Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
    }

    // MARK: - What it holds

    @ViewBuilder private var pickerContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Each choice dismisses the popover straight away — you came here to set ONE thing,
            // and leaving it open makes you tap outside to confirm nothing happened (42013da7).
            // Not on a GitHub board with no Priority field: the server refuses that write (AITD-491).
            if TaskCapabilities.allows(.priority, listIds: listIds, lists: listService.lists) {
                PriorityButtonPicker(priority: $priority, onSave: { newPriority in
                    _ = try await taskService.updateTask(taskId: task.id,
                                                         priority: newPriority.rawValue,
                                                         task: task)
                    await MainActor.run { showingPicker = false }
                })
            }

            InlineAssigneePicker(
                label: NSLocalizedString("tasks.assignee", comment: ""),
                assigneeId: $assigneeId,
                taskListIds: listIds,
                taskId: task.id,
                availableLists: listService.lists,
                onSave: { newAssigneeId in
                    await onSaveAssignee(newAssigneeId)
                    await MainActor.run { showingPicker = false }
                },
                showLabel: false
            )

            // Board state, for someone else's task (AITD-375). Your own task's detail already
            // has its priority and assignee as rows, and its board state as a row on a board.
            if TaskLeadingControl.pickerShowsProjectState(surface: .detail,
                                                          assigneeId: assigneeId,
                                                          currentUserId: AuthManager.shared.currentUser?.id) {
                Divider()
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    Text(NSLocalizedString("board.project_state", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(Theme.textMuted)
                    ProjectStateQuickPicker(task: task,
                                            onMoved: { showingPicker = false },
                                            onTaskUpdated: onTaskUpdated)
                }
            }

            Divider()

            // A task that is not yours — someone else's or nobody's — opens on the question
            // itself: the checkbox, then Complete (ADEV-79; ADEV-70, web ADEV-56). Reopening and
            // your own tasks never ask.
            if TaskLeadingControl.completionNeedsConfirmation(
                assigneeId: assigneeId,
                currentUserId: AuthManager.shared.currentUser?.id,
                completed: isCompleted) {
                CompletionConfirmationPrompt(
                    assigneeLabel: CompletionConfirmation.assigneeLabel(for: task, assigneeId: assigneeId),
                    onCancel: { showingPicker = false },
                    onConfirm: {
                        showingPicker = false
                        onToggleCompletion()
                    })
            } else {
            MarkDoneQuickSetRow(completed: isCompleted) {
                showingPicker = false
                onToggleCompletion()
            }
            }
        }
        .padding(Theme.spacing16)
        .frame(width: 320)
    }

    // MARK: - The shared rules, asked rather than spelled

    private var leadingKind: TaskLeadingControl {
        TaskLeadingControl.kind(assigneeId: assigneeId,
                                currentUserId: AuthManager.shared.currentUser?.id)
    }

    /// What tapping does here: complete, open the picker, or ask first.
    ///
    /// The whole action rather than a `completes` boolean, so a new case cannot collapse
    /// silently into "not complete, so open the picker". Mirrors the Mac's
    /// `MacLeadingControlButton`.
    private var leadingControlAction: TaskLeadingControlAction {
        TaskLeadingControl.action(surface: .detail,
                                  kind: leadingKind,
                                  currentUserId: AuthManager.shared.currentUser?.id)
    }

    /// Whether the leading control is a face rather than a checkbox or the unassigned mark.
    private var showsAssigneeFace: Bool {
        if case .avatar = leadingKind { return true }
        return false
    }

    /// The assignee to depict — the full object when we have it, otherwise a minimal User built
    /// from the id so UserImageCache can still resolve a photo (same as TaskRowView).
    private var effectiveAssignee: User? {
        // No member list here — the picker fetches its own — so the resolver falls through to
        // the task's assignee, then to a minimal User that UserImageCache can still supply a
        // photo for.
        AssigneeResolver.resolve(id: assigneeId, members: [], taskAssignee: task.assignee,
                                 agents: AIAgentCache.shared.load() ?? [])
    }

    private var priorityColor: Color {
        switch priority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }
}
