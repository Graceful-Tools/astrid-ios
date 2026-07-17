//  MacRootView.swift
//  Astrid for Mac — three-column shell wired to the SHARED services (M1).
//
//  Sidebar = ListService.shared.lists; content = TaskService.shared.getTasksForList(...);
//  detail = a native Mac task detail. No task/list logic here — reads flow from the shared
//  services (the same ones iOS uses), writes go back through TaskService.

#if os(macOS)
import SwiftUI
import AppKit

struct MacRootView: View {
    @State private var keyMonitor: Any?
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @StateObject private var appModel = MacAppModel.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var network = NetworkMonitor.shared
    // Persist the selected list per scene so the window restores its last list on relaunch (Task 84993a68).
    @SceneStorage("selectedListId") private var selectedListId: String?
    @State private var selectedTaskIds = Set<String>()
    @State private var draftTitle = ""
    @FocusState private var addFieldFocused: Bool
    @SceneStorage("contentMode") private var contentMode: ContentMode = .list
    @State private var sortKey: SortKey = .due
    @State private var filter: TaskFilter = .all

    enum ContentMode: String, CaseIterable { case list, board, chat }
    enum SortKey: String, CaseIterable { case due = "Due", priority = "Priority", title = "Title" }
    enum TaskFilter: String, CaseIterable { case all = "All", active = "Active", today = "Today", overdue = "Overdue" }

    private var sortedTasks: [Task] {
        switch sortKey {
        case .due: return tasksForSelection.sorted { ($0.dueDateTime ?? .distantFuture) < ($1.dueDateTime ?? .distantFuture) }
        case .priority: return tasksForSelection.sorted { $0.priority.rawValue > $1.priority.rawValue }
        case .title: return tasksForSelection.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private var displayedTasks: [Task] {
        switch filter {
        case .all: return sortedTasks
        case .active: return sortedTasks.filter { !$0.completed }
        case .today: return sortedTasks.filter { $0.isDueToday }
        case .overdue: return sortedTasks.filter { $0.isOverdue }
        }
    }

    /// Cross-list move (C3): move the given tasks into another list via the canonical service.
    private func move(_ ids: Set<String>, to listId: String) {
        let toMove = tasksForSelection.filter { ids.contains($0.id) }
        for t in toMove {
            _Concurrency.Task { _ = try? await taskService.updateTask(taskId: t.id, listIds: [listId], task: t) }
        }
        selectedTaskIds.removeAll()
    }
    @State private var showNewList = false
    @State private var editingList: TaskList?
    @State private var sharingList: TaskList?
    @State private var listToDelete: TaskList?
    @State private var showPublicLists = false

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

    /// Focus the inline quick-add field instead of eagerly creating a junk "New Task" (C2).
    /// A task is only created when the user commits non-empty text (see commitDraft).
    private func newTask() {
        guard selectedListId != nil else { return }
        if contentMode != .list { contentMode = .list }
        addFieldFocused = true
    }

    /// Complete every selected task through the canonical service (repeat rollover honored).
    private func completeSelected() {
        let toComplete = tasksForSelection.filter { selectedTaskIds.contains($0.id) && !$0.completed }
        for task in toComplete {
            _Concurrency.Task { _ = try? await taskService.completeTask(id: task.id, completed: true, task: task) }
        }
        selectedTaskIds.removeAll()
    }

    @ViewBuilder private var taskTable: some View {
        VStack(spacing: 0) {
            quickAddBar
            Divider()
            if displayedTasks.isEmpty {
                if tasksForSelection.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                } else {
                    // The list has tasks but the active filter hides them all — say so and offer a reset.
                    ContentUnavailableView {
                        Label("Nothing matches “\(filter.rawValue)”", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No tasks in this list match the current filter.")
                    } actions: {
                        Button("Show All") { filter = .all }
                    }
                }
            } else {
                taskTableBody
            }
        }
    }

    /// Inline draft: a task is created only when the user commits non-empty text — so an
    /// abandoned draft creates nothing (the old New Task button eagerly created junk).
    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
            TextField("Add a task…  (try “Report friday #work urgent”)", text: $draftTitle)
                .textFieldStyle(.plain)
                .focused($addFieldFocused)
                .onSubmit(commitDraft)
                .accessibilityLabel("Add a task")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var taskTableBody: some View {
            Table(displayedTasks, selection: $selectedTaskIds) {
                TableColumn("") { task in
                    Button { toggleCompleted(task) } label: {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.completed ? Theme.success : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help(task.completed ? "Mark incomplete" : "Mark complete")
                    .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
                }.width(28)
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
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty {
                    Menu("Move to List") {
                        ForEach(listService.lists.filter { $0.id != selectedListId }) { list in
                            Button(list.name) { move(ids, to: list.id) }
                        }
                    }
                    Button("Complete") {
                        for t in tasksForSelection where ids.contains(t.id) && !t.completed { setCompleted(t) }
                    }
                }
            }
    }

    private func setCompleted(_ t: Task) {
        _Concurrency.Task { _ = try? await taskService.completeTask(id: t.id, completed: true, task: t) }
    }

    /// Toggle completion from the row glyph (both directions; repeat rollover honored).
    private func toggleCompleted(_ t: Task) {
        _Concurrency.Task { _ = try? await taskService.completeTask(id: t.id, completed: !t.completed, task: t) }
    }

    // MARK: bare-key shortcuts (web-parity scheme, Task cdfbd79f)

    /// Install a local key monitor so the shared bare-key scheme (n/x/Delete/?) dispatches to the
    /// same actions as the menus. Guarded: bare keys only, never while editing text or in a modal.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Returns true if the event was consumed (a shortcut fired).
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Only bare keys (allow Shift for "?"); modified keys belong to the menus.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        // Never hijack keys while a text field editor is first responder.
        if let r = NSApp.keyWindow?.firstResponder, r is NSText || r is NSTextView { return false }
        let key = MacKeyMonitor.normalizedKey(chars: event.charactersIgnoringModifiers, keyCode: event.keyCode)
        guard let key else { return false }
        let ctx = KeyboardShortcutHandler.Context(
            hasSelection: !selectedTaskIds.isEmpty,
            isTextFieldFocused: false,
            isModalPresented: appModel.showPalette || appModel.showShortcutsHelp
                || showNewList || showPublicLists || editingList != nil || sharingList != nil || listToDelete != nil)
        guard let action = KeyboardShortcutHandler.action(for: key, context: ctx),
              MacAppModel.handledActions.contains(action) else { return false }
        appModel.perform(action)
        return true
    }

    /// Commit the inline quick-add draft. Empty text creates nothing (no junk tasks).
    private func commitDraft() {
        guard let args = MacQuickAdd.makeArgs(rawText: draftTitle, selectedListId: selectedListId,
                                              lists: listService.lists) else { return }
        draftTitle = ""
        _Concurrency.Task {
            _ = try? await taskService.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate, repeating: args.repeating, repeatingData: args.repeatingData)
        }
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
                ToolbarItem {
                    Button { showPublicLists = true } label: { Image(systemName: "globe") }
                        .help("Browse Public Lists")
                }
            }
        } content: {
            Group {
                if let listId = selectedListId {
                    switch contentMode {
                    case .list: taskTable
                    case .board: MacBoardView(tasks: displayedTasks)
                    case .chat: MacChatPanelView(listId: listId)
                    }
                } else {
                    ContentUnavailableView("Select a list", systemImage: "sidebar.left")
                }
            }
            .navigationTitle(listService.lists.first { $0.id == selectedListId }?.name ?? "Tasks")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $contentMode) {
                        Image(systemName: "list.bullet").tag(ContentMode.list)
                        Image(systemName: "square.grid.2x2").tag(ContentMode.board)
                        Image(systemName: "bubble.left.and.bubble.right").tag(ContentMode.chat)
                    }
                    .pickerStyle(.segmented)
                    .disabled(selectedListId == nil)
                }
                ToolbarItem {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(TaskFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .disabled(selectedListId == nil || contentMode == .chat)
                    .help("Filter")
                }
                ToolbarItem {
                    Menu {
                        Picker("Sort by", selection: $sortKey) {
                            ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .disabled(selectedListId == nil || contentMode != .list)
                    .help("Sort")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { newTask() } label: { Label("New Task", systemImage: "plus") }
                        .disabled(selectedListId == nil)
                        .help("New Task")
                }
                if selectedTaskIds.count > 1 && contentMode == .list {
                    ToolbarItem(placement: .primaryAction) {
                        Button { completeSelected() } label: {
                            Label("Complete \(selectedTaskIds.count)", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 520)
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
        .onChange(of: selectedListId) { _, id in
            appModel.selectedListId = id                       // mirror selection for menu/shortcut commands
            // Fetch the selected list's tasks from the server (SSE keeps them fresh after).
            guard let id else { return }
            _Concurrency.Task { _ = try? await taskService.fetchTasksForListFromServer(id) }
        }
        .onChange(of: selectedTaskIds) { _, ids in appModel.selectedTaskIds = ids }
        // Apply selection requested by the command palette, then clear the request (Task 5003c622).
        .onChange(of: appModel.requestedListId) { _, id in
            if let id { selectedListId = id; appModel.requestedListId = nil }
        }
        .onChange(of: appModel.requestedTaskId) { _, tid in
            if let tid { selectedTaskIds = [tid]; appModel.requestedTaskId = nil }
        }
        .onChange(of: taskService.tasks) {
            _Concurrency.Task { await BadgeManager.shared.updateBadge(with: taskService.tasks) }
        }
        .sheet(isPresented: $appModel.showShortcutsHelp) { MacShortcutsHelpView() }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .sheet(isPresented: $appModel.showPalette) {
            CommandPaletteView(registry: appModel.registry)
        }
        .sheet(isPresented: $showNewList) { MacListEditSheet(existing: nil) }
        .sheet(item: $editingList) { MacListEditSheet(existing: $0) }
        .sheet(item: $sharingList) { MacListMembersView(list: $0) }
        .sheet(isPresented: $showPublicLists) { MacPublicListsView() }
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
