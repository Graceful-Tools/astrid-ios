//  MacMenuBarView.swift
//  Astrid for Mac — menu-bar extra: glanceable tasks + quick add (v1.1).

#if os(macOS)
import SwiftUI

struct MacMenuBarView: View {
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @State private var quickText = ""
    @Environment(\.openWindow) private var openWindow

    /// Open, undated-or-soon tasks across the first few lists (cache-backed glance).
    private var openTasks: [Task] {
        listService.lists.flatMap { taskService.getTasksForList($0.id) }
            .filter { !$0.completed }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Quick add…", text: $quickText).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(quickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Divider()
            if openTasks.isEmpty {
                Text("No open tasks").foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                ForEach(openTasks) { task in
                    Button {
                        _Concurrency.Task { _ = try? await taskService.completeTask(id: task.id, completed: true, task: task) }
                    } label: {
                        Label(task.title, systemImage: "circle").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button("Open Astrid") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func add() {
        let parsed = QuickEntryParser.parse(quickText)
        guard !parsed.title.isEmpty, let listId = listService.lists.first?.id else { return }
        _Concurrency.Task { _ = try? await taskService.createTask(listIds: [listId], title: parsed.title) }
        quickText = ""
    }
}
#endif
