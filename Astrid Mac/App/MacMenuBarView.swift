//  MacMenuBarView.swift
//  Astrid for Mac — menu-bar extra: glanceable tasks + quick add (v1.1).

#if os(macOS)
import SwiftUI

struct MacMenuBarView: View {
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @State private var quickText = ""
    @Environment(\.openWindow) private var openWindow

    /// Open tasks across lists, most-relevant first (due date, then priority) — not an arbitrary slice.
    private var openTasks: [Task] {
        listService.lists.flatMap { taskService.getTasksForList($0.id) }
            .filter { !$0.completed }
            .sorted { a, b in
                let ad = a.dueDateTime ?? .distantFuture, bd = b.dueDateTime ?? .distantFuture
                if ad != bd { return ad < bd }
                return a.priority.rawValue > b.priority.rawValue
            }
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
        // Shared SmartTaskParser (dates/priority/#lists/repeat), same engine as the main window +
        // sidebar. Global context (no current list) → makeGlobalArgs (Task 8c7e5968, fa267754).
        guard let args = MacQuickAdd.makeGlobalArgs(rawText: quickText, lists: listService.lists,
                                                    smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled) else { return }
        quickText = ""
        _Concurrency.Task {
            _ = try? await taskService.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate, repeating: args.repeating, repeatingData: args.repeatingData)
        }
    }
}
#endif
