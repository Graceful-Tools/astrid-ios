//  MacBoardView.swift
//  Astrid for Mac — project-status board (Task 196d482a). Columns are the shared
//  [Inbox, …status lists, Done] contract (getProjectBoardColumns); cards drag between columns
//  via Transferable and move through the shared services. Replaces the old priority board.

#if os(macOS)
import SwiftUI

struct MacBoardView: View {
    let listId: String
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var dropTargetColumnId: String?
    @State private var draftByColumn: [String: String] = [:]
    @State private var boardBusy = false

    private var list: TaskList? { listService.lists.first { $0.id == listId } }
    private var boardEnabled: Bool { MacBoardControl.isEnabled(projectId: list?.projectId) }
    private var columns: [ProjectBoardColumn] { getProjectBoardColumns(listService.lists) }
    private var tasks: [Task] { taskService.getTasksForList(listId) }

    private func tasks(in column: ProjectBoardColumn) -> [Task] {
        tasks.filter { getTaskProjectColumnId($0, lists: listService.lists) == column.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if boardEnabled {
                    Menu {
                        Button("Disable Board", role: .destructive) { disableBoard() }
                    } label: { Image(systemName: "ellipsis.circle") }.fixedSize()
                } else {
                    Button { enableBoard() } label: {
                        HStack { Label("Enable Board", systemImage: "square.grid.2x2")
                            if boardBusy { ProgressView().controlSize(.small) } }
                    }
                    .disabled(boardBusy)
                    .help("Create Ready / Doing / Waiting status columns for this list")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { col in columnView(col) }
                }
                .padding()
            }
        }
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

    private func columnView(_ col: ProjectBoardColumn) -> some View {
        let items = tasks(in: col)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(col.name).font(.headline).foregroundStyle(Theme.textSecondary)
                Text("\(items.count)").font(.caption).foregroundStyle(Theme.textMuted)
            }
            .help(col.description)
            ForEach(items) { t in card(t) }
            addCardField(col)
            Spacer(minLength: 40)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(dropTargetColumnId == col.id ? Theme.accent.opacity(0.15) : Theme.bgTertiary.opacity(0.4)))
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
            TextField("Add task", text: Binding(
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
        HStack(alignment: .top, spacing: 8) {
            Button { toggleComplete(t) } label: {
                MacTaskCheckbox(completed: t.completed, priority: t.priority, size: 18)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).foregroundStyle(Theme.textPrimary).strikethrough(t.completed)
                if let due = t.dueDateTime {
                    Text(due, style: .date).font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { MacAppModel.shared.openTask(listId: listId, taskId: t.id) }
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
