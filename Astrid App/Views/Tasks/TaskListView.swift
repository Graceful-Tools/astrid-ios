import SwiftUI

/// Applies `.refreshable` only when `isEnabled` — `.refreshable`
/// returns an opaque type, so it can't be toggled with a plain
/// ternary. Used to suppress pull-to-refresh in board mode, where an
/// inherited refresh control caused a vertical bounce while swiping
/// between columns.
private struct ConditionalRefreshable: ViewModifier {
    let isEnabled: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

struct TaskListView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @StateObject private var syncManager = SyncManager.shared

    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?  // The featured list data
    @Binding var searchText: String  // Search text from sidebar
    @Binding var selectedTaskForPanel: Task?  // For iPad side panel presentation
    var forcePushNavigation: Bool = false  // When true, use iPhone-style push even on iPad
    var onMenuTap: (() -> Void)?

    @State private var isCopyingList = false
    @State private var showingListSettings = false
    @State private var showingMyTasksFilter = false
    @State private var taskToNavigateTo: Task?
    @State private var taskToShowInSheet: Task?  // For iPad modal presentation
    @State private var featuredListTasks: [Task] = []  // Tasks for featured public list
    @State private var isLoadingFeaturedTasks = false
    @State private var showingCopySheet = false
    @State private var taskToCopy: Task?
    @State private var hasLoadedInitialData = false  // Prevent infinite .task loop
    /// Which view the user picked from the unified List/Board/Messages
    /// rotator button. Defaults to `.list`; auto-flips to `.board` when
    /// the selected list has a project board attached (so the board
    /// renders by default while still letting the user rotate back to
    /// the list or forward to messages).
    @State private var taskViewMode: HeaderToggleSegment = .list
    @FocusState private var isSearchFieldFocused: Bool  // Keyboard focus for search header

    // My Tasks filter preferences (synced across devices via server)
    @StateObject private var myTasksPreferences = MyTasksPreferencesService.shared

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    init(
        selectedListId: Binding<String?> = .constant(nil),
        isViewingFromFeatured: Binding<Bool> = .constant(false),
        featuredList: Binding<TaskList?> = .constant(nil),
        searchText: Binding<String> = .constant(""),
        selectedTaskForPanel: Binding<Task?> = .constant(nil),
        forcePushNavigation: Bool = false,
        onMenuTap: (() -> Void)? = nil
    ) {
        _selectedListId = selectedListId
        _isViewingFromFeatured = isViewingFromFeatured
        _featuredList = featuredList
        _searchText = searchText
        _selectedTaskForPanel = selectedTaskForPanel
        self.forcePushNavigation = forcePushNavigation
        self.onMenuTap = onMenuTap
    }

    private var selectedList: TaskList? {
        // If viewing from featured, use the featured list data
        if isViewingFromFeatured, let featured = featuredList {
            return featured
        }

        // Otherwise look it up in user's lists
        guard let listId = selectedListId else { return nil }
        return listService.lists.first { $0.id == listId }
    }

    /// Determine if user can add tasks (show quick add and + button)
    private var shouldShowQuickAdd: Bool {
        // No quick add in search mode
        if selectedListId == "search" {
            return false
        }

        // My Tasks and no list selected always allow adding tasks
        if selectedListId == "my-tasks" || selectedListId == nil {
            return true
        }

        // Special case: Bugs & Feedback list allows anyone to add tasks
        if selectedListId == Constants.Lists.bugsAndRequestsListId {
            return true
        }

        guard let list = selectedList,
              let currentUserId = AuthManager.shared.userId else {
            return false
        }

        return canUserAddTasks(userId: currentUserId, list: list)
    }

    /// Determine if user can view list settings (any member can access sort/filter/leave).
    /// Canonical source of roles is `listMembers` — mirrors web's
    /// `getUserRoleInList` in `astrid-web/lib/list-permissions.ts`.
    private var canShowListSettings: Bool {
        guard let list = selectedList,
              let currentUserId = AuthManager.shared.userId else {
            return false
        }
        return list.isMember(userId: currentUserId)
    }

    /// Navigation title based on current view state
    private var navigationTitle: String {
        // If search is active, show search query
        if !searchText.isEmpty {
            let truncated = searchText.count > 20 ? String(searchText.prefix(20)) + "..." : searchText
            return String(format: NSLocalizedString("search.query_prefix", comment: ""), truncated)
        }

        // Otherwise show list name
        if selectedListId == "my-tasks" {
            let baseName = NSLocalizedString("navigation.my_tasks", comment: "")
            let filterText = getMyTasksFilterText()

            if !filterText.isEmpty {
                return "\(baseName) - \(filterText)"
            }
            return baseName
        }

        return selectedList?.name ?? NSLocalizedString("navigation.all_tasks", comment: "")
    }

    /// Get filter text for My Tasks (matching web implementation, including priority 0)
    private func getMyTasksFilterText() -> String {
        let prefs = myTasksPreferences.preferences
        let dueDate = prefs.filterDueDate ?? "all"
        let priority = prefs.filterPriority ?? []

        let hasDateFilter = dueDate != "all"
        let hasPriorityFilter = !priority.isEmpty

        // No filters active
        if !hasDateFilter && !hasPriorityFilter {
            return ""
        }

        // Get date filter text
        var dateText = ""
        if hasDateFilter {
            switch dueDate {
            case "today":
                dateText = NSLocalizedString("time.today", comment: "")
            case "this_week":
                dateText = NSLocalizedString("time.this_week", comment: "")
            case "this_month":
                dateText = NSLocalizedString("time.this_month", comment: "")
            case "overdue":
                dateText = NSLocalizedString("tasks.overdue", comment: "")
            case "no_date":
                dateText = NSLocalizedString("tasks.no_due_date", comment: "")
            default:
                dateText = ""
            }
        }

        // Get priority filter text (including priority 0 with ○ symbol)
        // If all 4 priorities are selected (0,1,2,3), treat as "no filter" since it includes everything
        var priorityText = ""
        let allPrioritiesSelected = Set(priority) == Set([0, 1, 2, 3])
        if hasPriorityFilter && !priority.isEmpty && !allPrioritiesSelected {
            // Sort priorities in descending order to show highest first
            let sortedPriorities = priority.sorted(by: >)

            // Convert priority numbers to symbols
            let priorityMarks = sortedPriorities.compactMap { p -> String? in
                switch p {
                case 3: return "!!!"
                case 2: return "!!"
                case 1: return "!"
                case 0: return "○"  // Priority 0 shows as ○
                default: return nil
                }
            }

            if !priorityMarks.isEmpty {
                priorityText = String(format: NSLocalizedString("tasks.priority_only", comment: ""), priorityMarks.joined(separator: " "))
            }
        }

        // Combine date and priority filters
        if !dateText.isEmpty && !priorityText.isEmpty {
            return "\(dateText) \(priorityText)"
        } else if !dateText.isEmpty {
            return dateText
        } else if !priorityText.isEmpty {
            return priorityText
        }

        return ""
    }

    /// Get priority color for iOS (matching web colors)
    private func getPriorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .red        // Highest priority
        case 2: return .orange     // High priority
        case 1: return .blue       // Medium priority
        case 0: return .gray       // Low/no priority (○)
        default: return .gray
        }
    }

    /// Navigation title view with colored priority indicators (including ○ for priority 0)
    private var navigationTitleView: some View {
        let title = navigationTitle
        let prefs = myTasksPreferences.preferences
        let priority = prefs.filterPriority ?? []

        // Only apply colors if we're on My Tasks and have priority filters with indicators
        if selectedListId == "my-tasks" && !priority.isEmpty && (title.contains("!") || title.contains("○")) {
            // Split the title into parts, coloring priority indicators
            return AnyView(
                HStack(spacing: 0) {
                    ForEach(splitTitleWithPriorities(title), id: \.0) { index, part, priorityLevel in
                        if let priorityLevel = priorityLevel {
                            // This is a priority indicator - apply color
                            Text(part)
                                .foregroundColor(getPriorityColor(priorityLevel))
                        } else {
                            // Regular text
                            Text(part)
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        }
                    }
                }
            )
        } else {
            // Default rendering without colors
            return AnyView(
                Text(title)
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
            )
        }
    }

    /// Split title into parts with priority levels for coloring (including ○ for priority 0)
    private func splitTitleWithPriorities(_ title: String) -> [(Int, String, Int?)] {
        var result: [(Int, String, Int?)] = []
        var index = 0

        // Pattern: match priority indicators (!!!, !!, !, ○)
        let pattern = "(!!!|!!|!|○)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [(0, title, nil)]
        }

        let nsString = title as NSString
        let matches = regex.matches(in: title, range: NSRange(location: 0, length: nsString.length))

        var lastEnd = 0
        for match in matches {
            let matchRange = match.range

            // Add text before this match
            if matchRange.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                let beforeText = nsString.substring(with: beforeRange)
                result.append((index, beforeText, nil))
                index += 1
            }

            // Add the priority indicator with its priority level
            let priorityText = nsString.substring(with: matchRange)
            let priorityLevel: Int
            switch priorityText {
            case "!!!": priorityLevel = 3
            case "!!": priorityLevel = 2
            case "!": priorityLevel = 1
            case "○": priorityLevel = 0
            default: priorityLevel = 0
            }
            result.append((index, priorityText, priorityLevel))
            index += 1

            lastEnd = matchRange.location + matchRange.length
        }

        // Add remaining text after last match
        if lastEnd < nsString.length {
            let remainingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let remainingText = nsString.substring(with: remainingRange)
            result.append((index, remainingText, nil))
        }

        return result
    }

    /// Floating header with rounded corners (modern look)
    @ViewBuilder
    private var floatingHeader: some View {
        if selectedListId == "search" {
            searchHeader
        } else {
            standardHeader
        }
    }

    /// Search mode header with editable text field
    private var searchHeader: some View {
        HStack(spacing: 0) {
            // Leading: Hamburger menu icon
            HamburgerMenuIcon()
                .padding(.leading, 22)
                .padding(.trailing, 10)

            // Editable search field styled like the header title
            HStack(spacing: Theme.spacing8) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                TextField(NSLocalizedString("tasks.search_tasks_placeholder", comment: "Search tasks"), text: $searchText)
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.vertical, Theme.spacing12)
        .padding(.horizontal, Theme.spacing4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusLarge)
                .fill(colorScheme == .dark ? Theme.Dark.bgSecondary : Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 8)
        .padding(.top, Theme.spacing8)
        .overlay(alignment: .topLeading) {
            Button(action: {
                onMenuTap?()
            }) {
                Color.clear
                    .frame(width: 120, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: 8)
            .allowsHitTesting(true)
            .transaction { transaction in
                transaction.animation = nil
            }
            .zIndex(999)
        }
        .onAppear {
            // Auto-focus the search field when entering search mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFieldFocused = true
            }
        }
    }

    /// Standard (non-search) floating header
    private var standardHeader: some View {
        HStack(spacing: 0) {
            // Leading: Hamburger menu icon (visual only, tap target is overlay)
            HamburgerMenuIcon()
                .padding(.leading, 22)  // Align with task row checkboxes
                .padding(.trailing, 10)  // Space to align title with task titles

            // Title (with colored priority indicators for My Tasks filters, including ○)
            navigationTitleView
                .font(Theme.Typography.headline())

            Spacer()

            // Trailing: Actions (same as toolbar)
            HStack(spacing: Theme.spacing16) {
                // Copy List button for featured public lists
                if isViewingFromFeatured && selectedList != nil {
                    Button {
                        _Concurrency.Task {
                            await copyList()
                        }
                    } label: {
                        if isCopyingList {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(Theme.Typography.headline())
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCopyingList)
                }

                // Unified view-mode rotator: list → messages → board → list.
                // Replaces the old 2-way ChatToggleButton. The board step is
                // skipped automatically when the current list has no project
                // board attached, matching getHeaderViewToggle()'s rules.
                if !isViewingFromFeatured, let _ = selectedListId {
                    ViewModeRotatorButton(
                        mode: $taskViewMode,
                        hasBoard: selectedList?.projectId != nil
                    )
                }

                // Settings/Filter button
                if selectedListId == "my-tasks" {
                    Button {
                        showingMyTasksFilter = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(Theme.Typography.headline())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                } else if selectedList != nil && canShowListSettings {
                    Button {
                        showingListSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(Theme.Typography.headline())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, 0)  // Align hamburger icon left edge with checkbox left edge
        .padding(.trailing, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(headerBackground)
        .cornerRadius(Theme.radiusLarge)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)  // Match task row horizontal margins
        .padding(.top, Theme.spacing8)
        .overlay(alignment: .topLeading) {
            // Large tap target overlay - doesn't affect layout or animations
            Button(action: {
                onMenuTap?()
            }) {
                Color.clear
                    .frame(width: 120, height: 60)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: 8)  // Align with header padding
            .allowsHitTesting(true)
            .transaction { transaction in
                transaction.animation = nil  // Don't animate overlay changes
            }
            .zIndex(999)  // Keep overlay on top without affecting layout
        }
    }


    var body: some View {
        NavigationStack {
            ZStack {
                // Theme background behind all floating elements
                getPrimaryBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom floating header
                    floatingHeader

                    // Main content — driven by `taskViewMode`. The rotator
                    // button in the header advances the mode.
                    if taskViewMode == .messages, let listId = selectedListId {
                        ChatPanelView(listId: listId, onSignedIn: {
                            taskViewMode = .list
                        })
                    } else {
                        Group {
                            if (!taskService.hasCompletedInitialLoad || !listService.hasCompletedInitialLoad) || (taskService.isLoading && taskService.tasks.isEmpty) || (isViewingFromFeatured && isLoadingFeaturedTasks) {
                                loadingState
                            } else if taskViewMode == .board,
                                      let projectId = selectedList?.projectId {
                                // Render the board straight from the projectId —
                                // we don't need the full Project model to draw
                                // columns (status lists are on ListService and
                                // are looked up by projectId).
                                ProjectStatusBoardView(
                                    projectId: projectId,
                                    onOpenSidebar: onMenuTap,
                                    onTaskTap: { task in
                                        // iPad split view: open in the side panel so the
                                        // board stays visible in the left column, just like
                                        // the flat list does. Tapping the open task again
                                        // closes it. iPhone / forced-push: full screen.
                                        if UIDevice.current.userInterfaceIdiom == .pad && !forcePushNavigation {
                                            selectedTaskForPanel = (selectedTaskForPanel?.id == task.id) ? nil : task
                                        } else {
                                            TaskPresenter.shared.showTask(task)
                                        }
                                    },
                                    selectedTaskId: selectedTaskForPanel?.id
                                )
                            } else {
                                // Compute the filtered rows ONCE per body eval
                                // (was computed twice: here and in taskList).
                                let rows = filteredTasks
                                if rows.isEmpty {
                                    emptyState
                                } else {
                                    taskList(rows: rows)
                                }
                            }
                        }
                    }

                    // Quick add task at bottom (phone and iPad). Show only
                    // when looking at the list view. Suppressed in board
                    // mode (each column has its own inline footer) and
                    // messages mode (chat has its own input).
                    if shouldShowQuickAdd && taskViewMode == .list {
                        QuickAddTaskView(
                            selectedList: selectedList,
                            onTaskCreated: { task in
                                // iPad: Show in side panel (replacing any existing), iPhone/forcePush: Push navigation
                                if UIDevice.current.userInterfaceIdiom == .pad && !forcePushNavigation {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        selectedTaskForPanel = task
                                    }
                                } else {
                                    taskToNavigateTo = task
                                }
                            }
                        )
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Suppress the swipe-to-open-sidebar gesture when
                        // the board view is active — the column carousel
                        // owns horizontal pans in that mode. Mirrors the
                        // web's shouldHandleMobileListSwipe gate.
                        let gate = MobileListSwipeGateState(
                            isMobile: UIDevice.current.userInterfaceIdiom == .phone,
                            mobileView: "list",
                            showMobileSidebar: false, // sidebar is owned by parent; this view fires only when sidebar is closed
                            isBoardMode: taskViewMode == .board
                        )
                        guard shouldHandleMobileListSwipe(gate) else { return }

                        let isHorizontal = value.translation.width > abs(value.translation.height)
                        let isRight = value.translation.width > 0
                        let meetsThreshold = value.translation.width > 80
                            || value.predictedEndTranslation.width > 200
                        if isHorizontal && isRight && meetsThreshold {
                            onMenuTap?()
                        }
                    }
            )
            .leadingEdgeSwipe(
                isEnabled: UIDevice.current.userInterfaceIdiom == .phone && taskViewMode != .board
            ) {
                onMenuTap?()
            }
            .navigationTitle("")
            .navigationDestination(item: $taskToNavigateTo) { task in
                getTaskDetailView(for: task)
                    .onAppear {
                        NotificationCenter.default.post(name: .taskDetailDidAppear, object: nil)
                    }
                    .onDisappear {
                        NotificationCenter.default.post(name: .taskDetailDidDisappear, object: nil)
                    }
            }
            .withTaskPresentation()  // Handle global TaskPresenter navigation
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingListSettings) {
                listSettingsSheet
            }
            .sheet(isPresented: $showingMyTasksFilter) {
                MyTasksFilterSheet()
            }
            .sheet(isPresented: $showingCopySheet) {
                if let task = taskToCopy {
                    CopyTaskView(task: task, currentListId: nil)
                }
            }
            .sheet(item: $taskToShowInSheet) { task in
                // iPad task detail modal (same view as iPhone navigation)
                NavigationStack {
                    getTaskDetailView(for: task)
                }
            }
        }
        .task {
            // Only load data once on initial appearance to prevent infinite loop
            guard !hasLoadedInitialData else { return }
            hasLoadedInitialData = true

            // Register SSE handler for My Tasks preferences updates (once only)
            await SSEClient.shared.onMyTasksPreferencesUpdated { preferences in
                _Concurrency.Task { @MainActor in
                    MyTasksPreferencesService.shared.handleSSEUpdate(preferences)
                }
            }

            // Load data in background to avoid blocking UI on initial load
            // UI will update automatically when data arrives via @Published properties
            _Concurrency.Task {
                do {
                    try await loadData()
                } catch {
                    // Show error to user via taskService
                    taskService.errorMessage = "Failed to load tasks: \(error.localizedDescription)"
                }
            }
        }
        // Pull-to-refresh is suppressed in board mode: the column
        // carousel owns vertical drags, and an inherited `.refreshable`
        // caused a vertical bounce while swiping between columns.
        .modifier(ConditionalRefreshable(isEnabled: taskViewMode != .board) {
            do {
                try await loadData()
            } catch {
                // Errors on refresh are less critical, don't show to user
            }
            // Pull-to-refresh also nudges the external sync providers
            // (debounced no-ops when not connected / nothing linked).
            GitHubSyncService.shared.scheduleSync()
            GoogleTasksSyncService.shared.scheduleSync()
        })
        .onChange(of: isViewingFromFeatured) { _, newValue in
            if newValue, let listId = selectedListId {
                _Concurrency.Task {
                    await loadFeaturedListTasks(listId: listId)
                }
            } else {
                // Clear featured list data when switching to regular lists
                featuredList = nil
                featuredListTasks = []
            }
        }
        .onChange(of: selectedListId) { _, newListId in
            // Reset the view-mode rotator: default to board when the new
            // list has one, list otherwise. A fresh selection always
            // resets the default; within a list the user can rotate freely.
            taskViewMode = selectedList?.projectId != nil ? .board : .list

            if isViewingFromFeatured, let listId = newListId {
                _Concurrency.Task {
                    await loadFeaturedListTasks(listId: listId)
                }
            } else {
                // Clear featured tasks when switching away from featured
                featuredListTasks = []
            }
        }
        // NOTE: No onChange handler needed for featured lists!
        // User's tasks come from taskService.tasks (source of truth, like regular lists)
        // Other users' tasks come from featuredListTasks (refreshed on load/pull)
        // The merge happens in filteredTasks computed property
    }

    // MARK: - Search Logic

    private func applySearchFilter(_ tasks: [Task], query: String) -> [Task] {
        let lowercaseQuery = query.lowercased()

        return tasks.filter { task in
            // Search in title
            if task.title.lowercased().contains(lowercaseQuery) {
                return true
            }

            // Search in description
            if task.description.lowercased().contains(lowercaseQuery) {
                return true
            }

            // Search in assignee name (if available)
            if let assigneeName = task.assignee?.displayName,
               assigneeName.lowercased().contains(lowercaseQuery) {
                return true
            }

            return false
        }
    }

    // MARK: - List Settings Sheet

    @ViewBuilder
    private var listSettingsSheet: some View {
        // Use selectedList which handles both:
        // 1. Featured public lists (from featuredList)
        // 2. User's own lists (from listService.lists)
        if let list = selectedList {
            ListSettingsModal(
                list: list,
                onUpdate: { updatedList in
                    handleListUpdate(original: list, updated: updatedList)
                },
                onDelete: {
                    handleListDelete(listId: list.id)
                },
                onLeave: {
                    handleListLeave(listId: list.id)
                }
            )
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ScrollView {
            // Use same EmptyStateView as splash screen for seamless transition
            EmptyStateView(
                message: NSLocalizedString("tasks.loading", comment: ""),
                buttonTitle: nil,
                buttonAction: nil
            )
            .frame(minHeight: UIScreen.main.bounds.height - 200)
        }
    }

    // MARK: - Task List

    private func taskList(rows: [Task]) -> some View {
        List {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                TaskRowView(
                    task: task,
                    onToggle: {
                        _Concurrency.Task {
                            do {
                                _ = try await taskService.completeTask(id: task.id, completed: !task.completed, task: task)
                            } catch {
                                // Completion errors surface via the service's own state.
                            }
                        }
                    },
                    isViewingFeaturedPublicList: isViewingFromFeatured,
                    onCopy: {
                        taskToCopy = task
                        showingCopySheet = true
                    },
                    isSelected: selectedTaskForPanel?.id == task.id,
                    compactMode: UIDevice.current.userInterfaceIdiom == .pad,  // Always truncate on iPad
                    hiddenListIds: rowHiddenListIds
                )
                .listRowBackground(getPrimaryBackground())
                .listRowSeparator(.hidden)  // Hide separator for card effect
                .listRowInsets(EdgeInsets(
                    top: index == 0 ? 8 : 4,  // First task has 2x top margin
                    leading: 8 + CGFloat(min(subtaskDepth(task), 4)) * 16,  // Per-level indent, capped at 4 levels (deeper still shows)
                    bottom: 4,
                    trailing: 8  // Horizontal margin
                ))
                .onTapGesture {
                    // iPad: toggle the side panel (tap the same task to close).
                    // Set instantly so the row's selected state changes immediately;
                    // the panel's slide is animated by the container. iPhone /
                    // forced-push: push to navigation.
                    if UIDevice.current.userInterfaceIdiom == .pad && !forcePushNavigation {
                        selectedTaskForPanel = (selectedTaskForPanel?.id == task.id) ? nil : task
                    } else {
                        taskToNavigateTo = task
                    }
                }
            }
            .onDelete(perform: deleteTasks)
            .onMove(perform: moveTask)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(getPrimaryBackground())
        // Selected-row highlight is instant even though the container animates the
        // detail panel's slide.
        .animation(nil, value: selectedTaskForPanel?.id)
    }

    /// Rows to render: top-level pipeline, plus (in the default "indented"
    /// display mode) each visible parent's subtasks spliced directly after it.
    /// "under_parent" mode hides subtasks from lists entirely (detail only).
    private var filteredTasks: [Task] {
        let top = topLevelFilteredTasks
        guard UserSettingsService.shared.settings.subtaskDisplay != "under_parent" else { return top }
        var byParent: [String: [Task]] = [:]
        for t in taskService.tasks {
            if let parentId = t.parentTaskId { byParent[parentId, default: []].append(t) }
        }
        guard !byParent.isEmpty else { return top }
        // Depth-first: nested subtasks (subtasks of subtasks, any depth) all
        // render, each following the SAME completion settings as the list.
        // Depth cap of 10 guards against bad-data cycles.
        var out: [Task] = []
        func appendSubtree(_ task: Task, depth: Int) {
            out.append(task)
            guard depth < 10, let subs = byParent[task.id] else { return }
            let visible = applyContextCompletionFilter(subs)
                .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            for sub in visible { appendSubtree(sub, depth: depth + 1) }
        }
        for t in top { appendSubtree(t, depth: 0) }
        return out
    }

    /// Nesting depth of a task (0 = top-level), walking parentTaskId with a
    /// cycle-safe cap. O(1) parent lookups via tasksById (was an O(n) scan per
    /// ancestor step → O(depth×n) per row → O(n²) across the list).
    private func subtaskDepth(_ task: Task) -> Int {
        let byId = taskService.tasksById
        var depth = 0
        var parentId = task.parentTaskId
        while let pid = parentId, depth < 8 {
            depth += 1
            parentId = byId[pid]?.parentTaskId
        }
        return depth
    }

    /// The completion filter the CURRENT view context applies to its rows —
    /// mirrors the branches of `topLevelFilteredTasks` so spliced subtasks obey
    /// the exact same visibility rule as their surroundings.
    private func applyContextCompletionFilter(_ tasks: [Task]) -> [Task] {
        if !searchText.isEmpty {
            return applyCompletionFilter(tasks, filterCompletion: "default")
        }
        if selectedListId == "my-tasks" {
            let completion = myTasksPreferences.preferences.filterCompletion ?? "default"
            return applyCompletionFilter(tasks, filterCompletion: completion)
        }
        if let list = selectedList {
            return applyCompletionFilterWithWindow(
                tasks,
                filter: list.filterCompletion ?? "default",
                window: list.recentlyCompletedWindow
            )
        }
        return applyCompletionFilter(tasks, filterCompletion: "default")
    }

    private var topLevelFilteredTasks: [Task] {
        // Search mode with no query — show empty state
        if selectedListId == "search" && searchText.isEmpty {
            return []
        }

        var tasks = taskService.tasks

        // Subtasks render inside their parent's detail, not as top-level rows.
        tasks = tasks.filter { $0.parentTaskId == nil }

        // If search is active, show ALL matching tasks across all lists (ignore list selection)
        if !searchText.isEmpty {
            tasks = applySearchFilter(tasks, query: searchText)
            // Apply default completion filter (hide completed by default)
            tasks = applyCompletionFilter(tasks, filterCompletion: "default")
            // Sort by priority
            tasks = applySorting(tasks, sortBy: "priority")
            return tasks
        }

        // If viewing from featured, merge featuredListTasks with user's own tasks
        // This mirrors how regular lists work: taskService.tasks is the source of truth
        // for the user's tasks, featuredListTasks provides other users' public tasks
        if isViewingFromFeatured {
            guard let listId = selectedListId else {
                return []
            }

            // Get user's own tasks for this list from taskService (source of truth)
            // This includes optimistic tasks, edits, etc. - just like regular lists
            let userTasks = taskService.tasks.filter { task in
                task.listIds?.contains(listId) == true
            }

            // Start with other users' tasks from featuredListTasks
            // (tasks we don't own that were fetched from the public list API)
            let currentUserId = AuthManager.shared.userId
            let otherUsersTasks = featuredListTasks.filter { task in
                // Keep tasks we don't own (other users' public tasks)
                task.creatorId != currentUserId && task.assigneeId != currentUserId
            }

            // Merge: user's tasks take precedence (they're more up-to-date)
            tasks = userTasks
            for otherTask in otherUsersTasks {
                // Only add if not already in user's tasks (avoid duplicates)
                if !tasks.contains(where: { $0.id == otherTask.id }) {
                    tasks.append(otherTask)
                }
            }

            // Apply list filters if we have a selected list
            if let selectedList = selectedList {
                tasks = applyListFilters(tasks, list: selectedList)
                // Apply sorting based on list's sortBy setting
                tasks = applySorting(tasks, sortBy: selectedList.sortBy ?? "manual")
            }

            return tasks
        }

        // Handle special "my-tasks" virtual list
        if selectedListId == "my-tasks" {
            // Filter to show tasks assigned to current user ONLY
            if let currentUserId = AuthManager.shared.userId {
                tasks = tasks.filter { task in
                    task.assigneeId == currentUserId
                }
            } else {
                tasks = []
            }

            // Apply user's saved filter preferences (synced across devices)
            let completion = myTasksPreferences.preferences.filterCompletion ?? "default"
            let priority = myTasksPreferences.preferences.filterPriority ?? []
            let dueDate = myTasksPreferences.preferences.filterDueDate ?? "all"
            let sortBy = myTasksPreferences.preferences.sortBy ?? "auto"

            tasks = applyCompletionFilter(tasks, filterCompletion: completion)

            if !priority.isEmpty {
                tasks = tasks.filter { priority.contains($0.priority.rawValue) }
            }

            if dueDate != "all" {
                tasks = applyDueDateFilter(tasks, filter: dueDate)
            }

            // Apply user's saved sorting preference
            tasks = applySorting(tasks, sortBy: sortBy)
            return tasks
        }

        // Filter by selected list
        if let selectedList = selectedList {
            // Check if list is virtual (saved filter)
            if selectedList.isVirtual == true {
                // Apply all filters for virtual list
                tasks = applyListFilters(tasks, list: selectedList)
            } else {
                // Regular list - filter by membership first
                tasks = tasks.filter { task in
                    // Check both lists array and listIds array
                    let hasInLists = task.lists?.contains(where: { $0.id == selectedList.id }) ?? false
                    let hasInListIds = task.listIds?.contains(selectedList.id) ?? false
                    return hasInLists || hasInListIds
                }

                // Then apply list filters (completion, priority, assignee, etc.)
                tasks = applyListFilters(tasks, list: selectedList)
            }

            // Apply sorting based on list's sortBy setting
            tasks = applySorting(tasks, sortBy: selectedList.sortBy ?? "manual")
        } else {
            // No list selected - show all tasks but still apply default completion filter
            tasks = applyCompletionFilter(tasks, filterCompletion: "default")
            // Apply default sorting
            tasks = applySorting(tasks, sortBy: "priority")
        }

        return tasks
    }

    private func applyListFilters(_ tasks: [Task], list: TaskList) -> [Task] {
        var filtered = tasks

        // Completion filter — honors the list's per-list
        // recentlyCompletedWindow so iOS matches the web (which already
        // does this via shouldShowCompletedByFilter in useFilterState).
        // Previously hardcoded to 24h, which is why tasks visible on web
        // weren't visible on iOS for lists with a longer window.
        let completionFilter = list.filterCompletion ?? "default"
        filtered = applyCompletionFilterWithWindow(
            filtered,
            filter: completionFilter,
            window: list.recentlyCompletedWindow
        )

        // Priority filter
        if let priority = list.filterPriority, priority != "all" {
            if let priorityInt = Int(priority) {
                filtered = filtered.filter { $0.priority.rawValue == priorityInt }
            }
        }

        // Due date filter
        if let dueDate = list.filterDueDate, dueDate != "all" {
            filtered = applyDueDateFilter(filtered, filter: dueDate)
        }

        // Assignee filter
        if let assignee = list.filterAssignee, assignee != "all" {
            switch assignee {
            case "current_user":
                // Filter to show only tasks assigned to current user
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.assigneeId == currentUserId }
                } else {
                    // No current user - show no tasks
                    filtered = []
                }
            case "not_current_user":
                // Filter to show only tasks NOT assigned to current user
                // Used by "I've Assigned" virtual list
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.assigneeId != currentUserId && $0.assigneeId != nil }
                } else {
                    // No current user - show all assigned tasks
                    filtered = filtered.filter { $0.assigneeId != nil }
                }
            case "unassigned":
                filtered = filtered.filter { $0.assigneeId == nil }
            default:
                // Specific user ID
                filtered = filtered.filter { $0.assigneeId == assignee }
            }
        }

        // Assigned By filter
        // Filter by who created/assigned the task
        if let assignedBy = list.filterAssignedBy, assignedBy != "all" {
            switch assignedBy {
            case "current_user":
                // Show tasks assigned BY current user
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.isCreatedBy(currentUserId) }
                } else {
                    filtered = []
                }
            case "not_current_user":
                // Show tasks NOT assigned by current user
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { !$0.isCreatedBy(currentUserId) }
                }
            default:
                // Specific user ID
                filtered = filtered.filter { $0.isCreatedBy(assignedBy) }
            }
        }

        // In Lists filter
        // Filter by list membership
        if let inLists = list.filterInLists, inLists != "dont_filter" {
            switch inLists {
            case "not_in_list":
                // Show tasks that are NOT in any list
                // Used by "Not in a List" virtual list
                filtered = filtered.filter { task in
                    let hasLists = (task.lists?.count ?? 0) > 0
                    let hasListIds = (task.listIds?.count ?? 0) > 0
                    return !hasLists && !hasListIds
                }
            case "in_list":
                // Show tasks that ARE in at least one list
                filtered = filtered.filter { task in
                    let hasLists = (task.lists?.count ?? 0) > 0
                    let hasListIds = (task.listIds?.count ?? 0) > 0
                    return hasLists || hasListIds
                }
            case "public_lists":
                // Show tasks in public lists
                // Used by "Public Lists" virtual list
                filtered = filtered.filter { task in
                    task.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false
                }
            default:
                break
            }
        }

        return filtered
    }

    /// Check if manual sorting is enabled for the current list
    /// List ids to hide as chips on each task row — namely the list
    /// the user is currently viewing. Virtual lists (`my-tasks`,
    /// `search`, featured) don't have a meaningful id to hide.
    private var rowHiddenListIds: Set<String> {
        guard let listId = selectedListId,
              !["my-tasks", "search", "shared", "favorites"].contains(listId),
              !isViewingFromFeatured else {
            return []
        }
        return [listId]
    }

    private var isManualSortEnabled: Bool {
        // Handle My Tasks separately
        if selectedListId == "my-tasks" {
            return myTasksPreferences.preferences.sortBy == "manual"
        }

        // For regular lists: must exist, not be virtual, and have manual sort enabled
        guard let list = selectedList,
              list.isVirtual != true else {
            return false
        }

        // Check if list's sortBy is set to "manual"
        return list.sortBy == "manual"
    }

    /// Handle task reordering via drag & drop
    private func moveTask(from source: IndexSet, to destination: Int) {
        // Only allow reordering when manual sort is enabled
        guard isManualSortEnabled,
              let listId = selectedListId else {
            return
        }


        // Get ALL tasks in this list (not just filtered - need to include completed tasks, etc.)
        let allTasksInList = taskService.tasks.filter { task in
            task.lists?.contains(where: { $0.id == listId }) ?? false ||
            task.listIds?.contains(listId) ?? false
        }

        // Get currently displayed (filtered) tasks
        var displayedTasks = filteredTasks
        displayedTasks.move(fromOffsets: source, toOffset: destination)

        // Start with the new order from displayed tasks
        var completeOrder = displayedTasks.map { $0.id }

        // Append tasks that exist in the list but aren't currently displayed
        // Order them by creation date descending (newest first)
        let displayedTaskIds = Set(completeOrder)
        let hiddenTasks = allTasksInList.filter { !displayedTaskIds.contains($0.id) }
        let hiddenTasksSorted = hiddenTasks.sorted { task1, task2 in
            let date1 = task1.createdAt ?? Date.distantPast
            let date2 = task2.createdAt ?? Date.distantPast
            return date1 > date2  // Descending (newest first)
        }
        completeOrder.append(contentsOf: hiddenTasksSorted.map { $0.id })


        // Update order via API (no optimistic update - SwiftUI handles visual reordering)
        _Concurrency.Task {
            do {
                if listId == "my-tasks" {
                    // Update My Tasks manual order in preferences
                    var updatedPrefs = myTasksPreferences.preferences
                    updatedPrefs.manualSortOrder = completeOrder
                    await myTasksPreferences.updatePreferences(updatedPrefs)
                } else {
                    // Update list's manual order
                    try await listService.updateManualOrder(listId: listId, order: completeOrder)
                }
            } catch {
            }
        }
    }

    private func applyCompletionFilter(_ tasks: [Task], filterCompletion: String) -> [Task] {
        // Delegate to the shared pure helper (nil window = legacy 24h default).
        // It keys the recently-completed window on completedAt — the real
        // completion time, backdatable by sync — falling back to updatedAt.
        // A private updatedAt-based copy here once made every Google-backfill
        // import (completed 2010, row written just now) visible in My Tasks:
        // hundreds of rows inserting above the viewport as the backfill
        // drained — the "list flickers up and down" bug.
        applyCompletionFilterWithWindow(tasks, filter: filterCompletion, window: nil)
    }

    private func applyDueDateFilter(_ tasks: [Task], filter: String) -> [Task] {
        // Use UTC calendar for all-day tasks, local for timed tasks
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let localCalendar = Calendar.current

        let now = Date()

        // CRITICAL: For all-day tasks, use LOCAL calendar date to create UTC midnight
        // Example: 10 PM Jan 15 PST → create Jan 15 00:00 UTC (not Jan 16 00:00 UTC)
        let localComponents = localCalendar.dateComponents([.year, .month, .day], from: now)
        let todayUTC = utcCalendar.date(from: localComponents)!
        let todayLocal = localCalendar.startOfDay(for: now)

        return tasks.filter { task in
            guard let dueDateTime = task.dueDateTime else {
                return filter == "no_date"
            }

            // Choose calendar based on isAllDay
            let calendar = task.isAllDay ? utcCalendar : localCalendar
            let today = task.isAllDay ? todayUTC : todayLocal
            let dueDate = calendar.startOfDay(for: dueDateTime)

            // Overdue incomplete tasks should appear in time-bound filters
            let isOverdueIncomplete = dueDate < today && !task.completed

            switch filter {
            case "overdue":
                return dueDate < today && !task.completed
            case "today":
                return dueDate == today || isOverdueIncomplete
            case "this_week":
                let weekFromNow = calendar.date(byAdding: .day, value: 7, to: today)!
                return (dueDate >= today && dueDate <= weekFromNow) || isOverdueIncomplete
            case "this_month":
                let monthFromNow = calendar.date(byAdding: .day, value: 30, to: today)!
                return (dueDate >= today && dueDate <= monthFromNow) || isOverdueIncomplete
            case "no_date":
                return false
            default:
                return true
            }
        }
    }

    private func applySorting(_ tasks: [Task], sortBy: String) -> [Task] {
        switch sortBy {
        case "auto":
            // Auto sort: Completion status → Priority → Due date
            // Completed tasks go to the bottom
            return tasks.sorted { task1, task2 in
                // 1. Completion status (incomplete first, completed at bottom)
                if task1.completed != task2.completed {
                    return !task1.completed  // Incomplete tasks first
                }

                // 2. Priority (higher first)
                if task1.priority.rawValue != task2.priority.rawValue {
                    return task1.priority.rawValue > task2.priority.rawValue
                }

                // 3. Due date (earlier first, no date at end)
                let date1 = task1.dueDateTime
                let date2 = task2.dueDateTime

                if let d1 = date1, let d2 = date2 {
                    return d1 < d2
                } else if date1 != nil {
                    return true  // Tasks with dates come before tasks without
                } else if date2 != nil {
                    return false
                }

                // 4. Creation date (earlier first) as tiebreaker
                let created1 = task1.createdAt ?? Date.distantPast
                let created2 = task2.createdAt ?? Date.distantPast
                return created1 < created2
            }

        case "priority":
            // Sort by priority (high to low), then by due date (earliest first)
            // Completed tasks go to the bottom
            return tasks.sorted { task1, task2 in
                // Completed tasks at the bottom
                if task1.completed != task2.completed {
                    return !task1.completed
                }

                if task1.priority.rawValue != task2.priority.rawValue {
                    return task1.priority.rawValue > task2.priority.rawValue
                }
                // If priority is the same, sort by due date
                // Use whenTime (timed tasks) if available, otherwise when (all-day tasks)
                let date1 = task1.dueDateTime
                let date2 = task2.dueDateTime

                if let d1 = date1, let d2 = date2 {
                    return d1 < d2
                } else if date1 != nil {
                    return true  // Tasks with dates come before tasks without
                } else if date2 != nil {
                    return false
                }
                // If both have no date, maintain original order
                return false
            }

        case "when":
            // Sort by due date (earliest first), then by priority
            // Completed tasks go to the bottom
            return tasks.sorted { task1, task2 in
                // Completed tasks at the bottom
                if task1.completed != task2.completed {
                    return !task1.completed
                }

                // Use whenTime (timed tasks) if available, otherwise when (all-day tasks)
                let date1 = task1.dueDateTime
                let date2 = task2.dueDateTime

                if let d1 = date1, let d2 = date2 {
                    if d1 != d2 {
                        return d1 < d2
                    }
                    // If dates are the same, sort by priority
                    return task1.priority.rawValue > task2.priority.rawValue
                } else if date1 != nil {
                    return true  // Tasks with dates come before tasks without
                } else if date2 != nil {
                    return false
                }
                // If both have no date, sort by priority
                return task1.priority.rawValue > task2.priority.rawValue
            }

        case "createdAt":
            // Sort by creation date (newest first)
            return tasks.sorted { task1, task2 in
                let date1 = task1.createdAt ?? Date.distantPast
                let date2 = task2.createdAt ?? Date.distantPast
                return date1 > date2
            }

        case "manual":
            // Manual sorting - use manualSortOrder from list or My Tasks preferences
            let manualOrder: [String]?

            // Check if this is My Tasks - use preferences
            if selectedListId == "my-tasks" {
                manualOrder = myTasksPreferences.preferences.manualSortOrder
            } else {
                // Use list's manual sort order
                manualOrder = selectedList?.manualSortOrder
            }

            guard let order = manualOrder, !order.isEmpty else {
                // No manual order defined, fall back to creation date descending (newest first)
                return tasks.sorted { task1, task2 in
                    let date1 = task1.createdAt ?? Date.distantPast
                    let date2 = task2.createdAt ?? Date.distantPast
                    return date1 > date2  // Descending (newest first)
                }
            }

            // Create a map of task ID to index in manual order
            let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })

            // Sort tasks by their position in manualSortOrder
            // Tasks not in the order appear at the end, sorted by creation date
            return tasks.sorted { task1, task2 in
                let index1 = orderMap[task1.id]
                let index2 = orderMap[task2.id]

                switch (index1, index2) {
                case let (i1?, i2?):
                    // Both tasks are in the manual order
                    return i1 < i2
                case (_?, nil):
                    // Only task1 is in the manual order
                    return true
                case (nil, _?):
                    // Only task2 is in the manual order
                    return false
                case (nil, nil):
                    // Neither task is in the manual order, sort by creation date descending (newest first)
                    let date1 = task1.createdAt ?? Date.distantPast
                    let date2 = task2.createdAt ?? Date.distantPast
                    return date1 > date2  // Descending (newest first)
                }
            }

        default:
            // Default to auto sorting (completion → priority → due date)
            return applySorting(tasks, sortBy: "auto")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            // Use reusable EmptyStateView component with Astrid character
            // No button needed - both phone and iPad now use bottom quick add bar
            EmptyStateView(
                message: getEmptyStateMessage(),
                buttonTitle: nil,
                buttonAction: nil
            )
            .frame(minHeight: UIScreen.main.bounds.height - 200) // Ensure scrollable for pull-to-refresh
        }
        .refreshable {
            try? await loadData()
            GitHubSyncService.shared.scheduleSync()
            GoogleTasksSyncService.shared.scheduleSync()
        }
    }

    /// Get contextual empty state message based on list type
    private func getEmptyStateMessage() -> String {
        // Search mode
        if selectedListId == "search" {
            if searchText.isEmpty {
                return NSLocalizedString("tasks.search_tasks_placeholder", comment: "Search tasks")
            }
            return NSLocalizedString("empty_state.default", comment: "")
        }

        // If search is active from sidebar, return default creative response
        if !searchText.isEmpty {
            return NSLocalizedString("empty_state.default", comment: "")
        }

        // Handle special "my-tasks" virtual list
        if selectedListId == "my-tasks" {
            return getMyTasksEmptyMessage()
        }

        guard let list = selectedList else {
            return NSLocalizedString("empty_state.default", comment: "")
        }

        // Check if it's a virtual list (saved filter)
        if list.isVirtual == true {
            if let virtualType = list.virtualListType {
                switch virtualType {
                case "my-tasks":
                    return getMyTasksEmptyMessage()
                case "today":
                    return NSLocalizedString("empty_state.today", comment: "")
                default:
                    return NSLocalizedString("empty_state.default", comment: "")
                }
            }
            return NSLocalizedString("empty_state.default", comment: "")
        }

        // Regular list
        if list.privacy == .PUBLIC {
            return NSLocalizedString("empty_state.public_list", comment: "")
        } else if list.privacy == .SHARED {
            return NSLocalizedString("empty_state.shared_list", comment: "")
        } else {
            return String(format: NSLocalizedString("empty_state.list_with_name", comment: ""), list.name)
        }
    }

    /// Get empty state message for My Tasks view
    /// Shows "caught up" message only for users who have completed 10+ tasks
    /// New users see a welcoming message instead
    private func getMyTasksEmptyMessage() -> String {
        // Aligns with web's `AstridEmptyState` (see
        // astrid-web/components/ui/astrid-empty-state.tsx): a single empty
        // message per list type, no completed-task threshold. iOS used to
        // branch to a "caught up" message after 10 completions, but web has
        // no equivalent and this created cross-platform UX inconsistency.
        return NSLocalizedString("empty_state.my_tasks", comment: "")
    }

    // MARK: - Actions

    private func copyList() async {
        guard let _ = selectedList else { return }

        isCopyingList = true
        defer { isCopyingList = false }

        // TODO: Implement copy list API v1 endpoint
    }

    private func loadFeaturedListTasks(listId: String) async {
        isLoadingFeaturedTasks = true
        defer { isLoadingFeaturedTasks = false }

        do {
            let tasks = try await taskService.fetchTasksForListFromServer(listId)

            // Merge optimistic tasks from taskService that belong to this list
            // This ensures newly added tasks don't disappear during the reload
            let optimisticTasks = taskService.tasks.filter {
                $0.id.hasPrefix("temp_") && $0.listIds?.contains(listId) == true
            }

            var mergedTasks = tasks
            for optTask in optimisticTasks {
                if !mergedTasks.contains(where: { $0.id == optTask.id }) {
                    mergedTasks.insert(optTask, at: 0)
                }
            }

            featuredListTasks = mergedTasks
        } catch {
            featuredListTasks = []
        }
    }

    private func loadData() async throws {

        // On My Tasks view, include user tasks to catch tasks not in lists
        // Otherwise, only fetch tasks from lists (faster, lighter)
        let shouldIncludeUserTasks = selectedListId == "my-tasks"

        if shouldIncludeUserTasks {
        }

        // Always do full sync on manual refresh to ensure all tasks are visible
        // This is what users expect from pull-to-refresh behavior
        try await syncManager.performFullSync(includeUserTasks: shouldIncludeUserTasks)

        // If viewing a featured public list, refresh after sync completes
        // This ensures we get the latest server data INCLUDING any newly created tasks
        if isViewingFromFeatured, let listId = selectedListId {
            await loadFeaturedListTasks(listId: listId)
        }

        // Start auto-sync in background (every 60 seconds) - uses incremental sync
        syncManager.startAutoSync()
    }

    private func deleteTasks(at offsets: IndexSet) {
        // Capture tasks before async operations to avoid index out of bounds
        let tasksToDelete: [Task] = offsets.compactMap { index in
            guard index < filteredTasks.count else { return nil }
            return filteredTasks[index]
        }

        for task in tasksToDelete {
            _Concurrency.Task {
                try? await taskService.deleteTask(id: task.id, task: task)
            }
        }
    }

    // MARK: - Helper Methods

    @ViewBuilder
    private func getTaskDetailView(for task: Task) -> some View {
        let isReadOnly = shouldShowTaskAsReadOnly(task: task)
        if isReadOnly {
            TaskDetailViewOnly(task: task)
        } else {
            TaskDetailViewNew(task: task, isReadOnly: false)
        }
    }

    /// Determine if a task should be shown as read-only
    /// Based on web's canUserEditTask logic
    private func shouldShowTaskAsReadOnly(task: Task) -> Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return true // No user, show as read-only
        }

        // CRITICAL: Featured public lists are read-only UNLESS you created the task
        // Tasks you didn't create don't exist in your database yet
        if isViewingFromFeatured && !task.isCreatedBy(currentUserId) {
            return true
        }

        // If viewing featured list but you're the creator, allow editing
        if isViewingFromFeatured && task.isCreatedBy(currentUserId) {
            return false
        }

        // For My Tasks or when no list is associated, tasks are always editable
        if selectedListId == "my-tasks" {
            return false
        }

        // Resolve the authoritative list for permission checks: prefer the
        // selectedList, then the full list from ListService (has complete
        // listMembers from getLists), and only then the task's embedded list.
        // This lets the tasks endpoint omit per-task listMembers (leanListMembers)
        // without breaking role checks.
        guard let taskList = selectedList
            ?? (task.listIds?.compactMap { id in listService.lists.first { $0.id == id } }.first)
            ?? task.lists?.first else {
            return false // No list info, allow edit
        }

        // Get the actual owner ID (prefer ownerId field, fall back to owner.id)
        let listOwnerId = taskList.ownerId ?? taskList.owner?.id

        // If user owns this task's list, all tasks are editable (includes copied lists)
        if listOwnerId == currentUserId {
            return false
        }

        // Check user's role in the list (shared with web semantics).
        let role = taskList.role(for: currentUserId)

        // List owner and admins can always edit.
        if role == .owner || role == .admin {
            return false
        }

        // For public copy-only lists (default), only owner/admin can edit (already handled above).
        // Members and viewers should copy the list to edit tasks.
        if taskList.privacy == .PUBLIC && (taskList.publicListType == "copy_only" || taskList.publicListType == nil) {
            return true // Always read-only for non-owners/non-admins
        }

        // For public collaborative lists, task creator OR admin can edit.
        if taskList.privacy == .PUBLIC && taskList.publicListType == "collaborative" {
            let isCreator = task.isCreatedBy(currentUserId)
            let isAdmin = role == .owner || role == .admin
            return !isCreator && !isAdmin // Read-only unless creator or admin
        }

        // For non-public lists, members can edit.
        return role != .member && role != .owner && role != .admin
    }

    /// Check if user can add tasks to a list (matching web's canUserEditTasks).
    /// Role source is the shared `TaskList.role(for:)` — see `TaskList.swift`.
    private func canUserAddTasks(userId: String, list: TaskList) -> Bool {
        let role = list.role(for: userId)

        // For public copy-only lists (default), only owner/admin can add tasks.
        // Members and viewers should copy the list to add/edit tasks.
        if list.privacy == .PUBLIC && (list.publicListType == "copy_only" || list.publicListType == nil) {
            return role == .owner || role == .admin
        }

        // For public collaborative lists, viewers can also add tasks.
        if list.privacy == .PUBLIC && list.publicListType == "collaborative" {
            return role != nil
        }

        // Default: owner, admin, or member can add tasks.
        return role == .owner || role == .admin || role == .member
    }

    private func handleListUpdate(original: TaskList, updated: TaskList) {
        _Concurrency.Task {

            var updates: [String: Any] = [:]

            // Check name
            if updated.name != original.name {
                updates["name"] = updated.name
            }

            // Check description
            if updated.description != original.description {
                updates["description"] = updated.description ?? ""
            }

            // Check sortBy
            if updated.sortBy != original.sortBy {
                updates["sortBy"] = updated.sortBy ?? "manual"
            }

            // List Defaults
            if updated.defaultPriority != original.defaultPriority {
                updates["defaultPriority"] = updated.defaultPriority ?? 0
            }
            if updated.defaultDueDate != original.defaultDueDate {
                updates["defaultDueDate"] = updated.defaultDueDate ?? "none"
            }
            if updated.defaultDueTime != original.defaultDueTime {
                // Use NSNull() for nil to ensure key is sent to backend (nil removes key in Swift)
                updates["defaultDueTime"] = updated.defaultDueTime != nil ? updated.defaultDueTime! : NSNull()
            }
            if updated.defaultIsPrivate != original.defaultIsPrivate {
                updates["defaultIsPrivate"] = updated.defaultIsPrivate ?? true
            }
            if updated.defaultRepeating != original.defaultRepeating {
                updates["defaultRepeating"] = updated.defaultRepeating ?? "never"
            }
            if updated.defaultAssigneeId != original.defaultAssigneeId {
                // Use NSNull() for nil to ensure key is sent to backend (nil removes key in Swift)
                let valueToSend: Any = updated.defaultAssigneeId != nil ? updated.defaultAssigneeId! : NSNull()
                updates["defaultAssigneeId"] = valueToSend
            }

            // Filters
            if updated.filterPriority != original.filterPriority {
                updates["filterPriority"] = updated.filterPriority ?? "all"
            }
            if updated.filterAssignee != original.filterAssignee {
                updates["filterAssignee"] = updated.filterAssignee ?? "all"
            }
            if updated.filterDueDate != original.filterDueDate {
                updates["filterDueDate"] = updated.filterDueDate ?? "all"
            }
            if updated.filterCompletion != original.filterCompletion {
                updates["filterCompletion"] = updated.filterCompletion ?? "default"
            }
            if updated.filterAssignedBy != original.filterAssignedBy {
                updates["filterAssignedBy"] = updated.filterAssignedBy ?? "all"
            }
            if updated.filterRepeating != original.filterRepeating {
                updates["filterRepeating"] = updated.filterRepeating ?? "all"
            }
            if updated.filterInLists != original.filterInLists {
                updates["filterInLists"] = updated.filterInLists ?? "dont_filter"
            }

            // Privacy
            if updated.privacy != original.privacy {
                updates["privacy"] = updated.privacy?.rawValue ?? "PRIVATE"
            }

            // Image URL
            if updated.imageUrl != original.imageUrl {
                updates["imageUrl"] = updated.imageUrl ?? NSNull()
            }

            // Save if there are updates
            if !updates.isEmpty {

                do {
                    _ = try await listService.updateListAdvanced(listId: updated.id, updates: updates)
                    // Note: Not calling fetchLists() - updateListAdvanced already updates local lists with server response
                } catch {
                    // Advanced-update errors are non-fatal; local state already applied.
                }
            }
        }
    }

    private func handleListDelete(listId: String) {
        _Concurrency.Task {
            try? await listService.deleteList(listId: listId)
            selectedListId = "my-tasks"  // Redirect to My Tasks instead of All Tasks
        }
        showingListSettings = false
    }

    private func handleListLeave(listId: String) {
        showingListSettings = false
        selectedListId = "my-tasks"
        _Concurrency.Task {
            _ = try? await listService.fetchLists()
        }
    }

    // MARK: - Theme Helpers

    /// Header background with support for all themes
    @ViewBuilder
    private var headerBackground: some View {
        if effectiveTheme == "light" {
            // Light theme: Use thin material for glass effect
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else if effectiveTheme == "ocean" {
            Color.white  // Solid white header on Ocean theme
        } else {
            getHeaderBackground()
        }
    }

    /// Get header background color based on current theme
    private func getHeaderBackground() -> Color {
        if effectiveTheme == "ocean" {
            return Color.white  // Solid white header on Ocean theme
        }
        return effectiveTheme == "dark" ? Theme.Dark.headerBg : Theme.headerBg
    }

    /// Get primary background color based on current theme
    private func getPrimaryBackground() -> Color {
        if effectiveTheme == "ocean" {
            return Theme.Ocean.bgPrimary  // Cyan for Ocean
        }
        return effectiveTheme == "dark" ? Theme.Dark.bgPrimary : Theme.bgPrimary
    }

}

#Preview {
    TaskListView()
}
