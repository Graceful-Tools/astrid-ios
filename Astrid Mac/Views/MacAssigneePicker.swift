//  MacAssigneePicker.swift
//  Who a task is assigned to — with faces.
//
//  This was a bare `Picker`, so it showed a name and a stepper and no photo, while the Mac
//  already had MacAssigneeAvatar sitting unused next to it.
//
//  It is a POPOVER of real rows rather than a Menu, for the same reason the priority picker
//  is: AppKit renders menu items in the system's own style, so a custom avatar view in a menu
//  row is not reliably drawn. The control whose entire point is showing a face cannot be a
//  control that refuses to draw one.

#if os(macOS)
import SwiftUI

struct MacAssigneePicker: View {
    let task: Task
    let priority: Task.Priority
    let onSelect: (String?) -> Void

    @State private var showingPicker = false
    /// Who the task can go to — astrid-core's answer, iOS's rule (AITD-461), asked as the
    /// trigger appears and kept app-wide.
    @ObservedObject private var picks = AssigneePicks.shared

    /// Currently assigned id; nil for unassigned.
    private var selectedId: String? {
        if let pickedIds { return pickedIds.first }
        return task.assigneeId?.isEmpty == false ? task.assigneeId : nil
    }
    private var question: AssigneeQuestion { MacAssigneeOptions.question(for: task) }
    private var options: [MacAssigneeOption] {
        MacAssigneeOptions.rows(AssigneePicks.answer(question), currentUserId: AuthManager.shared.userId)
    }

    @ObservedObject private var listService = ListService.shared
    /// Set once a person is clicked on a list that allows several assignees (AITD-491) — the
    /// `task` this view was handed is the one from before the click.
    @State private var pickedIds: [String]?

    /// A GitHub-backed board lets a task hold several people; there a click adds or removes one
    /// and the popover stays open — the same rule as iOS (`AssigneeSelection`).
    private var allowsMultiple: Bool {
        AssigneeSelection.allowsMultiple(listIds: task.listIds ?? [], lists: listService.lists)
    }
    private var selectedIds: [String] { pickedIds ?? AssigneeResolver.assigneeIds(of: task) }
    private func isSelected(_ option: MacAssigneeOption) -> Bool {
        guard allowsMultiple else { return option.userId == selectedId }
        return option.userId.map(selectedIds.contains) ?? selectedIds.isEmpty
    }
    /// Everyone after the primary, as options, so the trigger can draw their faces.
    private var additional: (shown: [MacAssigneeOption], overflow: Int) {
        guard allowsMultiple else { return ([], 0) }
        let faces = AssigneeSelection.additionalFaces(in: selectedIds)
        let shown = faces.shown.map { id in
            options.first { $0.userId == id }
                ?? MacAssigneeOption(userId: id,
                                     user: AssigneeResolver.resolve(id: id, members: [], taskAssignee: nil),
                                     isCurrentUser: id == AuthManager.shared.userId)
        }
        return (shown, faces.overflow)
    }

    private func toggle(_ option: MacAssigneeOption) {
        let agentIds = Set(options.compactMap { $0.user?.isAIAgent == true ? $0.userId : nil })
        let next = AssigneeSelection.toggling(option.userId, in: selectedIds, agentIds: agentIds)
        pickedIds = next
        AppActions.perform("Set assignees") {
            _ = try await TaskService.shared.setAssignees(taskId: task.id, assigneeIds: next)
        }
    }

    /// The trigger shows who holds the task even when they are not one of the choices — someone
    /// assigned from outside the list — resolved from every record the app has (42013da7).
    private var selected: MacAssigneeOption? {
        guard let selectedId else { return nil }
        return options.first { $0.userId == selectedId }
            ?? MacAssigneeOption(userId: selectedId, user: AssigneeResolver.resolve(task: task),
                                 isCurrentUser: selectedId == AuthManager.shared.userId)
    }

    var body: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 6) {
                face(for: selected, size: 20)
                    // Keyed on the assignee: SwiftUI reuses a view whose identity hasn't changed,
                    // which is how the PREVIOUS person's photo used to stay on screen after a
                    // reassign. On the face rather than the button, so removing the primary on a
                    // list with several assignees does not rebuild the open popover (AITD-491).
                    .id(AssigneeResolver.avatarIdentity(for: selectedId))
                // Ask the option for its name rather than spelling the fallback again — the two
                // copies are how this drifted from iOS separately (task 6c891bce).
                Text(selected?.displayName ?? MacAssigneeOption.unassignedLabel)
                    .macFont(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                ForEach(additional.shown) { face(for: $0, size: 20) }
                if additional.overflow > 0 {
                    Text("+\(additional.overflow)")
                        .macFont(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .macFont(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(Color.secondary.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .macPointingHand()
        .help(NSLocalizedString("tasks.assignee", comment: ""))
        // The task has caught up with the clicks, or is a different task: it is the answer again.
        .onChange(of: AssigneeResolver.assigneeIds(of: task)) { pickedIds = nil }
        .onChange(of: task.id) { pickedIds = nil }
        .task(id: question) { await AssigneePicks.ask(question) }
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options) { option in
                    Button {
                        if allowsMultiple {
                            toggle(option)
                        } else {
                            onSelect(option.userId)
                            showingPicker = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            face(for: option, size: 22)
                            Text(option.displayName)
                                .macFont(.system(size: 12))
                                .foregroundStyle(.primary)
                            if option.isCurrentUser {
                                Text(NSLocalizedString("mac.you", comment: "(you)"))
                                    .macFont(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if isSelected(option) {
                                Image(systemName: "checkmark")
                                    .macFont(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .macPointingHand()
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 200)
        }
    }

    /// The avatar, or the unassigned glyph — the same "U" iOS and the task rows use, because
    /// unassigned is a state in its own right rather than an absence.
    @ViewBuilder
    private func face(for option: MacAssigneeOption?, size: CGFloat) -> some View {
        if let user = option?.user {
            MacAssigneeAvatar(user: user, priority: priority, size: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .fill(Color.secondary.opacity(0.15))
                Text(TaskLeadingControl.unassignedGlyph)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25)
                    .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 2)
            )
        }
    }
}
#endif
