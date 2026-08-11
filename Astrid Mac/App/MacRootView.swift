//  MacRootView.swift
//  Astrid for Mac — three-column shell wired to the SHARED services (M1).
//
//  Sidebar = ListService.shared.lists; content = TaskService.shared.getTasksForList(...);
//  detail = a native Mac task detail. No task/list logic here — reads flow from the shared
//  services (the same ones iOS uses), writes go back through TaskService.

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MacRootView: View {
    @State private var keyMonitor: Any?
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @StateObject private var appModel = MacAppModel.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var syncManager = SyncManager.shared   // drives the refresh spinner (0f525a89)
    @AppStorage("macDetailFullScreen") private var detailFullScreen = false   // 42013da7
    // Persist the selected list per scene so the window restores its last list on relaunch (Task 84993a68).
    @SceneStorage("selectedListId") private var selectedListId: String?
    /// One-shot: the shell lands on My Tasks when it appears. This view is built
    /// fresh both on launch-with-a-session and immediately after signing in, so
    /// the flag resets naturally and one rule covers both (MacLaunchSelection).
    @State private var didApplyLandingSelection = false
    @State private var selectedTaskIds = Set<String>()
    // Sort applied to the task list. Empty = follow the list's own saved sortBy (shared logic);
    // otherwise this per-scene override wins so the user can re-sort like the old table headers.
    @SceneStorage("taskSortOverride") private var taskSortOverride = ""
    @State private var editingTaskId: String?          // inline title editing (67c5e54c)
    @State private var editingTaskTitle = ""
    @State private var draftTitle = ""
    /// Priority the user picked on the quick-add checkbox for the NEXT task. nil = follow the
    /// list's default (iOS behaves the same: the checkbox shows the default and can override it).
    @State private var draftPriorityOverride: Int?
    @State private var draftAssigneeOverride: String?      // "" = explicitly no one
    @State private var showDraftDefaults = false
    @FocusState private var addFieldFocused: Bool
    @SceneStorage("contentMode") private var contentMode: ContentMode = .list
    @State private var taskSearchQuery = ""
    @State private var debouncedSearchQuery = ""   // search runs on this, ~200ms behind (6042bde0)
    @State private var sideEffectsTask: _Concurrency.Task<Void, Never>?   // coalesced badge/notify (c38b177b)
    @State private var lastDueSignature = 0
    @State private var myTasksCount = 0            // memoized sidebar badge (was O(n) per body eval)
    @State private var listCounts: [String: Int] = [:]   // memoized per-list badges — see MacListCount
    @State private var selectedRowMidY: CGFloat?   // pop-out arrow tracks the selected row (a1cb6083)
    @State private var scrollAccum: CGFloat = 0    // accumulated scroll while the pop-out is open
    @State private var contentWidth: CGFloat = 0   // responsive 2/3-column (23c98550)
    @State private var windowWidth: CGFloat = 0    // decides the chat column — see chatColumnVisible
    @State private var contentFrame: CGRect = .zero  // global frame — anchors the pop-out reveal
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false   // task 01d8cfa1
    @State private var columnVisibility: NavigationSplitViewVisibility = .all   // fixed sidebar in 3-col (1a71c0e7)

    /// What the chat panel talks to for the current selection — a real list's channel, or My
    /// Tasks' VIRTUAL channel (the same one iOS and web resolve). nil = this selection has no chat.
    /// Where the pop-out unfolds from: the arrow's height inside the content area.
    private var revealAnchorY: CGFloat {
        MacDetailReveal.anchor(rowMidY: selectedRowMidY,
                               contentMinY: contentFrame.minY, contentHeight: contentFrame.height)
    }

    /// Cached once: `ProcessInfo.arguments` allocates on every read.
    // Cached: read once, not on every scroll event. Goes through MacUITestArgs so it matches the
    // single-token `-uiTestSelectRow=<n>` form the hook actually supports (69ff12e7) — a raw
    // `contains("-uiTestSelectRow")` missed it and let the scroll handler clear the selection.
    private static let uiTestSelectsRow =
        MacUITestArgs.selectedRowIndex(from: ProcessInfo.processInfo.arguments) != nil

    private var chatSource: MacChatSource? {
        MacChatSource.forSelection(selectedListId: selectedListId,
                                   myTasksId: Self.myTasksId, searchId: Self.searchId,
                                   isRealList: currentRealList != nil, userId: auth.userId)
    }

    /// 3-column mode: wide content + a selection that HAS a channel → chat is a persistent right
    /// column (web parity). My Tasks qualifies now that it resolves a virtual channel (51703e2a).
    private var chatColumnVisible: Bool {
        MacLayout.showsChatColumn(windowWidth: windowWidth, isRealList: chatSource != nil,
                                  isBoard: contentMode == .board)
    }
    @Environment(\.openWindow) private var openWindow
    /// The window's undo manager — handed to MacUndoCoordinator so ⌘Z / Edit ▸ Undo reverse
    /// complete, move and delete (Task 9b603be4).
    @Environment(\.undoManager) private var undoManager
    static let searchId = "__search__"    // virtual "Search" selection (Task 36587d3d)

    enum ContentMode: String, CaseIterable { case list, board, chat }

    /// The glyph each mode wears in the toolbar picker.
    static func symbol(for mode: ContentMode) -> String {
        switch mode {
        case .list:  return "list.bullet"
        case .board: return "square.grid.2x2"
        case .chat:  return "bubble.left.and.bubble.right"
        }
    }

    /// What the toolbar picker can offer here — list, plus a board and a chat tab when this
    /// selection actually has them (task 6d709a75).
    private var availableContentModes: [ContentMode] {
        MacViewMode.availableModes(isRealList: currentRealList != nil,
                                   projectId: currentRealList?.projectId,
                                   hasChannel: chatSource != nil,
                                   chatColumnVisible: chatColumnVisible)
    }

    /// My Tasks and an empty selection have never been switchable; the picker used to render
    /// greyed out for them, which is dead chrome rather than a choice.
    private var contentModeIsSwitchable: Bool {
        selectedListId != nil && selectedListId != Self.myTasksId
    }

    /// Tasks shown for the current selection — applies the SAME shared filter + sort business
    /// logic as iOS/web (Core/Filters). For a real list it honors that list's saved filters and
    /// sortBy; My Tasks / no-list get the assignee filter (in tasksForSelection) + auto sort.
    private var displayedTasks: [Task] {
        // Composition lives in the PURE MacRowPipeline (0b1ee8f7) so it's directly tested.
        let list = (selectedListId != Self.myTasksId)
            ? listService.lists.first(where: { $0.id == selectedListId }) : nil
        return MacRowPipeline.displayed(base: tasksForSelection, list: list,
                                        override: taskSortOverride, currentUserId: auth.userId)
    }

    /// Cross-list move (C3): move the given tasks into another list via the canonical service.
    private func move(_ ids: Set<String>, to listId: String) {
        let toMove = tasksForSelection.filter { ids.contains($0.id) }
        // Capture each task's own origin BEFORE the write — ⌘Z has to send three tasks back to
        // three different lists, not all to the one they happened to share.
        MacUndoCoordinator.shared.record(
            MacUndo.moveStep(previous: Dictionary(uniqueKeysWithValues: toMove.map { ($0.id, $0.listIds ?? []) }),
                             to: listId))
        for t in toMove {
            MacActions.perform("Move task") {
                _ = try await taskService.updateTask(taskId: t.id, listIds: [listId], task: t)
            }
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

    /// Give a list a project board. Lived only inside the board pane, which is now hidden for a
    /// list that has no board — so it moves to the sidebar's context menu (8b71bc24).
    private func enableBoard(_ list: TaskList) {
        MacActions.perform("Enable board") {
            _ = try await ProjectService.shared.createBoardForList(list)
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func toggleFavorite(_ list: TaskList) {
        MacActions.perform("Update favourite") {
            _ = try await listService.toggleFavorite(listId: list.id, isFavorite: !(list.isFavorite ?? false))
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
        // Incomplete count, like iOS's sidebar (task 74d6f6aa).
        .badge(listCounts[list.id] ?? 0)   // memoized: per-row counting is O(lists × tasks)
        .tag(Optional(list.id))
        // Drop tasks here to MOVE them, or hold Option to COPY — the macOS convention (83f45d49).
        .dropDestination(for: String.self) { ids, _ in
            draggingTaskId = nil                // the drag ended on a list; retire the lines
            switch MacDropAction.current {
            case .copy: copyTasks(Set(ids), to: list.id)
            case .move: move(Set(ids), to: list.id)
            }
            return true
        }
        .contextMenu {
            Button(NSLocalizedString("mac.rename_ellipsis", comment: "")) { editingList = list }
            Button((list.isFavorite ?? false) ? NSLocalizedString("mac.remove_favorite", comment: "")
                                  : NSLocalizedString("lists.favorite", comment: "")) { toggleFavorite(list) }
            Button(NSLocalizedString("mac.sharing", comment: "")) { sharingList = list }
            if MacViewMode.offersEnableBoard(projectId: list.projectId) {
                Button(NSLocalizedString("mac.enable_board", comment: "")) { enableBoard(list) }
            }
            Divider()
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { listToDelete = list }
        }
    }

    // MARK: inline task-title editing (67c5e54c)
    /// j/k / ↑↓ — move the single selection within the RENDERED order (what the user sees),
    /// via the pure, tested MacRowPipeline.nextSelection (0b1ee8f7).
    private func moveSelection(by dir: Int) {
        if let next = MacRowPipeline.nextSelection(orderedIds: renderedTasks.map(\.id),
                                                   current: selectedTaskIds.first, direction: dir) {
            selectedTaskIds = [next]
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
    private func beginInlineEdit(_ t: Task) { editingTaskId = t.id; editingTaskTitle = t.title }
    private func commitInlineEdit(_ t: Task) {
        let new = editingTaskTitle.trimmingCharacters(in: .whitespaces)
        editingTaskId = nil
        guard !new.isEmpty, new != t.title else { return }
        MacActions.perform("Rename task") { _ = try await taskService.updateTask(taskId: t.id, title: new, task: t) }
    }

    /// Row currently under a drag-to-indent drop, for the highlight.
    @State private var indentDropTargetId: String?

    /// The task currently being dragged, if any. Needed because the promote-to-top-level
    /// target is offered ONLY while a SUBTASK is in flight (task 2ed0d0de) — a permanent
    /// unnest strip would be noise, since most tasks are not subtasks and most drags are
    /// reorders. `.onDrag` firing on the row is the only moment this is knowable.
    @State private var draggingTaskId: String?

    /// Which row currently has its insertion line lit.
    @State private var insertionLineAboveId: String?

    private func droppedTask(_ id: String) -> Task? {
        taskService.tasks.first(where: { $0.id == id })
    }

    /// Write whatever the shared rules resolved to. A reorder or a no-op writes nothing —
    /// which is the whole point of routing every drop through `DragNesting` rather than
    /// letting each drop zone decide for itself.
    private func applyNesting(_ outcome: DragNestingOutcome, droppedId: String) {
        guard let parentId = DragNesting.parentIdToWrite(for: outcome),
              let dropped = droppedTask(droppedId) else { return }
        MacActions.perform("Move task") {
            _ = try await taskService.updateTask(taskId: droppedId, task: dropped,
                                                 parentTaskId: parentId)
        }
    }

    /// Which row currently has its outdent band lit.
    @State private var outdentBandRowId: String?

    /// The leading edge band: pull a task out to the left and drop, and it moves ONE level
    /// out of its parent. Long-press-and-drag is what starts this, so it never competes with
    /// a click or a text selection — the gestures that this row has broken over before.
    ///
    /// Like the insertion line, it exists only while something is in flight.
    @ViewBuilder private func outdentBand(for task: Task) -> some View {
        GeometryReader { geo in
            let lit = outdentBandRowId == task.id
            RoundedRectangle(cornerRadius: 4)
                .fill(lit ? Theme.accent.opacity(0.18) : Color.clear)
                .overlay(alignment: .leading) {
                    Image(systemName: "arrow.left.to.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(lit ? Theme.accent : Color.clear)
                        .padding(.leading, 6)
                }
                .frame(width: DragNesting.outdentBandWidth(rowWidth: geo.size.width))
                .contentShape(Rectangle())
                .onDrop(of: [.text], isTargeted: Binding(
                    get: { outdentBandRowId == task.id },
                    set: { hovering in
                        outdentBandRowId = hovering ? task.id
                            : (outdentBandRowId == task.id ? nil : outdentBandRowId)
                    }
                )) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                        guard let droppedId = value as? String else { return }
                        DispatchQueue.main.async {
                            outdentBandRowId = nil
                            draggingTaskId = nil
                            guard let dragged = droppedTask(droppedId) else { return }
                            applyNesting(DragNesting.outcome(for: .outdent, dragged: dragged,
                                                             byId: taskService.tasksById),
                                         droppedId: droppedId)
                        }
                    }
                    return true
                }
        }
    }

    /// The line between two rows. Dropping on it makes the dragged task TOP LEVEL, and the
    /// line is drawn flush left — at top-level indent — so the affordance shows where the
    /// task will end up rather than just saying so.
    ///
    /// It rides as a top-edge overlay on each row instead of being its own List row, because
    /// the list's `.onMove` reorder indexes into the ForEach and interleaving rows would
    /// shift every index out from under it.
    @ViewBuilder private func insertionLine(above task: Task) -> some View {
        let lit = insertionLineAboveId == task.id
        Rectangle()
            .fill(lit ? Theme.accent : Color.clear)
            .frame(height: 2)
            // The whole band is the target — a 2pt line is not something anyone can hit.
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onDrop(of: [.text], isTargeted: Binding(
                get: { insertionLineAboveId == task.id },
                set: { hovering in
                    insertionLineAboveId = hovering ? task.id
                        : (insertionLineAboveId == task.id ? nil : insertionLineAboveId)
                }
            )) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let droppedId = value as? String, let dragged = droppedTask(droppedId)
                    else { return }
                    DispatchQueue.main.async {
                        insertionLineAboveId = nil
                        draggingTaskId = nil
                        applyNesting(DragNesting.outcome(for: .betweenRows(above: task.id),
                                                         dragged: dragged,
                                                         byId: taskService.tasksById),
                                     droppedId: droppedId)
                    }
                }
                return true
            }
            // The line is the only thing describing this affordance, so it carries the words:
            // a bare 2pt rule tells VoiceOver nothing.
            .accessibilityLabel(NSLocalizedString("subtasks.promote_drop_target", comment: ""))
            .accessibilityIdentifier(SubtaskPromotion.dropTargetId)
    }

    static let myTasksId = "__mytasks__"    // virtual "My Tasks" selection (Task d0306aab)

    // Favorites vs the rest is the only split in the sidebar. There is no name filter here
    // (task 1b0f034d) — "Search" under My Tasks searches tasks, not list names.
    private var favoriteLists: [TaskList] { listService.lists.filter { $0.isFavorite ?? false } }
    private var regularLists: [TaskList] { listService.lists.filter { !($0.isFavorite ?? false) } }

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

    /// Floating detail pop-out: a rounded card on the trailing edge with a left-pointing arrow back
    /// at the task list, plus a close button (2766d9a4). Replaces the permanent empty 3rd column.
    private func taskDetailPopout(_ task: Task) -> some View {
        // ✕ / "Task Details" / ⋯ live in the detail's own web-style header (df22157f).
        MacTaskDetailView(task: task, onClose: { selectedTaskIds.removeAll() })
            .frame(width: MacLayout.detailPanelWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MacDetailChrome.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 16, x: -2, y: 4)
            // The arrow is drawn ON TOP of the card, overlapping its edge by a point, so its base
            // MERGES into the card surface. Previously it sat in its own column beside the card:
            // the card's border stroke ran across the arrow's base (it looked cut off) and the
            // arrow carried its own drop shadow, which tinted it darker than the card.
            // Same fill as the card + no shadow of its own = it blends.
            .overlay(alignment: .topLeading) {
                GeometryReader { g in
                    // Convert the row's content-space midY through the CARD's measured origin.
                    // A hardcoded offset was wrong because the panel is centered, so its origin
                    // moves with the panel's height — the arrow aimed at the wrong task (69fd1f19).
                    // Global on BOTH sides (row + panel): a named-space mismatch offset the arrow
                    // by about one row height, so it pointed one row below the tapped one.
                    let originY = g.frame(in: .global).minY
                    MacPopoverArrow()
                        .fill(MacDetailChrome.background)
                        .frame(width: MacLayout.detailArrowWidth, height: 24)
                        .position(x: -MacLayout.detailArrowWidth / 2 + 1,   // 1pt overlap hides the border seam
                                  y: MacSelectionModel.arrowLocalY(rowMidY: selectedRowMidY,
                                                                   panelOriginY: originY,
                                                                   panelHeight: g.size.height))
                        .animation(MacMotion.fast, value: selectedRowMidY)
                }
            }
            .padding(.leading, MacLayout.detailArrowWidth + MacLayout.detailPanelMargin)
            .padding(.trailing, MacLayout.detailPanelMargin)
        .padding(.vertical, 14)
        // FULL height, not centred-and-intrinsic: a shorter card cannot reach rows outside its own
        // vertical extent, so the arrow clamped to the card's edge and pointed at the wrong row.
        .frame(maxHeight: .infinity)
    }

    /// Global search results view (Task 36587d3d) — full-text over all tasks incl. completed.
    @ViewBuilder private var searchView: some View {
        VStack(spacing: 0) {
            // A themed input card like the quick-add, with the SAME margins as a task row — it was
            // a bare unstyled field sitting flush against the window chrome (task 233144d9).
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMuted)
                TextField(NSLocalizedString("mac.search_all_tasks", comment: ""), text: $taskSearchQuery)
                    .textFieldStyle(.plain)
                    .font(MacTypography.rowTitle)
                    .accessibilityIdentifier("search.field")
                if !taskSearchQuery.isEmpty {
                    Button { taskSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .macPointingHand()
                    .help(NSLocalizedString("actions.clear", comment: ""))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.inputBg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.inputBorder, lineWidth: 0.5))
            .padding(.horizontal, MacLayout.rowTrailingGap)
            .padding(.vertical, 10)
            // Debounce: matches() runs on the debounced query (~200ms), not every keystroke (6042bde0).
            .task(id: taskSearchQuery) {
                try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                debouncedSearchQuery = taskSearchQuery
            }
            let results = MacTaskSearch.matches(taskService.tasks, query: debouncedSearchQuery)
            if taskSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                // Branded Astrid empty states, like every other empty surface — search was the
                // last place still showing system ContentUnavailableView chrome.
                MacEmptyState(copy: .searchPrompt)
            } else if results.isEmpty {
                MacEmptyState(copy: .searchNoResults)
            } else {
                List {
                    ForEach(results) { taskRow($0) }   // manual selection via row taps (0f695ef2)
                }
                .listStyle(.inset)
                .macScrollBars(showScrollBars)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bgPrimary)   // pervasive theme background in search
    }

    /// Complete every selected task through the canonical service (repeat rollover honored).
    private func completeSelected() {
        let toComplete = tasksForSelection.filter { selectedTaskIds.contains($0.id) && !$0.completed }
        MacUndoCoordinator.shared.record(
            MacUndo.completeStep(previous: Dictionary(uniqueKeysWithValues: toComplete.map { ($0.id, $0.completed) }),
                                 to: true))
        for task in toComplete {
            MacActions.perform("Complete task") {
                _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
            }
        }
        selectedTaskIds.removeAll()
    }

    @ViewBuilder private var taskTable: some View {
        // Compute the row pipeline ONCE per body eval (4e0ce183) — previously displayedTasks/
        // tasksForSelection/renderedTasks were each re-run per reference (3–5 full passes).
        let rows = renderedTasks
        VStack(spacing: 0) {
            if rows.isEmpty {
                // Branded Astrid empty states (1c3562e9) — character + speech bubble, not system chrome.
                MacEmptyState(copy: tasksForSelection.isEmpty ? .noTasks : .filteredOut)
            } else {
                taskTableBody(rows)
            }
            // Quick-add FLOATS at the bottom (iPad/iOS placement) as a lifted card — no divider.
            if MacAddTaskBar.isVisible(isVirtualSelection: selectionIsVirtual,
                                       hasSelection: selectedListId != nil,
                                       isMyTasks: selectedListId == Self.myTasksId) {
                quickAddBar
            }
        }
        .background(Theme.bgPrimary)   // theme shows behind the floating quick-add too
    }

    /// The task-list column. It NEVER changes width for the detail pop-out: the pop-out floats
    /// over the chat column instead (which is sized to contain it), so selecting a task cannot
    /// reflow the rows (task 89e42f29 follow-up).
    private var listColumn: some View {
        VStack(spacing: 0) {
            listChrome
            taskTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Sort and filter, above the rows they act on (9998d83a). They used to be
    /// `.primaryAction` toolbar items, but the window toolbar spans the whole detail area — so in
    /// 3-column mode they right-aligned above the CHAT column and read as its controls.
    @ViewBuilder
    private var listChrome: some View {
        let showsSort = MacListChrome.showsSort(hasSelection: selectedListId != nil,
                                                isListMode: contentMode == .list)
        let showsFilter = MacListChrome.showsFilter(isRealList: currentRealList != nil,
                                                    isListMode: contentMode == .list)
        if showsSort || showsFilter {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if showsSort { sortMenu.fixedSize() }
                if showsFilter, let list = currentRealList { filterButton(list) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, MacLayout.rowTrailingGap)
            .padding(.vertical, 4)
        }
    }

    /// The saved-filter editor. Lifted out of the toolbar with `sortMenu` (9998d83a).
    private func filterButton(_ list: TaskList) -> some View {
        Button { showFilterSheet = true } label: {
            let active = MacListFilter.activeCount(completion: list.filterCompletion,
                                                   priority: list.filterPriority,
                                                   dueDate: list.filterDueDate,
                                                   assignee: list.filterAssignee)
            Label(NSLocalizedString("actions.filter", comment: ""),
                  systemImage: active > 0 ? "line.3.horizontal.decrease.circle.fill"
                                          : "line.3.horizontal.decrease.circle")
        }
        .help(NSLocalizedString("mac.filter_tasks", comment: ""))
    }

    /// Inline draft: a task is created only when the user commits non-empty text — so an
    /// abandoned draft creates nothing (the old New Task button eagerly created junk).
    private var quickAddBar: some View {
        // iOS QuickAddTaskView layout (task 022701f3): checkbox on the LEFT, the bordered input in
        // the middle, and the add ⊕ on the RIGHT — the + used to be a decoration inside the field
        // on the left, with no way to commit by clicking. The surface stays themed (chrome silver
        // on Ocean, black on Dark) with a lift shadow, matching 5b41942a.
        HStack(alignment: .center, spacing: 12) {
            // Left: the same checkbox affordance iOS shows ahead of the field.
            // The leading control mirrors a task ROW: the priority-coloured checkbox for the
            // defaults this task will get, or the assignee's avatar when it is going to someone
            // else. Tapping it opens the override picker.
            //
            // NOTE: this is a plain view + tap, NOT a `Menu` with a custom label — that collapsed
            // the label and the checkbox disappeared from the add row entirely.
            Group {
                if let assignee = draftAssignee {
                    MacAssigneeAvatar(user: assignee, priority: draftPriority,
                                      size: MacTaskVisuals.rowCheckboxSize)
                } else {
                    MacTaskCheckbox(completed: false, priority: draftPriority,
                                    size: MacTaskVisuals.rowCheckboxSize,
                                    // The add-row previews what the task will be, repeat
                                    // included — the list's default repeat (ca13c94b).
                                    repeating: draftRepeats)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showDraftDefaults = true }
            .macPointingHand()
            .help(NSLocalizedString("tasks.priority", comment: ""))
            .popover(isPresented: $showDraftDefaults, arrowEdge: .top) {
                draftDefaultsPicker
            }

            // Wraps + expands vertically for long titles (a02a6819); Return still commits.
            TextField(NSLocalizedString("mac.quick_add_placeholder", comment: ""), text: $draftTitle, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .font(MacTypography.rowTitle)
                .focused($addFieldFocused)
                .onSubmit { commitDraft() }
                // The caret was unreachable except by clicking the field: this FocusState was
                // bound here and set by nothing, which is "add task didn't always have a cursor
                // prompt" (b71850e6). Focus follows the bar becoming usable, and the rule for
                // WHEN lives in MacAddTaskBar so it can be asserted.
                .onAppear { focusAddFieldIfAppropriate() }
                .onChange(of: selectedListId) { focusAddFieldIfAppropriate() }
                .onChange(of: taskSearchQuery.isEmpty) { focusAddFieldIfAppropriate() }
                .accessibilityLabel(NSLocalizedString("tasks.add_task_placeholder", comment: ""))
                .accessibilityIdentifier("tasks.quickAdd")

            // Right: ⊕ commits the draft (iOS parity); dimmed and inert while empty.
            // ⊕ adds the task AND opens its details (iOS / web parity); Return just adds.
            Button { commitDraft(openDetails: true) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MacQuickAdd.isCommittable(draftTitle) ? Theme.accent : Theme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!MacQuickAdd.isCommittable(draftTitle))
            .macPointingHand()
            .help(NSLocalizedString("tasks.new_task", comment: ""))
        }
        // ONE floating input card holding the checkbox, the field and ⊕ (iOS / web parity). The
        // internal padding matches MacTaskRow's card, so the quick-add checkbox sits in the same
        // column as the checkboxes of the rows above it.
        .padding(.horizontal, 12).padding(.vertical, 9)
        // The SAME surface a task row card uses (white on Light/Ocean) rather than the grey input
        // fill — the add row should read as a task card you are about to fill in, like iOS.
        .background(MacSelectionStyle.fill(isSelected: false), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.inputBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -2)
        .frame(maxWidth: .infinity)
        // Same outer margin as a row CARD: the rows sit inside an inset List, so matching their
        // 8pt card padding alone left the add row wider than the rows above it.
        .padding(.horizontal, MacLayout.rowTrailingGap)
        .padding(.vertical, 8)
    }

    /// Which tasks a row action targets: the whole selection when right-clicking a selected row in
    /// a multi-selection, otherwise just the clicked task.
    private func actionTargets(_ task: Task) -> Set<String> {
        (selectedTaskIds.contains(task.id) && selectedTaskIds.count > 1) ? selectedTaskIds : [task.id]
    }

    /// The rows to render — top-level tasks with subtasks spliced/indented under them via the SHARED
    /// splice helper (same as iOS), honoring the Sub-tasks display setting (3c945236).
    private var renderedTasks: [Task] {
        // Splice composition lives in the PURE MacRowPipeline (0b1ee8f7).
        MacRowPipeline.rendered(displayed: displayedTasks, allTasks: taskService.tasks,
                                indented: UserSettingsService.shared.settings.subtaskDisplay != "under_parent",
                                filterCompletion: currentRealList?.filterCompletion)
    }

    private func indentLevel(_ task: Task) -> Int {
        subtaskDepth(task, byId: taskService.tasksById)
    }

    @ViewBuilder private func taskTableBody(_ rows: [Task]) -> some View {
        // iOS-style rows. Selection is managed MANUALLY (no List(selection:) binding) so the native
        // macOS accent highlight never paints the whole row — the card stays white and only the
        // border shows selection (0f695ef2). Row taps select / re-tap closes / ⌘-click multi-selects.
        List {
            // Within-list drag-reorder is only meaningful under Manual sort (7b7a17d3), like iOS —
            // otherwise the shared sort would immediately re-order any manual arrangement.
            if isManualSort, currentRealList != nil {
                ForEach(rows) { taskRow($0) }
                    .onMove { source, destination in moveTasks(rows: rows, from: source, to: destination) }
            } else {
                ForEach(rows) { taskRow($0) }
            }
        }
        .listStyle(.inset)
        .macScrollBars(showScrollBars)          // hidden by default (task 01d8cfa1)
        // UI-test hook: XCUITest cannot deliver clicks into macOS List rows, so a layout test has
        // no way to open the detail pop-out. `-uiTestSelectRow <n>` selects the nth rendered row
        // on appear, making selection-dependent layout capturable. Inert without the argument.
        .onAppear { selectRowForUITestingIfRequested(rows) }
        // MacRowKey, not rows.map(\.id): the same question, without allocating an id array on
        // every body evaluation (e949df82).
        .onChange(of: MacRowKey.key(rows)) { _, _ in selectRowForUITestingIfRequested(rows) }
        .scrollContentBackground(.hidden)            // let the theme background show through
        .background(Theme.bgPrimary)                 // Ocean cyan / Dark / Light per theme
        .animation(MacMotion.medium, value: MacRowKey.key(rows))   // row insert/delete/reorder eases (4c7b9f08)
        // An intentional scroll dismisses the detail pop-out (a1cb6083).
        .onVerticalScroll { oldY, newY in
            // A UI-test-driven selection must survive the content shift that inserting rows causes,
            // or the layout capture never sees the pop-out. Cached — reading
            // ProcessInfo.arguments allocates, and this runs on every scroll event.
            if Self.uiTestSelectsRow { return }
            guard MacDetailPopover.isVisible(selectionCount: selectedTaskIds.count) else { scrollAccum = 0; return }
            scrollAccum += abs(newY - oldY)
            if MacSelectionModel.scrollShouldClose(delta: scrollAccum) {
                scrollAccum = 0
                selectedTaskIds.removeAll()
            }
        }
    }

    /// Test-only: honour `-uiTestSelectRow <index>` so UI tests can capture selection-dependent
    /// layout (the pop-out + its arrow). No effect in a normal run.
    private func selectRowForUITestingIfRequested(_ rows: [Task]) {
        // Synchronous on purpose: an async `.task(id:)` version was cancelled every time `rows`
        // changed, and `Task.sleep` returns immediately once cancelled, so the retry loop burned
        // out before the rows settled and the row was never selected.
        guard let n = MacUITestArgs.selectedRowIndex(from: ProcessInfo.processInfo.arguments),
              rows.indices.contains(n), selectedTaskIds.isEmpty else { return }
        selectedTaskIds = [rows[n].id]
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
            onCancelEdit: { editingTaskId = nil },
            // Selection lives on the row CONTENT (see MacTaskRow): a row-level tap gesture
            // swallowed the checkbox click and left it dead (task 652edb22).
            onSelect: {
                let cmd = NSEvent.modifierFlags.contains(.command)
                selectedTaskIds = MacSelectionModel.tap(current: selectedTaskIds, tapped: task.id, commandKey: cmd)
                scrollAccum = 0
            },
            // Which task is in flight decides whether the promote strip is offered at all.
            onDragBegan: { draggingTaskId = task.id }
        )
        // .draggable now lives on the row CONTENT (MacTaskRow) so it can't eat checkbox clicks.
        // Drop another task ONTO this row → make it a subtask of this task (drag-to-indent).
        //
        // `.onDrop`, not `.dropDestination`: inside a List, the row's own handling swallows the
        // higher-level modifier — the same defect that left the checkbox Button dead (652edb22)
        // and `.draggable` unable to start a drag (83f45d49). `.onDrop` is the lower-level API
        // that actually receives the event, and it also reports hover, which this had none of:
        // with no highlight there was nothing to tell you a row would accept the drop.
        .onDrop(of: [.text], isTargeted: Binding(
            get: { indentDropTargetId == task.id },
            set: { hovering in
                indentDropTargetId = hovering ? task.id : (indentDropTargetId == task.id ? nil : indentDropTargetId)
            }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let dropped = value as? String else { return }
                DispatchQueue.main.async {
                    indentDropTargetId = nil
                    draggingTaskId = nil        // the drag ended here; retire the insertion lines
                    // The SAME shared rules the insertion line uses, so the two drop zones
                    // cannot disagree about cycles or about what is already true.
                    guard let dragged = droppedTask(dropped) else { return }
                    applyNesting(DragNesting.outcome(for: .onRow(task.id),
                                                     dragged: dragged,
                                                     byId: taskService.tasksById),
                                 droppedId: dropped)
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(indentDropTargetId == task.id ? Theme.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        )
        // "Top level, here." Only while something is actually in flight — the lines answer a
        // drag, and with no drag there is no question to answer.
        .overlay(alignment: .top) {
            if draggingTaskId != nil { insertionLine(above: task) }
        }
        // "Out one level." Same rule: present only during a drag.
        .overlay(alignment: .leading) {
            if draggingTaskId != nil { outdentBand(for: task) }
        }
        .contextMenu {
            let targets = actionTargets(task)
            Button(task.completed ? NSLocalizedString("mac.mark_incomplete", comment: "")
                     : NSLocalizedString("reminders.complete", comment: "")) {
                targets.count > 1 ? bulkComplete(targets) : toggleCompleted(task)
            }
            Button(NSLocalizedString("mac.rename", comment: "")) { beginInlineEdit(task) }
            Menu(NSLocalizedString("mac.set_priority", comment: "")) {
                ForEach(MacTaskVisuals.allPriorities.reversed(), id: \.self) { p in
                    Button(MacTaskVisuals.priorityLabel(p)) { bulkSetPriority(targets, p) }
                }
            }
            Menu(NSLocalizedString("mac.move_to_list", comment: "")) {
                ForEach(listService.lists.filter { $0.id != selectedListId }) { list in
                    Button(list.name) { move(targets, to: list.id) }
                }
            }
            // Share / copy straight from the row — iOS offers these on a task without opening it
            // first, and on Mac they were detail-only (task ea0527ef). Same shared services.
            Menu(NSLocalizedString("lists.copy_to_list", comment: "")) {
                ForEach(MacTaskCopy.targets(lists: listService.lists)) { t in
                    Button(t.label) { copyTask(task, to: t.listId) }
                }
            }
            Button(NSLocalizedString("actions.share", comment: "")) { shareTaskFromRow(task) }
            Button(NSLocalizedString("actions.copy", comment: "")) {
                MacTaskActions.copyToPasteboard(
                    MacTaskActions.clipboardText(title: task.title, shareURL: nil))
            }
            Button(NSLocalizedString("mac.open_new_window", comment: "")) {
                openWindow(id: "task", value: task.id)
            }
            Divider()
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { bulkDelete(targets) }
        }
        .listRowBackground(Color.clear)              // card is drawn by MacTaskRow; show theme bg between
        .listRowSeparator(.hidden)
        // The selected row reports its vertical center so the pop-out arrow points at it.
        .background(GeometryReader { g in
            Color.clear.preference(key: MacSelectedRowMidYKey.self,
                                   value: selectedTaskIds == [task.id]
                                       ? g.frame(in: .global).midY : nil)
        })
    }

    /// The sort key actually in effect for the current selection (override wins over the list's own).
    private var effectiveSortKey: String {
        if !taskSortOverride.isEmpty { return taskSortOverride }
        return currentRealList?.sortBy ?? "auto"
    }
    private var isManualSort: Bool { effectiveSortKey == "manual" }

    /// Persist a manual within-list reorder via the canonical service (writes manualSortOrder).
    /// Takes the already-computed rows so the pipeline isn't re-run (4e0ce183).
    private func moveTasks(rows: [Task], from source: IndexSet, to destination: Int) {
        guard let listId = currentRealList?.id else { return }
        let ids = MacReorder.reordered(rows.map(\.id), from: source, to: destination)
        MacActions.perform("Reorder tasks") {
            try await listService.updateManualOrder(listId: listId, order: ids)
        }
    }

    /// Sort control. On a REAL list a pick is saved to the list (`sortBy`) through the canonical
    /// service, so it persists and syncs to iOS/web — iOS behaves the same way. Previously every
    /// pick was a window-local override that never left the Mac (task 2b886104). Virtual/saved
    /// selections own no list, so those keep the local override.
    private var sortMenu: some View {
        Menu {
            if let list = currentRealList {
                Picker(NSLocalizedString("actions.sort", comment: ""), selection: Binding(
                    get: { list.sortBy ?? "auto" },
                    set: { newValue in
                        taskSortOverride = ""          // the list's own sort is authoritative again
                        MacActions.perform("Update sort") {
                            _ = try await ListService.shared.updateListAdvanced(
                                listId: list.id, updates: ["sortBy": newValue])
                        }
                    }
                )) {
                    ForEach(MacListFilter.sort) { Text($0.label).tag($0.value) }
                }
            } else {
                Picker(NSLocalizedString("actions.sort", comment: ""), selection: $taskSortOverride) {
                    Text(NSLocalizedString("mac.list_default", comment: "")).tag("")
                    ForEach(MacListFilter.sort) { Text($0.label).tag($0.value) }
                }
            }
        } label: {
            Label(NSLocalizedString("actions.sort", comment: ""), systemImage: "arrow.up.arrow.down")
        }
        .help(NSLocalizedString("mac.sort_tasks", comment: ""))
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
        MacUndoCoordinator.shared.record(MacUndo.deleteStep(
            snapshots: MacUndoCoordinator.shared.deletionSnapshots(for: targets, allTasks: taskService.tasks)))
        MacActions.perform("Delete tasks") {
            for t in targets { try await taskService.deleteTask(id: t.id, task: t) }
        }
    }

    private func setCompleted(_ t: Task) {
        MacUndoCoordinator.shared.record(MacUndo.completeStep(previous: [t.id: t.completed], to: true))
        MacActions.perform("Complete task") {
            _ = try await taskService.completeTask(id: t.id, completed: true, task: t)
        }
    }

    /// Toggle completion from the row glyph (both directions; repeat rollover honored).
    private func toggleCompleted(_ t: Task) {
        // Surface failures instead of swallowing them with `try?` — a silently-failing completion
        // is indistinguishable from a dead checkbox (task 652edb22).
        MacUndoCoordinator.shared.record(MacUndo.completeStep(previous: [t.id: t.completed], to: !t.completed))
        MacActions.perform("Complete task") {
            _ = try await TaskService.shared.completeTask(id: t.id, completed: !t.completed, task: t)
        }
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

    /// Copy dropped tasks into a list (Option-drag), through the same service the menu uses so
    /// comments come across too.
    private func copyTasks(_ ids: Set<String>, to listId: String) {
        MacActions.perform("Copy tasks") {
            for id in ids {
                _ = try await TaskService.shared.copyTask(id: id, targetListId: listId,
                                                          includeComments: true)
            }
        }
    }

    /// Copy a task into another list from the row menu — the SAME service call the detail menu
    /// uses, so the comments come across too.
    private func copyTask(_ task: Task, to listId: String?) {
        MacActions.perform("Copy task") {
            _ = try await TaskService.shared.copyTask(id: task.id, targetListId: listId,
                                                      includeComments: true)
        }
    }

    /// Share from the row: make the shortcode link through the shared service (identical to iOS
    /// ShareTaskView), then present the native share sheet.
    private func shareTaskFromRow(_ task: Task) {
        MacActions.perform("Share task") {
            if let url = try await MacTaskActions.makeShareURL(taskId: task.id) {
                MacTaskActions.presentShareSheet(url: url, relativeTo: nil)
            }
        }
    }

    /// Commit the inline quick-add draft. Empty text creates nothing (no junk tasks).
    /// The assignee the next task will get — the override, else the list's default. nil means it
    /// stays with the creator, which is drawn as a checkbox rather than an avatar (row parity).
    private var draftAssignee: User? {
        let id = draftAssigneeOverride
            ?? NewTaskDefaults.assignee(currentRealList?.defaultAssigneeId, currentUserId: auth.userId)
        // Unassigned, or assigned to ME, draws as the CHECKBOX — exactly like a task row. Only a
        // task headed to someone ELSE shows an avatar.
        guard let id, !id.isEmpty, id != auth.userId else { return nil }
        // Only show an avatar for someone we can actually name: a synthesised User with no name
        // rendered as "??", which is not a person (task follow-up).
        return listMembers.first { $0.userId == id }?.user
    }

    /// What "list default" resolves to for the Who row, so the picker states the real outcome
    /// rather than an abstract label.
    private var listDefaultAssigneeLabel: String {
        let id = NewTaskDefaults.assignee(currentRealList?.defaultAssigneeId, currentUserId: auth.userId)
        guard let id, !id.isEmpty else { return NSLocalizedString("assignee.unassigned", comment: "") }
        if id == auth.userId { return NSLocalizedString("lists.me", comment: "") }
        return listMembers.first { $0.userId == id }?.user?.displayName
            ?? NSLocalizedString("lists.me", comment: "")
    }

    /// Members of the current list, for the assignee picker.
    private var listMembers: [ListMember] {
        currentRealList.flatMap { ListMemberService.shared.membersByList[$0.id] } ?? []
    }

    /// Override the defaults for the NEXT task only — the same idea as iOS's quick-add picker.
    @ViewBuilder private var draftDefaultsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("tasks.priority", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)
            // The SAME styled picker the task detail uses — ○ ! !! !!! in their priority colours,
            // not plain text buttons.
            MacPriorityPicker(selection: Binding(
                get: { draftPriority },
                set: { draftPriorityOverride = $0.rawValue }
            ))
            Text(NSLocalizedString("tasks.assignee", comment: ""))
                .font(MacTypography.label).foregroundStyle(Theme.textMuted)
            Picker("", selection: Binding(
                get: { draftAssigneeOverride ?? "" },
                set: { draftAssigneeOverride = $0.isEmpty ? nil : $0 }
            )) {
                // Say what the default actually resolves to (Me / Unassigned / a name) instead of
                // an abstract "List default" the user then has to guess at.
                Text(String(format: NSLocalizedString("mac.list_default_is", comment: ""),
                            listDefaultAssigneeLabel)).tag("")
                Text(NSLocalizedString("assignee.unassigned", comment: "")).tag("unassigned")
                ForEach(listMembers) { m in Text(m.user?.displayName ?? m.userId).tag(m.userId) }
            }
            .labelsHidden()
            Divider()
            Button(NSLocalizedString("mac.list_default", comment: "")) {
                draftPriorityOverride = nil
                draftAssigneeOverride = nil
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    /// The priority the quick-add checkbox displays: the user's override if they picked one,
    /// otherwise the destination list's default.
    /// Whether a task added right now would repeat — i.e. the list carries a default repeat.
    /// The quick-add checkbox previews it, the same way it previews the default priority.
    private var draftRepeats: Bool {
        NewTaskDefaults.repeating(currentRealList?.defaultRepeating) != nil
    }

    private var draftPriority: Task.Priority {
        let raw = draftPriorityOverride
            ?? NewTaskDefaults.priority(currentRealList?.defaultPriority)
            ?? 0
        return Task.Priority(rawValue: raw) ?? .none
    }

    /// - Parameter openDetails: ⊕ opens the new task's details (iOS / web); Return does not.
    /// Put the caret in the quick-add field when the rule says it belongs there.
    private func focusAddFieldIfAppropriate() {
        guard MacAddTaskBar.shouldTakeFocus(
            isVisible: MacAddTaskBar.isVisible(isVirtualSelection: selectionIsVirtual,
                                               hasSelection: selectedListId != nil,
                                               isMyTasks: selectedListId == Self.myTasksId),
            isSearchActive: !taskSearchQuery.isEmpty
        ) else { return }
        addFieldFocused = true
    }

    private func commitDraft(openDetails: Bool = false) {
        guard let args = MacQuickAdd.makeArgs(rawText: draftTitle, selectedListId: selectedListId,
                                              lists: listService.lists,
                                              smartEnabled: UserSettingsService.shared.smartTaskCreationEnabled,
                                              selectionIsVirtual: selectionIsVirtual,
                                              priorityOverride: draftPriorityOverride,
                                              currentUserId: auth.userId) else { return }
        draftTitle = ""
        if MacAddTaskBar.retainsFocusAfterCommit { addFieldFocused = true }
        let assigneeOverride = draftAssigneeOverride
        draftPriorityOverride = nil          // the overrides apply to one task, like iOS
        draftAssigneeOverride = nil
        MacActions.perform("Add task") {
            let created = try await taskService.createTask(
                listIds: args.listIds, title: args.title, priority: args.priority,
                whenDate: args.whenDate,
                assigneeId: assigneeOverride == "unassigned" ? nil : (assigneeOverride ?? args.assigneeId),
                isPrivate: args.isPrivate,
                repeating: args.repeating, repeatingData: args.repeatingData)
            // `created` is non-optional now that the error is thrown rather than swallowed.
            if openDetails { selectedTaskIds = [created.id] }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedListId) {
                Section {
                    // Use the SAME ForEach-row pattern as the lists below — a lone tagged Label
                    // isn't reliably selectable in List(selection:); ForEach gives it row identity.
                    ForEach([Self.myTasksId], id: \.self) { _ in
                        Label {
                            Text(NSLocalizedString("navigation.my_tasks", comment: ""))
                        } icon: {
                            Circle().fill(Theme.accent).frame(width: 12, height: 12)
                        }
                        .badge(myTasksCount)   // memoized — was a full O(n) scan per body eval (c38b177b)
                        .tag(Optional(Self.myTasksId))
                        .accessibilityIdentifier("sidebar.myTasks")
                    }
                    // Global search across ALL tasks incl. completed (Task 36587d3d).
                    ForEach([Self.searchId], id: \.self) { _ in
                        Label(NSLocalizedString("actions.search", comment: ""), systemImage: "magnifyingglass")
                            .tag(Optional(Self.searchId))
                            .accessibilityIdentifier("sidebar.search")
                    }
                }
                if !favoriteLists.isEmpty {
                    Section(NSLocalizedString("navigation.favorites", comment: "")) { ForEach(favoriteLists) { listRow($0) } }
                }
                Section(NSLocalizedString("navigation.lists", comment: "")) {
                    // Add List / Public Lists live HERE, above the lists, the way iOS
                    // (ListSidebarView.addListButton) and web do — not as unlabelled toolbar
                    // glyphs (0fc546a8).
                    ForEach(MacSidebarActions.all, id: \.id) { action in
                        Button {
                            if action.id == "sidebar.newList" { showNewList = true } else { showPublicLists = true }
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.id)
                    }
                    ForEach(regularLists) { listRow($0) }
                }
            }
            .macScrollBars(showScrollBars)               // hidden by default (task 01d8cfa1)
            .scrollContentBackground(.hidden)            // pervasive theme background (Ocean cyan) in the sidebar
            .background(Theme.bgPrimary)
            .navigationTitle(Brand.appName)
            .accessibilityIdentifier("sidebar.lists")
            .safeAreaInset(edge: .bottom, spacing: 0) {   // account + settings at bottom-left
                Divider()
                MacSidebarAccountBar()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)

        } detail: {
            Group {
                if let listId = selectedListId {
                    if listId == Self.searchId {
                        searchView
                    } else if chatColumnVisible, let chatSource {
                        // 3-column (web ≥1100 parity): chat is ALWAYS visible as the right column;
                        // the middle shows list or board (23c98550). My Tasks reaches here too —
                        // it has a virtual channel, same as iOS and web (51703e2a).
                        HStack(spacing: 0) {
                            listColumn      // board never reaches here — see chatColumnVisible
                            Divider()
                            MacChatPanelView(source: chatSource)
                                .frame(width: MacLayout.chatColumnWidth)
                        }
                    } else {
                        switch contentMode {
                        case .board where listId != Self.myTasksId:
                            // The board gets the SAME floating quick-add as the list, pinned at the
                            // bottom, adding into this board's list (task e466eab8).
                            VStack(spacing: 0) {
                                MacBoardView(listId: listId)
                                if MacAddTaskBar.isVisible(isVirtualSelection: selectionIsVirtual,
                                                           hasSelection: true,
                                                           isMyTasks: listId == Self.myTasksId) {
                                    quickAddBar
                                }
                            }
                        case .chat:
                            if let chatSource { MacChatPanelView(source: chatSource) } else { listColumn }
                        default: listColumn
                        }
                    }
                } else {
                    MacEmptyState(copy: .noListSelected).background(Theme.bgPrimary)
                }
            }
            // The detail pop-out floats at the trailing edge of the content area, which in
            // 3-column mode IS the chat column — the panel covers chat, never the task rows, and
            // the rows keep their width (task 89e42f29 follow-up). Board shows details inline.
            .overlay(alignment: detailFullScreen ? .center : .trailing) {
                if contentMode != .board, selectedTaskIds.count == 1,
                   let id = selectedTaskIds.first,
                   // O(1) only: `tasksForSelection` here would re-run the entire filter→sort→
                   // splice pipeline on every body evaluation (the cost 4e0ce183 removed).
                   let task = taskService.tasksById[id] {
                    if detailFullScreen {
                        // Full screen (42013da7): the panel fills the content area so the
                        // description gets the whole window. No arrow — there is no row beside it
                        // to point at, and the fold-out transition would be pointing at nothing.
                        MacTaskDetailView(task: task, onClose: { selectedTaskIds.removeAll() })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(MacDetailChrome.background)
                            .transition(.opacity)
                    } else {
                        taskDetailPopout(task)
                            // Unfolds OUT OF the arrow and folds back into it the same way — the
                            // panel grows horizontally from the arrow's position, which sits at the
                            // selected row. A plain slide/fade did not read as coming from the task.
                            .transition(.modifier(
                                active: MacDetailReveal(progress: 0, anchorY: revealAnchorY),
                                identity: MacDetailReveal(progress: 1, anchorY: revealAnchorY)))
                    }
                }
            }
            .coordinateSpace(name: "contentArea")              // rows report frames in this space
            .onPreferenceChange(MacSelectedRowMidYKey.self) { selectedRowMidY = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { contentFrame = $0 }
            .animation(MacMotion.medium, value: contentMode)   // list/board/chat switch eases (4c7b9f08)
            .navigationTitle(selectedListId == Self.searchId ? "Search"
                             : selectedListId == Self.myTasksId ? "My Tasks"
                             : (listService.lists.first { $0.id == selectedListId }?.name ?? "Tasks"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Drawn only when there is something to switch BETWEEN — see
                    // MacViewMode.showsModePicker (task 6d709a75).
                    if MacViewMode.showsModePicker(modes: availableContentModes,
                                                   isSwitchable: contentModeIsSwitchable) {
                        Picker(NSLocalizedString("mac.view", comment: ""), selection: $contentMode) {
                            ForEach(availableContentModes, id: \.self) { mode in
                                Image(systemName: Self.symbol(for: mode)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                // Manual refresh (0f525a89) — the one control that DOES belong to the window
                // rather than to the task list: it reconciles everything, not just these rows.
                ToolbarItem(placement: .primaryAction) {
                    Button { MacAppModel.shared.refreshNow() } label: {
                        if MacRefresh.showsProgress(isSyncing: syncManager.isSyncing) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(NSLocalizedString("mac.refresh", comment: ""),
                                  systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(!MacRefresh.isEnabled(isOnline: network.isConnected,
                                                    isSyncing: syncManager.isSyncing))
                    .help(NSLocalizedString("mac.refresh", comment: ""))
                    .accessibilityIdentifier("tasks.refresh")
                }
                // Sort, filter and the task "+" are NOT toolbar items (9998d83a, 10d2cd34): the
                // window toolbar's trailing edge is the chat column in 3-column mode, so they
                // looked like the message list's controls. Sort/filter moved to `listChrome`
                // above the rows; adding lives on the quick-add bar's ⊕ and ⌘N.
                if selectedTaskIds.count > 1 && contentMode == .list {
                    ToolbarItem(placement: .primaryAction) {
                        Button { completeSelected() } label: {
                            Label(String(format: NSLocalizedString("mac.complete_count", comment: ""),
                                         selectedTaskIds.count), systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.85), value: selectedTaskIds)
        }
        // 3-column mode (1a71c0e7) OPENS the sidebar when the window becomes wide enough — it must
        // not PIN it there. Snapping `.all` back on every change made the rail impossible to close:
        // the toolbar toggle and ⌃⌘S were undone the instant they fired.
        .onChange(of: chatColumnVisible) { _, wide in
            if wide { columnVisibility = .all }
        }
        // Adding/removing a list, or editing a smart list's filters, changes the badges too.
        .onChange(of: listService.lists.map(\.id)) { _, _ in
            listCounts = MacListCount.counts(taskService.tasks, lists: listService.lists,
                                             currentUserId: auth.userId)
        }
        // Measure the WINDOW, not the content area: the content shrinks when the sidebar opens,
        // which used to drop the window under the 3-column threshold and close the chat column.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onAppear {
            guard !didApplyLandingSelection else { return }
            didApplyLandingSelection = true
            // A UI test asks for its own starting selection; don't fight it.
            guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
            selectedListId = MacLaunchSelection.landingListId(restored: selectedListId,
                                                             myTasksId: Self.myTasksId)
        }
        .task {
            // Seed the memoized badge (onChange only fires on later mutations — c38b177b).
            myTasksCount = MacMyTasks.filter(taskService.tasks, userId: auth.userId).count
            listCounts = MacListCount.counts(taskService.tasks, lists: listService.lists,
                                             currentUserId: auth.userId)
            // Hydrate lists from the shared service (cache-first, offline-safe).
            _ = try? await listService.fetchLists()
        }
        .onChange(of: selectedListId) { _, id in
            selectedTaskIds.removeAll()                        // close the detail panel when switching lists
            appModel.selectedListId = id                       // mirror selection for menu/shortcut commands
            // The global SyncManager already loaded all lists' tasks; just refresh the opened
            // real list for immediacy (My Tasks/virtual needs no per-list fetch).
            guard let id, id != Self.myTasksId else { return }
            _Concurrency.Task { _ = try? await taskService.fetchTasksForListFromServer(id) }
        }
        .onChange(of: selectedTaskIds) { _, ids in appModel.selectedTaskIds = ids }
        // Apply selection requested by the command palette, then clear the request (Task 5003c622).
        // A list without a board must not leave the pane showing one the picker is hiding.
        .onChange(of: selectedListId) { _, _ in
            contentMode = MacViewMode.resolve(requested: contentMode,
                                              isRealList: currentRealList != nil,
                                              projectId: currentRealList?.projectId)
        }
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
            // Menu-bar ⌘ equivalents (e0412a64).
            case .focusSearch:
                selectedListId = Self.searchId
            case .setContentMode(let raw):
                // Board/chat only mean something for a real list; falling back to the list view
                // beats a menu item that silently does nothing.
                if let mode = ContentMode(rawValue: raw) {
                    contentMode = MacViewMode.resolve(requested: mode,
                                                      isRealList: currentRealList != nil,
                                                      projectId: currentRealList?.projectId)
                }
            case .showFilters:
                if currentRealList != nil { showFilterSheet = true }
            }
        }
        .onChange(of: taskService.tasks) {
            // Coalesce per-mutation side-effects (c38b177b): a burst of edits schedules ONE pass
            // ~0.8s later, and notifications reschedule only when the due-date shape changed
            // (title/priority edits used to reschedule ALL local notifications).
            sideEffectsTask?.cancel()
            sideEffectsTask = _Concurrency.Task {
                try? await _Concurrency.Task.sleep(nanoseconds: MacSideEffects.coalesceNanos)
                guard !_Concurrency.Task.isCancelled else { return }
                let tasks = taskService.tasks
                myTasksCount = MacMyTasks.filter(tasks, userId: auth.userId).count
                listCounts = MacListCount.counts(tasks, lists: listService.lists,
                                                 currentUserId: auth.userId)
                await BadgeManager.shared.updateBadge(with: tasks)
                let sig = MacSideEffects.dueSignature(tasks)
                if sig != lastDueSignature {
                    lastDueSignature = sig
                    // Keep local reminder notifications in sync with due dates (Task 8b81fb9e).
                    await NotificationManager.shared.rescheduleAllNotifications(for: tasks)
                }
            }
        }
        .sheet(isPresented: $appModel.showShortcutsHelp) { MacShortcutsHelpView() }
        .onAppear { installKeyMonitor(); MacUndoCoordinator.shared.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in MacUndoCoordinator.shared.undoManager = new }
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
        .confirmationDialog(NSLocalizedString("mac.delete_list_confirm", comment: ""),
                            isPresented: Binding(get: { listToDelete != nil },
                                                 set: { if !$0 { listToDelete = nil } }),
                            presenting: listToDelete) { list in
            Button(String(format: NSLocalizedString("mac.delete_list_named", comment: ""), list.name),
                   role: .destructive) { deleteList(list) }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if !network.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text(NSLocalizedString("mac.offline_banner", comment: ""))
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
