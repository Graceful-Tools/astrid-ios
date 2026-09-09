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
//  the SHARED `TaskLeadingControl.action(surface:kind:displayMode:)`, never here, so the row, the
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
    /// Observed, so changing the mode in Appearance redraws an open detail rather than waiting
    /// for it to be reopened.
    @StateObject private var userSettings = UserSettingsService.shared

    @State private var showingPicker = false
    /// Confirming completion of a task assigned to someone else (AITD-363).
    @State private var showingCompleteForAssigneePrompt = false

    var body: some View {
        Button {
            onWillPresent()
            // LIST mode: a checkbox completes the task, which is what a checkbox means
            // (task 729a190e). Opening the picker was once unconditional, so in list mode the
            // most familiar gesture in the app did the one thing it does not normally do.
            //
            // Someone else's task opens the popover instead (AITD-375) — the confirmation now
            // sits on the popover's Complete button, not on this tap. The shared rule decides
            // which of the two this is; spelling the conditions here is what let the row and the
            // detail disagree about one task in the first place.
            switch leadingControlAction {
            case .complete:   onToggleCompletion()
            case .openPicker: showingPicker = true
            }
        } label: {
            face
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker) {
            pickerContent.presentationCompactAdaptation(.popover)
        }
        // "Complete this task?" / "Assigned to {name}" (AITD-363).
        //
        // It NAMES the assignee. A dialog asking about "this task" over an unlabelled photo is
        // the blind confirmation that teaches people to accept without reading, which would hand
        // back the hazard the confirmation exists to remove.
        .confirmationDialog(
            NSLocalizedString("tasks.confirm_complete_title", comment: "Complete this task?"),
            isPresented: $showingCompleteForAssigneePrompt,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("tasks.complete_task", comment: "Complete the task")) {
                onToggleCompletion()
            }
            Button(NSLocalizedString("actions.cancel", comment: "Cancel"), role: .cancel) {}
        } message: {
            if let assignee = effectiveAssignee {
                Text(String(format: NSLocalizedString("tasks.confirm_complete_assigned",
                                                      comment: "Assigned to {name}"),
                            assignee.displayName))
            }
        }
    }

    // MARK: - What it shows

    /// Checkbox, someone else's photo, or the unassigned mark — the same three states the task
    /// row shows, decided by the same helper (42013da7).
    @ViewBuilder private var face: some View {
        if let assignee = effectiveAssignee, showsAssigneeFace {
            CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.accent)
                    Text(assignee.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(priorityColor, lineWidth: 2))
            // Keyed on the assignee: SwiftUI reuses a view whose identity has not changed, which
            // is the other half of "the photo didn't change" (42013da7).
            .id(AssigneeResolver.avatarIdentity(for: assigneeId))
            .accessibilityLabel(Text(assignee.displayName))
        } else if leadingKind == .unassigned {
            // Nobody assigned gets "U", the same mark the assignee list uses (42013da7).
            Text(TaskLeadingControl.unassignedGlyph)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(priorityColor)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(priorityColor, lineWidth: 2))
                .accessibilityLabel(Text(NSLocalizedString("assignee.unassigned", comment: "")))
        } else {
            checkboxImage
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
            PriorityButtonPicker(priority: $priority, onSave: { newPriority in
                _ = try await taskService.updateTask(taskId: task.id,
                                                     priority: newPriority.rawValue,
                                                     task: task)
                await MainActor.run { showingPicker = false }
            })

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

            // Board state, in PROJECT mode only (task 729a190e) — the third thing the quick
            // changer holds. List mode does not offer it: priority and assignee are rows of
            // their own there, and a board column is a project idea. Offering it in both would
            // rebuild the hybrid layout this setting exists to end.
            if TaskLeadingControl.pickerShowsProjectState(displayMode: displayMode,
                                                          surface: .detail,
                                                          isSomeoneElses: needsCompletionConfirmation) {
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

            Button {
                showingPicker = false
                // Not yours? Ask first (AITD-375). Finishing another person's work is one tap
                // from the control you opened this with, and it is not undoable in place.
                if needsCompletionConfirmation { showingCompleteForAssigneePrompt = true }
                else { onToggleCompletion() }
            } label: {
                Label(isCompleted ? NSLocalizedString("mac.mark_incomplete", comment: "")
                                  : NSLocalizedString("tasks.complete_task", comment: ""),
                      systemImage: isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                    .font(Theme.Typography.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacing16)
        .frame(width: 320)
    }

    // MARK: - The shared rules, asked rather than spelled

    private var displayMode: TaskDisplayMode {
        TaskDisplayMode(stored: userSettings.settings.taskDisplayMode)
    }

    private var leadingKind: TaskLeadingControl {
        TaskLeadingControl.kind(assigneeId: assigneeId,
                                currentUserId: AuthManager.shared.currentUser?.id,
                                displayMode: displayMode)
    }

    /// What tapping does here: complete, open the picker, or ask first.
    ///
    /// The whole action rather than a `completes` boolean, so a new case cannot collapse
    /// silently into "not complete, so open the picker". Mirrors the Mac's
    /// `MacLeadingControlButton`.
    private var leadingControlAction: TaskLeadingControlAction {
        TaskLeadingControl.action(surface: .detail,
                                  kind: leadingKind,
                                  displayMode: displayMode,
                                  currentUserId: AuthManager.shared.currentUser?.id)
    }

    /// Whether finishing this task should ask first — i.e. it belongs to someone else.
    ///
    /// Also decides whether the popover carries board state, because "not yours" is what turns
    /// this into the full project-mode set of choices (AITD-375).
    private var needsCompletionConfirmation: Bool {
        TaskLeadingControl.completionNeedsConfirmation(
            assigneeId: assigneeId,
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
