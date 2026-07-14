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
    @StateObject private var auth = AuthManager.shared
    @StateObject private var network = NetworkMonitor.shared
    @State private var selectedListId: String?
    @State private var selectedTaskIds = Set<String>()
    @State private var showNewList = false
    @State private var editingList: TaskList?
    @State private var sharingList: TaskList?
    @State private var listToDelete: TaskList?

    private func toggleFavorite(_ list: TaskList) {
        _Concurrency.Task {
            _ = try? await listService.toggleFavorite(listId: list.id, isFavorite: !(list.isFavorite ?? false))
        }
    }
    private func deleteList(_ list: TaskList) {
        _Concurrency.Task {
            try? await listService.deleteList(listId: list.id)
            if selectedListId == list.id { selectedListId = nil }
        }
    }

    private var accountMenu: some View {
        Menu {
            if let u = auth.currentUser {
                Text(u.name ?? u.email ?? "Account")
                Divider()
            }
            Button("Sign Out") {
                _Concurrency.Task { try? await auth.signOut() }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }
    }

    private var tasksForSelection: [Task] {
        guard let id = selectedListId else { return [] }
        return taskService.getTasksForList(id)
    }

    /// Create a task in the selected list and select it for full editing (C2).
    private func newTask() {
        guard let listId = selectedListId else { return }
        _Concurrency.Task {
            if let created = try? await taskService.createTask(listIds: [listId], title: "New Task") {
                await MainActor.run { selectedTaskIds = [created.id] }
            }
        }
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
                Label {
                    Text(list.name)
                } icon: {
                    Image(systemName: (list.isFavorite ?? false) ? "star.fill" : "list.bullet")
                        .foregroundStyle((list.isFavorite ?? false) ? Theme.warning : Theme.accent)
                }
                .tag(Optional(list.id))
                .contextMenu {
                    Button("Rename…") { editingList = list }
                    Button((list.isFavorite ?? false) ? "Remove Favorite" : "Favorite") { toggleFavorite(list) }
                    Button("Sharing…") { sharingList = list }
                    Divider()
                    Button("Delete…", role: .destructive) { listToDelete = list }
                }
            }
            .navigationTitle("Astrid")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button { showNewList = true } label: { Image(systemName: "plus") }
                        .help("New List")
                }
            }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { newTask() } label: { Label("New Task", systemImage: "plus") }
                        .disabled(selectedListId == nil)
                        .help("New Task")
                }
            }
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
        .sheet(isPresented: $showNewList) { MacListEditSheet(existing: nil) }
        .sheet(item: $editingList) { MacListEditSheet(existing: $0) }
        .sheet(item: $sharingList) { MacListMembersView(list: $0) }
        .confirmationDialog("Delete this list?",
                            isPresented: Binding(get: { listToDelete != nil },
                                                 set: { if !$0 { listToDelete = nil } }),
                            presenting: listToDelete) { list in
            Button("Delete “\(list.name)”", role: .destructive) { deleteList(list) }
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { accountMenu }
        }
        .safeAreaInset(edge: .bottom) {
            if !network.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text("Offline — changes will sync when reconnected")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(Theme.warning.opacity(0.15))
            }
        }
    }
}

// MacTaskDetailView + MacTaskWindowView live in Astrid Mac/Views/MacTaskDetailView.swift.
#endif
