//  CommandPaletteView.swift
//  Astrid for Mac — ⌘K command palette / quick-open (M2, expanded in Task 5003c622).
//  Searches registered commands, lists, and open tasks; tasks can be opened or completed.

#if os(macOS)
import SwiftUI

struct CommandPaletteView: View {
    let registry: CommandRegistry
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var query = ""
    @State private var selection: String?
    @Environment(\.dismiss) private var dismiss

    private enum Row: Identifiable {
        case command(AppCommand)
        case list(TaskList)
        case task(Task)
        var id: String {
            switch self {
            case .command(let c): return "cmd:\(c.id)"
            case .list(let l): return "list:\(l.id)"
            case .task(let t): return "task:\(t.id)"
            }
        }
    }

    private var allTasks: [Task] { listService.lists.flatMap { taskService.getTasksForList($0.id) } }

    private var rows: [Row] {
        var out = registry.search(query).map { Row.command($0) }
        out += MacPaletteSearch.matchingLists(query, lists: listService.lists).map { Row.list($0) }
        out += MacPaletteSearch.matchingTasks(query, tasks: allTasks).map { Row.task($0) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(NSLocalizedString("mac.palette_placeholder", comment: ""), text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(16)
                .onSubmit(runSelectedOrFirst)
            Divider()
            List(rows, selection: $selection) { row in
                rowView(row).tag(row.id).contentShape(Rectangle()).onTapGesture { run(row) }
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 400)
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .command(let c):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title)
                    if let sub = c.subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let s = c.shortcut { Text(s).font(.callout).foregroundStyle(.secondary) }
            }
        case .list(let l):
            Label { Text(l.name) } icon: { Image(systemName: "list.bullet") }
        case .task(let t):
            HStack {
                Label { Text(t.title) } icon: { Image(systemName: "circle") }
                Spacer()
                Button(NSLocalizedString("reminders.complete", comment: "")) { complete(t) }.buttonStyle(.borderless).font(.caption)
            }
        }
    }

    private func runSelectedOrFirst() {
        if let id = selection, let row = rows.first(where: { $0.id == id }) { run(row) }
        else if let first = rows.first { run(first) }
    }

    private func run(_ row: Row) {
        switch row {
        case .command(let c): c.run()
        case .list(let l): MacAppModel.shared.openList(l.id)
        case .task(let t): MacAppModel.shared.openTask(listId: t.listIds?.first, taskId: t.id)
        }
        dismiss()
    }

    private func complete(_ t: Task) {
        MacActions.perform("Complete task") { _ = try await taskService.completeTask(id: t.id, completed: true, task: t) }
        dismiss()
    }
}
#endif
