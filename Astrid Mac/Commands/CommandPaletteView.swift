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

    private typealias Row = CommandPaletteRow

    private var rows: [Row] {
        CommandPaletteRow.rows(query: query, registry: registry, lists: listService.lists,
                               tasks: MacGlanceTasks.all(lists: listService.lists,
                                                         tasksForList: taskService.getTasksForList))
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(NSLocalizedString("mac.palette_placeholder", comment: ""), text: $query)
                .textFieldStyle(.plain)
                .macFont(.title2)
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
                    if let sub = c.subtitle { Text(sub).macFont(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if let s = c.shortcut { Text(s).macFont(.callout).foregroundStyle(.secondary) }
            }
        case .list(let l):
            Label { Text(l.name) } icon: { Image(systemName: "list.bullet") }
        case .task(let t):
            HStack {
                Label { Text(t.title) } icon: { Image(systemName: "circle") }
                Spacer()
                Button(NSLocalizedString("reminders.complete", comment: "")) { complete(t) }.buttonStyle(.borderless).macFont(.caption)
            }
        }
    }

    private func runSelectedOrFirst() {
        let rows = self.rows
        guard let id = CommandPalettePick.rowToRun(selection: selection, rowIds: rows.map(\.id)),
              let row = rows.first(where: { $0.id == id }) else { return }
        run(row)
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
        AppActions.perform("Complete task") { _ = try await taskService.completeTask(id: t.id, completed: true, task: t) }
        dismiss()
    }
}
/// One row of the ⌘K palette.
enum CommandPaletteRow: Identifiable {
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

    /// What the palette shows for `query`: commands, then lists, then tasks — each ranked by the
    /// core's `paletteRank` (AITD-667). A task id is the most specific thing the box can hold, so
    /// its task leads and Return opens it (AITD-565).
    static func rows(query: String, registry: CommandRegistry, lists: [TaskList],
                     tasks: [Task]) -> [CommandPaletteRow] {
        let commands = registry.search(query).map { CommandPaletteRow.command($0) }
        let listRows = MacPaletteSearch.matchingLists(query, lists: lists).map { CommandPaletteRow.list($0) }
        let taskRows = MacPaletteSearch.matchingTasks(query, tasks: tasks).map { CommandPaletteRow.task($0) }
        if MacPaletteSearch.identifierMatch(query, tasks: tasks.filter { !$0.completed }) != nil {
            return taskRows + commands + listRows
        }
        return commands + listRows + taskRows
    }
}

/// Return in the palette runs the selected row — or the first, when nothing is selected or the
/// selection has filtered away (AITD-540).
enum CommandPalettePick {
    static func rowToRun(selection: String?, rowIds: [String]) -> String? {
        if let selection, rowIds.contains(selection) { return selection }
        return rowIds.first
    }
}
#endif
