//  MacBoardView.swift
//  Astrid for Mac — project-status board (Task 196d482a). Columns are the shared
//  [Inbox, …status lists, Done] contract (getProjectBoardColumns); cards drag between columns
//  via Transferable and move through the shared services. Replaces the old priority board.

#if os(macOS)
import SwiftUI

struct MacBoardView: View {
    let listId: String
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    /// Observed so the board redraws when a project's custom columns arrive (AITD-379).
    @StateObject private var projectService = ProjectService.shared
    @StateObject private var appModel = MacAppModel.shared
    @State private var dropTargetColumnId: String?
    @State private var draftByColumn: [String: String] = [:]
    @State private var boardBusy = false
    @State private var expandedCardId: String?   // inline expand-to-edit (efaf8120)
    /// Shared with the detail panel and its header toggle, so "full screen" means one
    /// thing app-wide (7017c3c1).
    @AppStorage("macDetailFullScreen") private var detailFullScreen = false
    @State private var hoveredCardId: String?    // Mac hover affordance (77225941)
    @StateObject private var memberService = ListMemberService.shared
    /// Priority being picked on a card, before the save lands (task 9be8cb1b).
    ///
    /// `MacPriorityPicker` WRITES its binding as well as calling `onSelect`, so a read-only
    /// binding would leave the swatch showing the old value for the instant the popover is still
    /// up. Cleared on save, after which the task itself is the truth again.
    @State private var priorityDraft: [String: Task.Priority] = [:]
    /// The last priority this board WROTE per task, as opposed to the one a card was rendered
    /// with. Only a repeat of this is worth suppressing.
    @State private var lastWrittenPriority: [String: Task.Priority] = [:]

    /// The board's own width, measured — the columns divide it (AITD-330).
    @State private var boardWidth: CGFloat = 0

    /// For the card menu's "Open in new window" — the same action the list row offers (AITD-372).
    @Environment(\.openWindow) private var openWindow

    /// What each column gets: an equal share of the room, never below the floor.
    private var columnWidth: CGFloat {
        MacLayout.boardColumnWidth(columnCount: columns.count, availableWidth: boardWidth)
    }

    private var list: TaskList? { listService.lists.first { $0.id == listId } }
    private var boardEnabled: Bool { MacBoardControl.isEnabled(projectId: list?.projectId) }
    /// This board's own custom columns (AITD-379) — keyed off the selected
    /// list's project, since that is what makes this a board at all.
    private var customStates: [ProjectCustomState]? {
        projectService.customStates(projectId: list?.projectId)
    }
    private var columns: [ProjectBoardColumn] {
        getProjectBoardColumns(listService.lists, customStates: customStates)
    }
    private var tasks: [Task] { taskService.getTasksForList(listId) }

    /// One-pass column grouping (6042bde0): builds the columns once, out of the per-task path.
    /// Was O(columns × tasks × lists) — tasks(in:) per column, each task rescanning all lists.
    private func groupTasksByColumn() -> [String: [Task]] {
        let columns = self.columns
        var buckets: [String: [Task]] = [:]
        for t in tasks {
            buckets[getTaskProjectColumnId(t, columns: columns), default: []].append(t)
        }
        return buckets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if boardEnabled {
                    Menu {
                        Button(NSLocalizedString("mac.disable_board", comment: ""), role: .destructive) { disableBoard() }
                    } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
                } else {
                    Button { enableBoard() } label: {
                        HStack { Label(NSLocalizedString("mac.enable_board", comment: ""), systemImage: "square.grid.2x2")
                            if boardBusy { ProgressView().controlSize(.small) } }
                    }
                    .disabled(boardBusy)
                    .help(NSLocalizedString("mac.board_create_columns_hint", comment: ""))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: MacLayout.boardColumnSpacing) {
                    let buckets = groupTasksByColumn()   // ONE pass over tasks (6042bde0)
                    ForEach(columns) { col in columnView(col, items: buckets[col.id] ?? []) }
                }
                .padding(MacLayout.boardPadding)
            }
            // The columns share whatever room the board has, down to their minimum — below that
            // this still scrolls, exactly as it did when the width was fixed (AITD-330).
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
            .macScrollBars(showScrollBars)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bgPrimary)   // pervasive theme background (Ocean cyan) behind the board
        // The card's leading control offers an assignee picker (task 9be8cb1b), and it can only
        // list people it knows about. Fetching here rather than relying on another screen having
        // opened the members sheet first, which is not something the board can assume.
        .task(id: listId) { try? await memberService.fetchMembers(listId: listId) }
    }

    private func enableBoard() {
        guard let list else { return }
        boardBusy = true
        MacActions.perform("Enable board") {
            defer { boardBusy = false }
            _ = try await ProjectService.shared.createBoardForList(list)
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func disableBoard() {
        guard let projectId = list?.projectId else { return }
        MacActions.perform("Disable board") {
            _ = try await ProjectService.shared.deleteProject(id: projectId)
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func columnView(_ col: ProjectBoardColumn, items: [Task]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(col.name).font(.headline).foregroundStyle(Theme.textSecondary)
                Text("\(items.count)").font(.caption).foregroundStyle(Theme.textMuted)
            }
            .help(col.description)
            // The CARDS scroll, not the board. Without this the column was a plain stack of
            // every card, so a long column simply grew past the bottom of the window and took
            // the whole board with it — the header and the add-card field went with it and
            // there was no way to reach them (task e508ae5b).
            //
            // Lazy, because a column is exactly the place a list gets long.
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { t in card(t) }
                }
            }
            .macScrollBars(showScrollBars)
            .scrollContentBackground(.hidden)
            // Takes the room left over between the header and the add field, so those two
            // stay put at the top and bottom of the column instead of scrolling away.
            .frame(maxHeight: .infinity)
            addCardField(col)          // stays at the bottom of the column (iPad/web placement)
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(dropTargetColumnId == col.id ? Theme.accent.opacity(0.15) : Theme.bgTertiary.opacity(0.4)))
        .animation(MacMotion.fast, value: dropTargetColumnId)   // drop-target highlight eases (4c7b9f08)
        .dropDestination(for: String.self) { items, _ in
            guard let taskId = items.first else { return false }
            move(taskId: taskId, to: col)
            return true
        } isTargeted: { dropTargetColumnId = $0 ? col.id : nil }
    }

    /// Inline "＋ Add task" footer per column (iOS/web parity). Creates in the domain list, then
    /// places the card into this column via the shared board move plan.
    @ViewBuilder private func addCardField(_ col: ProjectBoardColumn) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(Theme.textMuted).font(.caption)
            TextField(NSLocalizedString("tasks.add_task", comment: ""), text: Binding(
                get: { draftByColumn[col.id] ?? "" },
                set: { draftByColumn[col.id] = $0 }
            ))
            .textFieldStyle(.plain)
            .onSubmit { addCard(to: col) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgPrimary.opacity(0.6)))
    }

    private func addCard(to col: ProjectBoardColumn) {
        let title = (draftByColumn[col.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        draftByColumn[col.id] = ""
        let spec = MacBoardAdd.newCard(in: col, domainListId: listId, lists: listService.lists)
        MacActions.perform("Add card") {
            // Born in the column it was typed into, role and all (AITD-328). It used to be
            // created bare and then moved, and the move dropped the role — so a card typed into
            // Doing resolved to Inbox and appeared there.
            let created = try await taskService.createTask(listIds: spec.listIds, title: title,
                                                          statusRole: spec.statusRole)
            // Done goes through completeTask, never updateTask(completed:) — the only path that
            // rolls a repeating task forward (ASTRID.md §0 rule 2).
            if spec.complete {
                _ = try await taskService.completeTask(id: created.id, completed: true, task: created)
            }
        }
    }

    private func card(_ t: Task) -> some View {
        let expanded = expandedCardId == t.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // The SAME control the detail panel uses (task 9be8cb1b). This was a button whose
                // only action was complete, which made the most prominent thing on a card a
                // trapdoor: the click that reads as "pick this one" finished the task.
                //
                // The control already depicts priority (its colour) and assignee (whose photo),
                // so those are what it should let you set — the argument `MacLeadingControlButton`
                // was written for. Adopting it rather than copying it is the point: a second
                // implementation is exactly how the board and the panel came to disagree.
                MacLeadingControlButton(
                    task: t,
                    priority: priorityBinding(t),
                    members: members,
                    surface: .boardCard,
                    onPriority: { setPriority(t, $0) },
                    onAssignee: { setAssignee(t, $0) },
                    onToggleComplete: { toggleComplete(t) }
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).foregroundStyle(Theme.textPrimary).strikethrough(t.completed)
                    if let due = t.dueDateTime {
                        Text(due, style: .date).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Click the card body → expand INLINE to edit (like Astrid Web), not open the
                // panel. Springs open/closed instead of jumping (4c7b9f08). The gesture is on the
                // TITLE area rather than the whole header now, so the expand button beside the
                // caret is not swallowed by it.
                .contentShape(Rectangle())
                .onTapGesture { toggleExpanded(t) }

                // The caret, alone (AITD-377, matching web's AWTD-872). Full screen used to sit
                // directly beneath it whenever the card was open — two controls stacked in a
                // gutter this narrow, which is the clutter Jon asked about. It moved into the
                // card's right-click menu, where every other secondary action already lives.
                //
                // Collapse stayed a button on purpose: it undoes the click that expanded the
                // card, so burying it would make expanding feel like a trap. Web kept it for the
                // same reason.
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(Theme.textMuted)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded(t) }
            }

            if expanded {
                Divider()
                MacBoardCardEditor(task: t,
                                   onDone: { withAnimation(MacMotion.spring) { expandedCardId = nil } })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Expanded card is a WHITE details surface (like web); collapsed cards stay on the theme
        // with a hover wash (77225941).
        .background(expanded ? MacDetailChrome.background
                             : MacSelectionStyle.fill(isSelected: false, hovering: hoveredCardId == t.id))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Subtle selection border (b8d1ec16) — thin accent when expanded, hover-hairline otherwise.
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(MacSelectionStyle.borderColor(isSelected: expanded, hovering: hoveredCardId == t.id),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: expanded)))
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hoveredCardId = h ? t.id : (hoveredCardId == t.id ? nil : hoveredCardId) } }
        // Right-click gets the SAME actions as a list row (AITD-372). Rendered from the shared
        // model rather than restated here, so the board cannot fall behind the row: a card had no
        // context menu at all while the row had nine actions.
        //
        // Before `.draggable`, so the menu wins the right-click. A card is a drag source, and a
        // drag gesture attached first swallows the secondary click on the way past.
        .contextMenu {
            MacTaskRowMenuContent(
                task: t,
                surface: .boardCard,
                lists: listService.lists,
                currentListId: listId,
                actions: MacTaskRowMenuActions(
                    toggleComplete: { toggleComplete(t) },
                    // A card has no inline title field; its expanded editor does. Same intent,
                    // one layer down — better than dropping Rename from the card's menu.
                    rename: { if expandedCardId != t.id { toggleExpanded(t) } },
                    setPriority: { setPriority(t, $0) },
                    move: { moveToList(t, $0) },
                    copyToList: { copyTask(t, to: $0) },
                    share: { shareTask(t) },
                    copyToPasteboard: {
                        MacTaskActions.copyToPasteboard(
                            MacTaskActions.clipboardText(title: t.title, shareURL: nil))
                    },
                    openInNewWindow: { openWindow(id: "task", value: t.id) },
                    delete: { deleteTask(t) },
                    fullScreen: { openFullScreen(t) }
                )
            )
        }
        .draggable(t.id)
    }

    // MARK: moves

    private func move(taskId: String, to col: ProjectBoardColumn) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        let plan = MacBoardMove.plan(task: task, column: col,
                                     lists: listService.lists, customStates: customStates)
        MacActions.perform("Move task") {
            switch plan {
            case .none:
                break
            case .setLists(let ids, let role):
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task, statusRole: role)
            case .complete(let ids, let role):
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task, statusRole: role)
                _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
            case .uncomplete(let ids, let role):
                _ = try await taskService.completeTask(id: task.id, completed: false, task: task)
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task, statusRole: role)
            }
        }
    }

    /// Open or close the card. Both the title area and the caret call this, so tapping either does
    /// the same thing — the caret is the visible affordance, the title is the large target.
    private func toggleExpanded(_ t: Task) {
        withAnimation(MacMotion.spring) {
            expandedCardId = MacBoardExpand.toggle(current: expandedCardId, tapped: t.id)
        }
    }

    private func toggleComplete(_ t: Task) {
        // Recorded for ⌘Z, as the list row has always done. A card that completes a task without
        // an undo step is the same click with less of a way back (AITD-372).
        MacUndoCoordinator.shared.record(MacUndo.completeStep(previous: [t.id: t.completed],
                                                             to: !t.completed))
        MacActions.perform("Complete task") {
            _ = try await taskService.completeTask(id: t.id, completed: !t.completed, task: t)
        }
    }

    // MARK: - The card menu's remaining actions (AITD-372)
    //
    // Each is the SAME service call the list row's menu makes, undo step included, so the two
    // menus cannot mean different things by the same word.

    /// Move to another LIST — distinct from `move(taskId:to:)` above, which moves between the
    /// board's own columns.
    private func moveToList(_ t: Task, _ targetListId: String) {
        MacUndoCoordinator.shared.record(
            MacUndo.moveStep(previous: [t.id: t.listIds ?? []], to: targetListId))
        MacActions.perform("Move task") {
            _ = try await taskService.updateTask(taskId: t.id, listIds: [targetListId], task: t)
        }
    }

    private func copyTask(_ t: Task, to targetListId: String?) {
        MacActions.perform("Copy task") {
            _ = try await taskService.copyTask(id: t.id, targetListId: targetListId,
                                               includeComments: true)
        }
    }

    /// Open this task filling the content area — the action that used to be the second button in
    /// the card's gutter (AITD-377). Unchanged in what it does: set the app-wide full-screen flag
    /// and select the task, so `MacDetailPresentation` renders the pane over the board.
    private func openFullScreen(_ t: Task) {
        withAnimation(MacMotion.fast) { detailFullScreen = true }
        MacAppModel.shared.openTask(listId: listId, taskId: t.id)
    }

    private func shareTask(_ t: Task) {
        MacActions.perform("Share task") {
            if let url = try await MacTaskActions.makeShareURL(taskId: t.id) {
                MacTaskActions.presentShareSheet(url: url, relativeTo: nil)
            }
        }
    }

    private func deleteTask(_ t: Task) {
        // Collapse first: leaving the editor open over a card that is on its way out renders an
        // editor for a task that no longer exists.
        if expandedCardId == t.id { expandedCardId = nil }
        MacUndoCoordinator.shared.record(MacUndo.deleteStep(
            snapshots: MacUndoCoordinator.shared.deletionSnapshots(for: [t],
                                                                   allTasks: taskService.tasks)))
        MacActions.perform("Delete task") {
            try await taskService.deleteTask(id: t.id, task: t)
        }
    }

    // MARK: - The leading control's three actions (task 9be8cb1b)

    /// Members of the list this board belongs to, for the assignee picker. Empty until the fetch
    /// below lands, and an empty picker is honest about that — it offers only Unassigned rather
    /// than pretending nobody exists.
    private var members: [ListMember] { memberService.membersByList[listId] ?? [] }

    private func priorityBinding(_ t: Task) -> Binding<Task.Priority> {
        Binding(get: { priorityDraft[t.id] ?? t.priority },
                set: { priorityDraft[t.id] = $0 })
    }

    private func setPriority(_ t: Task, _ priority: Task.Priority) {
        // Asked of the shared rule, which does NOT consult `t.priority`. Comparing the tap
        // against the card's snapshot is what stalled this: whichever priority the card was
        // rendered with became a dead button, and the draft was wiped so it snapped back.
        let outcome = MacBoardPriorityTap.tap(priority, lastWritten: lastWrittenPriority[t.id])

        // The card shows what was pressed, always — even when there is nothing to write.
        priorityDraft[t.id] = outcome.draft

        guard let write = outcome.write else { return }
        lastWrittenPriority[t.id] = write
        MacActions.perform("Set priority") {
            _ = try await taskService.updateTask(taskId: t.id, priority: write.rawValue, task: t)
            // Only if this write is still the newest thing the user asked for: clearing
            // unconditionally discarded a tap made while this one was in flight.
            priorityDraft[t.id] = MacBoardPriorityTap.draftAfterWriting(
                write, currentDraft: priorityDraft[t.id])
        }
    }

    private func setAssignee(_ t: Task, _ assigneeId: String?) {
        MacActions.perform("Set assignee") {
            _ = try await taskService.updateTask(taskId: t.id, assigneeId: assigneeId ?? "", task: t)
        }
    }
}
#endif
