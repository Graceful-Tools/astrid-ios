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

    private var list: TaskList? { listService.lists.first { $0.id == listId } }
    private var boardEnabled: Bool { MacBoardControl.isEnabled(projectId: list?.projectId) }
    private var columns: [ProjectBoardColumn] { getProjectBoardColumns(listService.lists) }
    private var tasks: [Task] { taskService.getTasksForList(listId) }

    /// One-pass column grouping (6042bde0): hoists getProjectStatusLists out of the per-task path.
    /// Was O(columns × tasks × lists) — tasks(in:) per column, each task rescanning all lists.
    private func groupTasksByColumn() -> [String: [Task]] {
        let statusLists = getProjectStatusLists(listService.lists)
        var buckets: [String: [Task]] = [:]
        for t in tasks {
            buckets[getTaskProjectColumnId(t, statusLists: statusLists), default: []].append(t)
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
                HStack(alignment: .top, spacing: 12) {
                    let buckets = groupTasksByColumn()   // ONE pass over tasks (6042bde0)
                    ForEach(columns) { col in columnView(col, items: buckets[col.id] ?? []) }
                }
                .padding()
            }
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
        .frame(width: 250, alignment: .leading)
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
        MacActions.perform("Add card") {
            let created = try await taskService.createTask(listIds: [listId], title: title)
            let (ids, complete) = MacBoardAdd.apply(MacBoardMove.plan(task: created, column: col, lists: listService.lists))
            if let ids { _ = try await taskService.updateTask(taskId: created.id, listIds: ids, task: created) }
            if complete { _ = try await taskService.completeTask(id: created.id, completed: true, task: created) }
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

                // Close or expand, in one place (7017c3c1). The caret collapses the card, and
                // directly beneath it — only while open, which is when it means anything — the
                // full-screen control. These were at opposite ends of a card whose height changes
                // with its content, so the way out and the way further in were nowhere near
                // each other.
                VStack(alignment: .trailing, spacing: 6) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(Theme.textMuted)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleExpanded(t) }
                    if expanded {
                        Button {
                            withAnimation(MacMotion.fast) { detailFullScreen = true }
                            MacAppModel.shared.openTask(listId: listId, taskId: t.id)
                        } label: {
                            Image(systemName: MacDetailPresentation.fullScreenSymbol(isFullScreen: false))
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textMuted)
                        .macPointingHand()
                        .help(NSLocalizedString(
                            MacDetailPresentation.fullScreenTooltipKey(isFullScreen: false), comment: ""))
                        .accessibilityIdentifier("boardCard.fullScreen")
                    }
                }
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
        .draggable(t.id)
    }

    // MARK: moves

    private func move(taskId: String, to col: ProjectBoardColumn) {
        guard let task = tasks.first(where: { $0.id == taskId }) else { return }
        let plan = MacBoardMove.plan(task: task, column: col, lists: listService.lists)
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
        MacActions.perform("Complete task") {
            _ = try await taskService.completeTask(id: t.id, completed: !t.completed, task: t)
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
        // Same shape as the detail panel's save: skip a write that changes nothing, since the
        // picker notifies on every tap including one on the priority already set.
        guard priority != t.priority else { priorityDraft[t.id] = nil; return }
        MacActions.perform("Set priority") {
            _ = try await taskService.updateTask(taskId: t.id, priority: priority.rawValue, task: t)
            // The task is the truth again; drop the draft so a later change to this task from
            // anywhere else is not shadowed by a stale local value.
            priorityDraft[t.id] = nil
        }
    }

    private func setAssignee(_ t: Task, _ assigneeId: String?) {
        MacActions.perform("Set assignee") {
            _ = try await taskService.updateTask(taskId: t.id, assigneeId: assigneeId ?? "", task: t)
        }
    }
}
#endif
