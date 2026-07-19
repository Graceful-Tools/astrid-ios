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
    // Sort applied to the task list. Empty = follow the list's own saved sortBy (shared logic);
    // otherwise this per-scene override wins so the user can re-sort like the old table headers.
    @SceneStorage("taskSortOverride") private var taskSortOverride = ""
    @State private var editingTaskId: String?          // inline title editing (67c5e54c)
    @State private var editingTaskTitle = ""
    @State private var draftTitle = ""
    @FocusState private var addFieldFocused: Bool
    @SceneStorage("contentMode") private var contentMode: ContentMode = .list
    @State private var listSearch = ""
    @State private var taskSearchQuery = ""
    @Environment(\.openWindow) private var openWindow
    static let searchId = "__search__"    // virtual "Search" selection (Task 36587d3d)

    enum ContentMode: String, CaseIterable { case list, board, chat }

    /// Tasks shown for the current selection — applies the SAME shared filter + sort business
    /// logic as iOS/web (Core/Filters). For a real list it honors that list's saved filters and
    /// sortBy; My Tasks / no-list get the assignee filter (in tasksForSelection) + auto sort.
    private var displayedTasks: [Task] {
        let base = tasksForSelection
        if let id = selectedListId, id != Self.myTasksId,
           let list = listService.lists.first(where: { $0.id == id }) {
            let filtered = filterTasksForList(base, list: list, currentUserId: auth.userId)
            let sortKey = taskSortOverride.isEmpty ? (list.sortBy ?? "auto") : taskSortOverride
            return sortTasksByListSetting(filtered, sortBy: sortKey, manualOrder: list.manualSortOrder)
        }
        let sortKey = taskSortOverride.isEmpty ? "auto" : taskSortOverride
        return sortTasksByListSetting(base, sortBy: sortKey, manualOrder: nil)
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
    @State private var showFilterSheet = false

    /// The currently-selected real (non-virtual) list — drives the filter editor + Save-as-Smart-List.
    private var currentRealList: TaskList? {
        guard let id = selectedListId, id != Self.myTasksId else { return nil }
        return listService.lists.first { $0.id == id && $0.isVirtual != true }
    }

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
            if list.isVirtual == true {
                // Saved-filter (Smart) list — a funnel glyph distinguishes it from a real list.
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(Theme.accent)
            } else {
                MacListIcon(list: list, size: 16)     // real list image/color swatch (mirrors iOS)
            }
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
    /// j/k / ↑↓ — move the single selection up or down within the currently displayed order.
    private func moveSelection(by dir: Int) {
        let ordered = displayedTasks.map(\.id)
        guard !ordered.isEmpty else { return }
        if let cur = selectedTaskIds.first, let idx = ordered.firstIndex(of: cur) {
            let next = max(0, min(ordered.count - 1, idx + dir))
            selectedTaskIds = [ordered[next]]
        } else {
            selectedTaskIds = [dir >= 0 ? ordered[0] : ordered[ordered.count - 1]]
        }
    }

    /// l — cycle the sidebar selection through My Tasks + favorites + regular lists.
    private func cycleList() {
        let ids = [Self.myTasksId] + favoriteLists.map(\.id) + regularLists.map(\.id)
        guard !ids.isEmpty else { return }
        if let cur = selectedListId, let idx = ids.firstIndex(of: cur) {
            selectedListId = ids[(idx + 1) % ids.count]
        } else {
            selectedListId = ids[0]
        }
    }

    /// Make `droppedId` a subtask of `parent` (drag-to-indent), guarding against cycles.
    @discardableResult
    private func makeSubtask(_ droppedId: String, of parent: Task) -> Bool {
        guard droppedId != parent.id,
              MacSubtaskDrop.canParent(childId: droppedId, parentId: parent.id, allTasks: taskService.tasks),
              let dropped = taskService.tasks.first(where: { $0.id == droppedId }) else { return false }
        MacActions.perform("Make subtask") {
            _ = try await taskService.updateTask(taskId: droppedId, task: dropped, parentTaskId: parent.id)
        }
        return true
    }

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
        // Saved-filter / virtual lists (isVirtual) filter across ALL tasks — the shared
        // filterTasksForList in displayedTasks then applies their saved filters (efd05e56),
        // exactly like iOS. A real list uses just its own tasks.
        if listService.lists.first(where: { $0.id == id })?.isVirtual == true {
            return taskService.tasks
        }
        return taskService.getTasksForList(id)
    }

    /// A virtual/saved-filter list can't take a quick-add or a New Task (it owns no real tasks).
    private var selectionIsVirtual: Bool {
        selectedListId == Self.myTasksId || selectedListId == Self.searchId
            || listService.lists.first(where: { $0.id == selectedListId })?.isVirtual == true
    }

    /// Global search results view (Task 36587d3d) — full-text over all tasks incl. completed.
    @ViewBuilder private var searchView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField("Search all tasks…", text: $taskSearchQuery).textFieldStyle(.plain)
                    .accessibilityIdentifier("search.field")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            let results = MacTaskSearch.matches(taskService.tasks, query: taskSearchQuery)
            if taskSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search your tasks", systemImage: "magnifyingglass",
                                       description: Text("Find any task across every list, including completed."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: taskSearchQuery)
            } else {
                List(selection: $selectedTaskIds) {
                    ForEach(results) { taskRow($0) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bgPrimary)   // pervasive theme background in search
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
            if displayedTasks.isEmpty {
                if tasksForSelection.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // The list has tasks but its saved filters hide them all (same filters as iOS/web).
                    ContentUnavailableView("Nothing matches this list’s filters",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Adjust the list’s filters on iOS or the web to see more."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                taskTableBody
            }
            // Quick-add FLOATS at the bottom (iPad/iOS placement), not pinned to the top.
            if MacAddTaskBar.isVisible(isVirtualSelection: selectionIsVirtual, hasSelection: selectedListId != nil) {
                Divider()
                quickAddBar
            }
        }
        .background(Theme.bgPrimary)   // theme shows behind the floating quick-add too
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

    /// Which tasks a row action targets: the whole selection when right-clicking a selected row in
    /// a multi-selection, otherwise just the clicked task.
    private func actionTargets(_ task: Task) -> Set<String> {
        (selectedTaskIds.contains(task.id) && selectedTaskIds.count > 1) ? selectedTaskIds : [task.id]
    }

    /// The rows to render — top-level tasks with subtasks spliced/indented under them via the SHARED
    /// splice helper (same as iOS), honoring the Sub-tasks display setting (3c945236).
    private var renderedTasks: [Task] {
        let indented = UserSettingsService.shared.settings.subtaskDisplay != "under_parent"
        let showCompletedSubs = ["all", "completed"].contains(currentRealList?.filterCompletion ?? "default")
        return spliceSubtasks(topLevel: displayedTasks.filter { $0.parentTaskId == nil },
                              allTasks: taskService.tasks, indented: indented,
                              subtaskVisible: { showCompletedSubs || !$0.completed })
    }

    private func indentLevel(_ task: Task) -> Int {
        subtaskDepth(task, byId: taskService.tasksById)
    }

    @ViewBuilder private var taskTableBody: some View {
        // iOS-style rows (not a flat table): List(selection:) gives reliable single-click selection
        // + the shared filter/sort still drives ordering. Priority shows via the checkbox ring, so
        // there's no priority column (67c5e54c superseded by UI-parity polish).
        List(selection: $selectedTaskIds) {
            // Within-list drag-reorder is only meaningful under Manual sort (7b7a17d3), like iOS —
            // otherwise the shared sort would immediately re-order any manual arrangement.
            if isManualSort, currentRealList != nil {
                ForEach(renderedTasks) { taskRow($0) }.onMove(perform: moveTasks)
            } else {
                ForEach(renderedTasks) { taskRow($0) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)            // let the theme background show through
        .background(Theme.bgPrimary)                 // Ocean cyan / Dark / Light per theme
    }

    @ViewBuilder private func taskRow(_ task: Task) -> some View {
        MacTaskRow(
            task: task,
            hiddenListIds: selectedListId.map { $0 == Self.myTasksId ? [] : [$0] } ?? [],
            isEditing: editingTaskId == task.id,
            editingTitle: $editingTaskTitle,
            indent: indentLevel(task),
            isSelected: selectedTaskIds.contains(task.id),
            onToggle: { toggleCompleted(task) },
            onCommitEdit: { commitInlineEdit(task) },
            onCancelEdit: { editingTaskId = nil }
        )
        .draggable(task.id)                        // drag onto a sidebar list to move
        // Drop another task ONTO this row → make it a subtask of this task (drag-to-indent).
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let dropped = droppedIds.first else { return false }
            return makeSubtask(dropped, of: task)
        }
        .contextMenu {
            let targets = actionTargets(task)
            Button(task.completed ? "Mark Incomplete" : "Complete") {
                targets.count > 1 ? bulkComplete(targets) : toggleCompleted(task)
            }
            Button("Rename") { beginInlineEdit(task) }
            Menu("Set Priority") {
                ForEach(MacTaskVisuals.allPriorities.reversed(), id: \.self) { p in
                    Button(MacTaskVisuals.priorityLabel(p)) { bulkSetPriority(targets, p) }
                }
            }
            Menu("Move to List") {
                ForEach(listService.lists.filter { $0.id != selectedListId }) { list in
                    Button(list.name) { move(targets, to: list.id) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { bulkDelete(targets) }
        }
        .listRowBackground(Color.clear)              // card is drawn by MacTaskRow; show theme bg between
        .listRowSeparator(.hidden)
    }

    /// The sort key actually in effect for the current selection (override wins over the list's own).
    private var effectiveSortKey: String {
        if !taskSortOverride.isEmpty { return taskSortOverride }
        return currentRealList?.sortBy ?? "auto"
    }
    private var isManualSort: Bool { effectiveSortKey == "manual" }

    /// Persist a manual within-list reorder via the canonical service (writes manualSortOrder).
    private func moveTasks(from source: IndexSet, to destination: Int) {
        guard let listId = currentRealList?.id else { return }
        let ids = MacReorder.reordered(renderedTasks.map(\.id), from: source, to: destination)
        MacActions.perform("Reorder tasks") {
            try await listService.updateManualOrder(listId: listId, order: ids)
        }
    }

    /// Sort control (retains the table's "nice sort", without the table chrome). Empty override =
    /// follow the list's own saved sort; a pick overrides it for this window.
    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $taskSortOverride) {
                Text("List Default").tag("")
                Text("Smart (Auto)").tag("auto")
                Text("Priority").tag("priority")
                Text("Due Date").tag("when")
                Text("Recently Created").tag("createdAt")
                Text("Manual").tag("manual")
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort tasks")
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
                                              lists: listService.lists,
                                              smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled) else { return }
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
                    // Global search across ALL tasks incl. completed (Task 36587d3d).
                    ForEach([Self.searchId], id: \.self) { _ in
                        Label("Search", systemImage: "magnifyingglass")
                            .tag(Optional(Self.searchId))
                            .accessibilityIdentifier("sidebar.search")
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
            .scrollContentBackground(.hidden)            // pervasive theme background (Ocean cyan) in the sidebar
            .background(Theme.bgPrimary)
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
                    if listId == Self.searchId {
                        searchView
                    } else if listId == Self.myTasksId {
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
            .navigationTitle(selectedListId == Self.searchId ? "Search"
                             : selectedListId == Self.myTasksId ? "My Tasks"
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
                if contentMode == .list, selectedListId != nil {
                    ToolbarItem(placement: .primaryAction) { sortMenu }
                }
                // Filter editor — real lists only (My Tasks filters live in its own prefs, efd05e56).
                if contentMode == .list, let list = currentRealList {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showFilterSheet = true } label: {
                            let active = MacListFilter.activeCount(completion: list.filterCompletion,
                                                                   priority: list.filterPriority,
                                                                   dueDate: list.filterDueDate,
                                                                   assignee: list.filterAssignee)
                            Label("Filter", systemImage: active > 0 ? "line.3.horizontal.decrease.circle.fill"
                                                                     : "line.3.horizontal.decrease.circle")
                        }
                        .help("Filter tasks")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { newTask() } label: { Label("New Task", systemImage: "plus") }
                        .disabled(selectedListId == nil || selectionIsVirtual)
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
        // Bare-key shortcut requests that need view state (9a60b697). Data mutations are applied in
        // MacAppModel; field-focus is handled by MacTaskDetailView — here we do selection/navigation.
        .onChange(of: appModel.shortcutRequest) { _, req in
            guard let req else { return }
            switch req.kind {
            case .selectAdjacent(let dir): moveSelection(by: dir)
            case .cycleList:               cycleList()
            case .beginRename:
                if let id = selectedTaskIds.first, let t = displayedTasks.first(where: { $0.id == id }) {
                    beginInlineEdit(t)
                }
            case .openWindow:
                if let id = selectedTaskIds.first { openWindow(id: "task", value: id) }
            case .focus: break   // handled by MacTaskDetailView
            }
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
        .sheet(isPresented: $showFilterSheet) {
            if let list = currentRealList { MacFilterSheet(list: list) }
        }
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
