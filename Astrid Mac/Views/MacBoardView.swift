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

    private var columns: [ProjectBoardColumn] { getProjectBoardColumns(listService.lists) }
    private var tasks: [Task] { taskService.getTasksForList(listId) }

    private func tasks(in column: ProjectBoardColumn) -> [Task] {
        tasks.filter { getTaskProjectColumnId($0, lists: listService.lists) == column.id }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { col in
                    columnView(col)
                }
            }
            .padding()
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

    private func card(_ t: Task) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { toggleComplete(t) } label: {
                Image(systemName: t.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(t.completed ? Theme.success : Theme.textMuted)
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
