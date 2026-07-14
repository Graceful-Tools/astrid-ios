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
    @State private var selectedTaskId: String?

    private var tasksForSelection: [Task] {
        guard let id = selectedListId else { return [] }
        return taskService.getTasksForList(id)
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
                    List(tasksForSelection, selection: $selectedTaskId) { task in
                        HStack(spacing: 8) {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? .green : .secondary)
                            Text(task.title).strikethrough(task.completed)
                            Spacer()
                            if let due = task.dueDateTime {
                                Text(due, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(task.id))
                    }
                }
            }
            .navigationTitle(listService.lists.first { $0.id == selectedListId }?.name ?? "Tasks")
            .navigationSplitViewColumnWidth(min: 320, ideal: 440)
        } detail: {
            if let id = selectedTaskId, let task = tasksForSelection.first(where: { $0.id == id }) {
                MacTaskDetailView(task: task)
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

/// Minimal native task detail (M1). Grows into inline editing in M2.
struct MacTaskDetailView: View {
    let task: Task

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(task.title).font(.title2).bold()
                if let due = task.dueDateTime {
                    Label { Text(due, style: .date) } icon: { Image(systemName: "calendar") }
                }
                Label {
                    Text(task.completed ? "Completed" : "Open")
                } icon: {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
