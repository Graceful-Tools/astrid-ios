//  MacRootView.swift
//  Astrid for Mac — three-column shell wired to the SHARED services (M1).
//
//  Sidebar = ListService.shared.lists; content = TaskService.shared.getTasksForList(...);
//  detail = a native Mac task detail. No task/list logic here — reads flow from the shared
//  services (the same ones iOS uses), writes go back through TaskService.

#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @StateObject private var appModel = MacAppModel.shared
    @State private var selectedListId: String?
    @State private var selectedTaskIds = Set<String>()

    private var tasksForSelection: [Task] {
        guard let id = selectedListId else { return [] }
        return taskService.getTasksForList(id)
    }

    /// Complete every selected task through the canonical service (repeat rollover honored).
    private func completeSelected() {
        let toComplete = tasksForSelection.filter { selectedTaskIds.contains($0.id) && !$0.completed }
        for task in toComplete {
            _Concurrency.Task { _ = try? await taskService.completeTask(id: task.id, completed: true, task: task) }
        }
        selectedTaskIds.removeAll()
    }

    var body: some View {
        NavigationSplitView {
            List(listService.lists, selection: $selectedListId) { list in
                Label(list.name, systemImage: "list.bullet").tag(Optional(list.id))
            }
            .navigationTitle("Astrid")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } content: {
            Group {
                if selectedListId == nil {
                    ContentUnavailableView("Select a list", systemImage: "sidebar.left")
                } else if tasksForSelection.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                } else {
                    Table(tasksForSelection, selection: $selectedTaskIds) {
                        TableColumn("") { task in
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? .green : .secondary)
                        }.width(24)
                        TableColumn("Task") { task in
                            Text(task.title).strikethrough(task.completed)
                        }
                        TableColumn("Due") { task in
                            if let due = task.dueDateTime { Text(due, style: .date) }
                            else { Text("—").foregroundStyle(.secondary) }
                        }.width(min: 90, ideal: 120)
                        TableColumn("Priority") { task in
                            Text(String(describing: task.priority)).foregroundStyle(.secondary)
                        }.width(min: 70, ideal: 90)
                    }
                    .toolbar {
                        if selectedTaskIds.count > 1 {
                            ToolbarItem(placement: .primaryAction) {
                                Button { completeSelected() } label: {
                                    Label("Complete \(selectedTaskIds.count)", systemImage: "checkmark.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(listService.lists.first { $0.id == selectedListId }?.name ?? "Tasks")
            .navigationSplitViewColumnWidth(min: 360, ideal: 500)
        } detail: {
            if selectedTaskIds.count == 1,
               let task = tasksForSelection.first(where: { selectedTaskIds.contains($0.id) }) {
                MacTaskDetailView(task: task)
            } else if selectedTaskIds.count > 1 {
                ContentUnavailableView("\(selectedTaskIds.count) tasks selected", systemImage: "checklist")
            } else {
                ContentUnavailableView("Select a task", systemImage: "square.and.pencil")
            }
        }
        .task {
            // Hydrate lists from the shared service (cache-first, offline-safe).
            _ = try? await listService.fetchLists()
        }
        .sheet(isPresented: $appModel.showPalette) {
            CommandPaletteView(registry: appModel.registry)
        }
    }
}

/// Native task detail with inline editing (M2) + tear-off (M2/v1.1).
struct MacTaskDetailView: View {
    let task: Task
    @State private var editedTitle = ""
    @Environment(\.openWindow) private var openWindow
    private var taskService: TaskService { .shared }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $editedTitle)
                    .font(.title3)
                    .onSubmit(commitTitle)
                Toggle("Completed", isOn: Binding(
                    get: { task.completed },
                    set: { setCompleted($0) }
                ))
                if let due = task.dueDateTime {
                    LabeledContent("Due") { Text(due, style: .date) }
                }
                LabeledContent("Priority") { Text(String(describing: task.priority)) }
            }
            Section {
                Button {
                    openWindow(id: "task", value: task.id)
                } label: {
                    Label("Open in New Window", systemImage: "macwindow.on.rectangle")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { editedTitle = task.title }
        .onChange(of: task.id) { editedTitle = task.title }
    }

    private func commitTitle() {
        let t = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != task.title else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, title: t) }
    }

    private func setCompleted(_ value: Bool) {
        _Concurrency.Task { _ = try? await taskService.completeTask(id: task.id, completed: value, task: task) }
    }
}

/// A torn-off single-task window (opened by id via openWindow(id: "task", value:)).
struct MacTaskWindowView: View {
    let taskId: String?
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared

    private var task: Task? {
        guard let id = taskId else { return nil }
        return listService.lists.lazy.compactMap { list in
            taskService.getTasksForList(list.id).first { $0.id == id }
        }.first
    }

    var body: some View {
        if let task {
            MacTaskDetailView(task: task).frame(minWidth: 360, minHeight: 300)
        } else {
            ContentUnavailableView("Task not found", systemImage: "questionmark.square.dashed")
        }
    }
}
#endif
