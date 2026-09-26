//  MacQuickAddBar.swift
//  Astrid for Mac — the Add-a-task bar, shared by the list column and every board column
//  (Task AITD-431).
//
//  It lived inside MacRootView as `quickAddBar`, and the board had a second way to add: a bare
//  "+ Add task" TextField at the foot of each column, with no list defaults, no smart parsing, no
//  defaults picker and no ⊕. The board then ALSO drew the list's bar under the whole board
//  (e466eab8), so there were two boxes that disagreed about what a new task would be. One view
//  now serves both; a board column passes its column, and the card is born in it.

#if os(macOS)
import SwiftUI

struct MacQuickAddBar: View {
    enum Style {
        /// The list column's floating card — lifted, with a row's outer margins.
        case list
        /// Inside a board column — the same card, fitted to the column.
        case boardColumn
    }

    /// The list selection it adds into (`nil` = nothing selected).
    let selectedListId: String?
    /// My Tasks or a saved filter: not a real list, so never attached as a list id.
    let selectionIsVirtual: Bool
    /// The real list behind the selection, whose defaults the new task takes.
    let list: TaskList?
    /// Set on a board: the column the card should be born in, role and all (AITD-328).
    var column: ProjectBoardColumn? = nil
    var style: Style = .list
    /// Whether the caret belongs here right now (MacAddTaskBar.shouldTakeFocus), re-asked on
    /// appear and whenever `focusKey` changes.
    var takesFocus = false
    var focusKey: String = ""
    /// ⊕ adds the task AND opens it (iOS / web parity); Return just adds.
    var onOpen: ((Task) -> Void)? = nil

    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var memberService = ListMemberService.shared
    @State private var draftTitle = ""
    /// Priority the user picked on the checkbox for the NEXT task. nil = follow the list's default
    /// (iOS behaves the same: the checkbox shows the default and can override it).
    @State private var draftPriorityOverride: Int?
    @State private var draftAssigneeOverride: String?      // "" = explicitly no one
    @State private var showDraftDefaults = false
    @FocusState private var focused: Bool

    var body: some View {
        // iOS QuickAddTaskView layout (task 022701f3): checkbox on the LEFT, the bordered input in
        // the middle, and the add ⊕ on the RIGHT — the + used to be a decoration inside the field
        // on the left, with no way to commit by clicking. The surface stays themed (chrome silver
        // on Ocean, black on Dark) with a lift shadow, matching 5b41942a.
        let bar = HStack(alignment: .center, spacing: style == .list ? 12 : 8) {
            // The leading control mirrors a task ROW: the priority-coloured checkbox for the
            // defaults this task will get, or the assignee's avatar when it is going to someone
            // else. Tapping it opens the override picker.
            //
            // NOTE: this is a plain view + tap, NOT a `Menu` with a custom label — that collapsed
            // the label and the checkbox disappeared from the add row entirely.
            Group {
                if let assignee = draftAssignee {
                    MacAssigneeAvatar(user: assignee, priority: draftPriority,
                                      size: MacTaskVisuals.rowCheckboxSize)
                } else {
                    MacTaskCheckbox(completed: false, priority: draftPriority,
                                    size: MacTaskVisuals.rowCheckboxSize,
                                    // The add-row previews what the task will be, repeat
                                    // included — the list's default repeat (ca13c94b).
                                    repeating: draftRepeats)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showDraftDefaults = true }
            .macPointingHand()
            .help(NSLocalizedString("tasks.priority", comment: ""))
            .popover(isPresented: $showDraftDefaults, arrowEdge: .top) {
                draftDefaultsPicker
            }

            // Wraps + expands vertically for long titles (a02a6819); Return still commits.
            TextField(NSLocalizedString("mac.quick_add_placeholder", comment: ""), text: $draftTitle, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(MacTypography.rowTitle)
                .macTextSelection()
                .focused($focused)
                .onSubmit { commitDraft() }
                // The caret was unreachable except by clicking the field: the FocusState was
                // bound here and set by nothing, which is "add task didn't always have a cursor
                // prompt" (b71850e6). WHEN it takes focus is MacAddTaskBar's rule; the caller
                // evaluates it and says so through `takesFocus`.
                // Focus on appear, exactly as b71850e6 set it up — the caret is not delayed and no
                // keystroke is lost. Focusing is what summons macOS's empty AutoFill popover, so
                // the watch that closes it starts alongside (AITD-333). The watch owns its own
                // state and is idempotent: SwiftUI rebuilds this field during launch, and hanging
                // the timer off the view's lifecycle meant `onDisappear` killed it before it ever
                // ticked once.
                .onAppear {
                    if takesFocus { focused = true }
                    MacStrayAutoFillPanel.beginLaunchWatch()
                }
                .onChange(of: focusKey) { if takesFocus { focused = true } }
                .accessibilityLabel(NSLocalizedString("tasks.add_task_placeholder", comment: ""))
                .accessibilityIdentifier(style == .list ? "tasks.quickAdd" : "board.quickAdd")

            // The list's default DUE DATE, previewed (Task 3d47cb62). Priority, repeat and assignee
            // already show on the checkbox; the date was applied silently, so the first you knew of
            // it was the task appearing with a date you never typed. Absent when the list has none.
            if let due = MacQuickAddPreview.dueDateLabel(for: list) {
                HStack(spacing: 3) {
                    Image(systemName: "calendar")
                    Text(due)
                }
                .font(MacTypography.rowMeta)
                .foregroundStyle(Theme.textSecondary)
                .help(NSLocalizedString("lists.due_date", comment: ""))
                .accessibilityIdentifier("tasks.quickAdd.defaultDueDate")
            }

            // Right: ⊕ commits the draft (iOS parity); dimmed and inert while empty.
            // ⊕ adds the task AND opens its details (iOS / web parity); Return just adds.
            Button { commitDraft(openDetails: true) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(style == .list ? .title2 : .title3)
                    .foregroundStyle(MacQuickAdd.isCommittable(draftTitle) ? Theme.accent : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!MacQuickAdd.isCommittable(draftTitle))
            .macPointingHand()
            .help(NSLocalizedString("tasks.new_task", comment: ""))
        }
        // ONE input card holding the checkbox, the field and ⊕ (iOS / web parity). The internal
        // padding matches MacTaskRow's card, so the quick-add checkbox sits in the same column as
        // the checkboxes of the rows above it.
        .padding(.horizontal, style == .list ? 12 : 8).padding(.vertical, style == .list ? 9 : 6)
        // The SAME surface a task row card uses (white on Light/Ocean) rather than the grey input
        // fill — the add row should read as a task card you are about to fill in, like iOS.
        .background(MacSelectionStyle.fill(isSelected: false), in: RoundedRectangle(cornerRadius: style == .list ? 10 : 6))
        .overlay(RoundedRectangle(cornerRadius: style == .list ? 10 : 6).stroke(Theme.inputBorder, lineWidth: 0.5))

        switch style {
        case .list:
            bar
                // The lift shadow falls AWAY from the rows: down when the card leads the list, up
                // when it trails.
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: MacAddTaskBar.placement == .top ? 2 : -2)
                .frame(maxWidth: .infinity)
                // Same outer margin as a row CARD: the rows sit inside an inset List, so matching
                // their 8pt card padding alone left the add row wider than the rows above it.
                .padding(.horizontal, MacLayout.rowTrailingGap)
                .padding(.vertical, 8)
                .macTextSelection()
        case .boardColumn:
            // The column is already the frame; the cards above it carry no lift either.
            bar.frame(maxWidth: .infinity).macTextSelection()
        }
    }

    // MARK: - Draft defaults

    /// The assignee the next task will get — the override, else the list's default. nil means it
    /// stays with the creator, which is drawn as a checkbox rather than an avatar (row parity).
    private var draftAssignee: User? {
        let id = draftAssigneeOverride
            ?? NewTaskDefaults.assignee(list?.defaultAssigneeId, currentUserId: auth.userId)
        // Unassigned, or assigned to ME, draws as the CHECKBOX — exactly like a task row. Only a
        // task headed to someone ELSE shows an avatar.
        guard let id, !id.isEmpty, id != auth.userId else { return nil }
        // Only show an avatar for someone we can actually name: a synthesised User with no name
        // rendered as "??", which is not a person (task follow-up).
        return listMembers.first { $0.userId == id }?.user
    }

    /// What "list default" resolves to for the Who row, so the picker states the real outcome
    /// rather than an abstract label.
    private var listDefaultAssigneeLabel: String {
        // The shared rule (AITD-387), so the add bar and the ⌥Space window cannot describe the
        // same default with two different words.
        MacDraftDefaults.defaultAssigneeLabel(defaultAssigneeId: list?.defaultAssigneeId,
                                              currentUserId: auth.userId,
                                              members: listMemberChoices)
    }

    /// Members of the list, for the assignee picker.
    private var listMembers: [ListMember] {
        list.flatMap { memberService.membersByList[$0.id] } ?? []
    }

    /// Override the defaults for the NEXT task only — the same idea as iOS's quick-add picker.
    ///
    /// The picker itself is `MacDraftDefaultsPicker` (AITD-387) so the global ⌥Space window can
    /// offer the same options instead of a second copy of them. What stays here is the part that
    /// is genuinely about THIS bar: the choices come from its list's members.
    @ViewBuilder private var draftDefaultsPicker: some View {
        MacDraftDefaultsPicker(
            priorityOverride: $draftPriorityOverride,
            assigneeOverride: $draftAssigneeOverride,
            resolvedPriority: draftPriority,
            defaultAssigneeLabel: listDefaultAssigneeLabel,
            assigneeChoices: MacDraftDefaults.assigneeChoices(
                members: listMemberChoices, currentUserId: auth.userId, hasList: true))
    }

    /// The list's members, as picker choices.
    private var listMemberChoices: [MacAssigneeChoice] {
        listMembers.map { MacAssigneeChoice(id: $0.userId,
                                            label: $0.user?.displayName ?? $0.userId) }
    }

    /// Whether a task added right now would repeat — i.e. the list carries a default repeat.
    /// The checkbox previews it, the same way it previews the default priority.
    private var draftRepeats: Bool {
        NewTaskDefaults.repeating(list?.defaultRepeating) != nil
    }

    /// The priority the checkbox displays: the user's override if they picked one, otherwise the
    /// destination list's default.
    private var draftPriority: Task.Priority {
        let raw = draftPriorityOverride
            ?? NewTaskDefaults.priority(list?.defaultPriority)
            ?? 0
        return Task.Priority(rawValue: raw) ?? .none
    }

    // MARK: - Commit

    /// Commit the draft. Empty text creates nothing (no junk tasks).
    /// - Parameter openDetails: ⊕ opens the new task's details (iOS / web); Return does not.
    private func commitDraft(openDetails: Bool = false) {
        let lists = ListService.shared.lists
        guard var args = MacQuickAdd.makeArgs(rawText: draftTitle, selectedListId: selectedListId,
                                              lists: lists,
                                              smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled,
                                              selectionIsVirtual: selectionIsVirtual,
                                              priorityOverride: draftPriorityOverride,
                                              currentUserId: auth.userId) else { return }
        // A board column: born in the column it was typed into, role and all (AITD-328). It used
        // to be created bare and then moved, and the move dropped the role — so a card typed into
        // Doing resolved to Inbox and appeared there.
        var statusRole: String?
        var complete = false
        if let column, let domainListId = selectedListId {
            let card = MacBoardAdd.newCard(in: column, domainListId: domainListId, lists: lists)
            args = MacBoardAdd.placing(args, in: card)
            statusRole = card.statusRole
            complete = card.complete
        }
        draftTitle = ""
        if MacAddTaskBar.retainsFocusAfterCommit { focused = true }
        let assigneeOverride = draftAssigneeOverride
        draftPriorityOverride = nil          // the overrides apply to one task, like iOS
        draftAssigneeOverride = nil
        AppActions.perform(column == nil ? "Add task" : "Add card") {
            let created = try await TaskService.shared.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate,
                assigneeId: assigneeOverride == "unassigned" ? nil : (assigneeOverride ?? args.assigneeId),
                isPrivate: args.isPrivate,
                repeating: args.repeating, repeatingData: args.repeatingData,
                statusRole: statusRole)
            // Done goes through completeTask, never updateTask(completed:) — the only path that
            // rolls a repeating task forward (ASTRID.md §0 rule 2).
            if complete {
                _ = try await TaskService.shared.completeTask(id: created.id, completed: true, task: created)
            }
            if openDetails { onOpen?(created) }
        }
    }
}
#endif
