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
    @State private var hoveredCardId: String?    // Mac hover affordance (77225941)

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
            ForEach(items) { t in card(t) }
            Spacer(minLength: 40)
            addCardField(col)          // floats at the bottom of the column (iPad/web placement)
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
                Button { toggleComplete(t) } label: {
                    MacTaskCheckbox(completed: t.completed, priority: t.priority, size: 18,
                                    repeating: MacCheckboxAsset.isRepeating(t.repeating))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).foregroundStyle(Theme.textPrimary).strikethrough(t.completed)
                    if let due = t.dueDateTime {
                        Text(due, style: .date).font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2).foregroundStyle(Theme.textMuted)
            }
            // Click the card body → expand INLINE to edit (like Astrid Web), not open the panel.
            // Springs open/closed instead of jumping (4c7b9f08).
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(MacMotion.spring) {
                    expandedCardId = MacBoardExpand.toggle(current: expandedCardId, tapped: t.id)
                }
            }

            if expanded {
                Divider()
                MacBoardCardEditor(task: t,
                                   onOpenPanel: { MacAppModel.shared.openTask(listId: listId, taskId: t.id) },
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
            case .setLists(let ids):
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task)
            case .complete(let ids):
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task)
                _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
            case .uncomplete(let ids):
                _ = try await taskService.completeTask(id: task.id, completed: false, task: task)
                _ = try await taskService.updateTask(taskId: task.id, listIds: ids, task: task)
            }
        }
    }

    private func toggleComplete(_ t: Task) {
        MacActions.perform("Complete task") {
            _ = try await taskService.completeTask(id: t.id, completed: !t.completed, task: t)
        }
    }
}
#endif
