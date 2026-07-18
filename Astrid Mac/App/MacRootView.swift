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
    @State private var columnCustomization = TableColumnCustomization<Task>()   // configurable columns (67c5e54c)
    @State private var editingTaskId: String?          // inline title editing (67c5e54c)
    @State private var editingTaskTitle = ""
    @State private var draftTitle = ""
    @FocusState private var addFieldFocused: Bool
    @SceneStorage("contentMode") private var contentMode: ContentMode = .list
    @State private var listSearch = ""

    enum ContentMode: String, CaseIterable { case list, board, chat }

    /// Tasks shown for the current selection — applies the SAME shared filter + sort business
    /// logic as iOS/web (Core/Filters). For a real list it honors that list's saved filters and
    /// sortBy; My Tasks / no-list get the assignee filter (in tasksForSelection) + auto sort.
    private var displayedTasks: [Task] {
        let base = tasksForSelection
        if let id = selectedListId, id != Self.myTasksId,
           let list = listService.lists.first(where: { $0.id == id }) {
            let filtered = filterTasksForList(base, list: list, currentUserId: auth.userId)
            return sortTasksByListSetting(filtered, sortBy: list.sortBy ?? "auto", manualOrder: list.manualSortOrder)
        }
        return sortTasksByListSetting(base, sortBy: "auto", manualOrder: nil)
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
        MacActions.perform("Delete list") {
            try await listService.deleteList(listId: list.id)
            if selectedListId == list.id { selectedListId = nil }
        }
    }

    private func listRow(_ list: TaskList) -> some View {
        Label {
            Text(list.name)
        } icon: {
            MacListIcon(list: list, size: 16)     // real list image/color swatch (mirrors iOS)
        }
        .tag(Optional(list.id))
        .dropDestination(for: String.self) { ids, _ in   // drop dragged tasks here to move them
            move(Set(ids), to: list.id); return true
        }
        .contextMenu {
            Button("Rename…") { editingList = list }
            Button((list.isFavorite ?? false) ? "Remove Favorite" : "Favorite") { toggleFavorite(list) }
            Button("Sharing…") { sharingList = list }
            Divider()
            Button("Delete…", role: .destructive) { listToDelete = list }
        }
    }

    // MARK: inline task-title editing (67c5e54c)
    private func beginInlineEdit(_ t: Task) { editingTaskId = t.id; editingTaskTitle = t.title }
    private func commitInlineEdit(_ t: Task) {
        let new = editingTaskTitle.trimmingCharacters(in: .whitespaces)
        editingTaskId = nil
        guard !new.isEmpty, new != t.title else { return }
        MacActions.perform("Rename task") { _ = try await taskService.updateTask(taskId: t.id, title: new, task: t) }
    }

    static let myTasksId = "__mytasks__"    // virtual "My Tasks" selection (Task d0306aab)

    private func matchesSearch(_ l: TaskList) -> Bool {
        listSearch.isEmpty || l.name.localizedCaseInsensitiveContains(listSearch)
    }
    private var favoriteLists: [TaskList] { listService.lists.filter { ($0.isFavorite ?? false) && matchesSearch($0) } }
    private var regularLists: [TaskList] { listService.lists.filter { !($0.isFavorite ?? false) && matchesSearch($0) } }

    private var tasksForSelection: [Task] {
        guard let id = selectedListId else { return [] }
        if id == Self.myTasksId {
            // Virtual My Tasks: incomplete tasks assigned to me across ALL lists (from the global
            // task store, so it's populated even for lists not individually opened).
            return MacMyTasks.filter(taskService.tasks, userId: auth.userId)
        }
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
            if selectedListId != Self.myTasksId {   // can't quick-add into the virtual My Tasks
                quickAddBar
                Divider()
            }
            if displayedTasks.isEmpty {
                if tasksForSelection.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                } else {
                    // The list has tasks but its saved filters hide them all (same filters as iOS/web).
                    ContentUnavailableView("Nothing matches this list’s filters",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Adjust the list’s filters on iOS or the web to see more."))
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
                .accessibilityIdentifier("tasks.quickAdd")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var taskTableBody: some View {
            Table(displayedTasks, selection: $selectedTaskIds, columnCustomization: $columnCustomization) {
                TableColumn("") { task in
                    Button { toggleCompleted(task) } label: {
                        MacTaskCheckbox(completed: task.completed, priority: task.priority, size: 18)
                    }
                    .buttonStyle(.plain)
                    .help(task.completed ? "Mark incomplete" : "Mark complete")
                    .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
                }.width(28).customizationID("done").disabledCustomizationBehavior(.all)
                TableColumn("Task") { task in
                    if editingTaskId == task.id {
                        TextField("Title", text: $editingTaskTitle)
                            .textFieldStyle(.plain)
                            .onSubmit { commitInlineEdit(task) }
                            .onExitCommand { editingTaskId = nil }
                    } else {
                        Text(task.title).strikethrough(task.completed)
                            .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                            .draggable(task.id)                       // drag onto a sidebar list to move
                            .onTapGesture(count: 2) { beginInlineEdit(task) }   // double-click to rename
                    }
                }.customizationID("title").disabledCustomizationBehavior(.visibility)
                TableColumn("List") { task in
                    if let l = listService.lists.first(where: { task.listIds?.contains($0.id) == true }) {
                        HStack(spacing: 5) { MacListIcon(list: l, size: 12); Text(l.name).lineLimit(1) }
                    } else { Text("—").foregroundStyle(.secondary) }
                }.width(min: 90, ideal: 140).customizationID("list").defaultVisibility(.hidden)
                TableColumn("Due") { task in
                    if let due = task.dueDateTime { Text(due, style: .date) }
                    else { Text("—").foregroundStyle(.secondary) }
                }.width(min: 90, ideal: 120).customizationID("due")
                TableColumn("Priority") { task in
                    if task.priority != .none {
                        Text(MacTaskVisuals.prioritySymbol(task.priority))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacTaskVisuals.priorityColor(task.priority))
                    } else { Text("—").foregroundStyle(.secondary) }
                }.width(min: 60, ideal: 80).customizationID("priority")
                TableColumn("Assignee") { task in
                    Image(systemName: task.assigneeId == nil ? "person.crop.circle.dashed" : "person.crop.circle.fill")
                        .foregroundStyle(task.assigneeId == nil ? Theme.textMuted : Theme.accent)
                        .help(task.assigneeId == nil ? "Unassigned" : "Assigned")
                }.width(70).customizationID("assignee").defaultVisibility(.hidden)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if !ids.isEmpty {
                    Button("Complete") { bulkComplete(ids) }
                    Menu("Set Priority") {
                        ForEach(MacTaskVisuals.allPriorities.reversed(), id: \.self) { p in
                            Button(MacTaskVisuals.priorityLabel(p)) { bulkSetPriority(ids, p) }
                        }
                    }
                    Menu("Move to List") {
                        ForEach(listService.lists.filter { $0.id != selectedListId }) { list in
                            Button(list.name) { move(ids, to: list.id) }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { bulkDelete(ids) }
                }
            }
    }

    private func bulkComplete(_ ids: Set<String>) {
        for t in tasksForSelection where ids.contains(t.id) && !t.completed { setCompleted(t) }
        selectedTaskIds.removeAll()
    }
    private func bulkSetPriority(_ ids: Set<String>, _ p: Task.Priority) {
        let targets = tasksForSelection.filter { ids.contains($0.id) }
        MacActions.perform("Set priority") {
            for t in targets { _ = try await taskService.updateTask(taskId: t.id, priority: p.rawValue, task: t) }
        }
    }
    private func bulkDelete(_ ids: Set<String>) {
        let targets = tasksForSelection.filter { ids.contains($0.id) }
        selectedTaskIds.removeAll()
        MacActions.perform("Delete tasks") {
            for t in targets { try await taskService.deleteTask(id: t.id, task: t) }
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
            List(selection: $selectedListId) {
                Section {
                    // Use the SAME ForEach-row pattern as the lists below — a lone tagged Label
                    // isn't reliably selectable in List(selection:); ForEach gives it row identity.
                    ForEach([Self.myTasksId], id: \.self) { _ in
                        Label {
                            Text("My Tasks")
                        } icon: {
                            Circle().fill(Theme.accent).frame(width: 12, height: 12)
                        }
                        .badge(MacMyTasks.filter(taskService.tasks, userId: auth.userId).count)
                        .tag(Optional(Self.myTasksId))
                        .accessibilityIdentifier("sidebar.myTasks")
                    }
                }
                if !favoriteLists.isEmpty {
                    Section("Favorites") { ForEach(favoriteLists) { listRow($0) } }
                }
                Section("Lists") {
                    ForEach(regularLists) { listRow($0) }
                    if regularLists.isEmpty && !listSearch.isEmpty {
                        Text("No lists match “\(listSearch)”").foregroundStyle(Theme.textMuted).font(.callout)
                    }
                }
            }
            .searchable(text: $listSearch, placement: .sidebar, prompt: "Search lists")
            .navigationTitle("Astrid")
            .accessibilityIdentifier("sidebar.lists")
            .safeAreaInset(edge: .bottom, spacing: 0) {   // account + settings at bottom-left
                Divider()
                MacSidebarAccountBar()
            }
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
                    if listId == Self.myTasksId {
                        taskTable                          // virtual My Tasks is list-only
                    } else {
                        switch contentMode {
                        case .list: taskTable
                        case .board: MacBoardView(listId: listId)
                        case .chat: MacChatPanelView(listId: listId)
                        }
                    }
                } else {
                    ContentUnavailableView("Select a list", systemImage: "sidebar.left")
                }
            }
            .navigationTitle(selectedListId == Self.myTasksId ? "My Tasks"
                             : (listService.lists.first { $0.id == selectedListId }?.name ?? "Tasks"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $contentMode) {
                        Image(systemName: "list.bullet").tag(ContentMode.list)
                        Image(systemName: "square.grid.2x2").tag(ContentMode.board)
                        Image(systemName: "bubble.left.and.bubble.right").tag(ContentMode.chat)
                    }
                    .pickerStyle(.segmented)
                    .disabled(selectedListId == nil || selectedListId == Self.myTasksId)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { newTask() } label: { Label("New Task", systemImage: "plus") }
                        .disabled(selectedListId == nil || selectedListId == Self.myTasksId)
                        .help("New Task")
                        .accessibilityIdentifier("tasks.newTask")
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
            // The global SyncManager already loaded all lists' tasks; just refresh the opened
            // real list for immediacy (My Tasks/virtual needs no per-list fetch).
            guard let id, id != Self.myTasksId else { return }
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
            _Concurrency.Task {
                await BadgeManager.shared.updateBadge(with: taskService.tasks)
                // Keep local reminder notifications in sync with due dates (Task 8b81fb9e).
                await NotificationManager.shared.rescheduleAllNotifications(for: taskService.tasks)
            }
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
