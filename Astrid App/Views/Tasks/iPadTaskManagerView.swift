import SwiftUI

/// Wrapper view that adapts TaskListView for iPad side panel presentation
/// Instead of opening tasks in a sheet, it sets the selectedTask binding
/// which the parent iPadTaskManagerView uses to show the detail panel
private struct iPadTaskListView: View {
    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?
    @Binding var searchText: String
    @Binding var selectedTask: Task?
    var onMenuTap: (() -> Void)?
    var onViewModeChange: ((HeaderToggleSegment) -> Void)?

    var body: some View {
        TaskListView(
            selectedListId: $selectedListId,
            isViewingFromFeatured: $isViewingFromFeatured,
            featuredList: $featuredList,
            searchText: $searchText,
            selectedTaskForPanel: $selectedTask,
            onMenuTap: onMenuTap,
            onViewModeChange: onViewModeChange,
            // List messages get their own pane out here, so the rotator must not
            // offer them as a view that replaces the list (a34d0163).
            messagesArePinnedBeside: true
        )
    }
}

/// iPad-specific task manager view with adaptive column layout
/// Landscape: sidebar | task list | task details (always 3-column, details ~50% width)
/// Portrait: task list | task details (sidebar hidden, accessible via hamburger menu)
struct iPadTaskManagerView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @AppStorage("iPadLandscapeColumns") private var landscapeColumns: Int = 3
    @AppStorage("iPadPortraitMode") private var portraitMode: String = "twoColumn"
    @EnvironmentObject var authManager: AuthManager

    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?

    // Search state (managed at this level, passed to sidebar and task list)
    @State private var searchText = ""
    @State private var shouldScrollSidebarToTop = false

    // Selected task for detail panel
    @State private var selectedTask: Task?
    /// What the list column is currently drawing, reported by TaskListView's rotator. The pane
    /// layout turns on it: messages ride beside a LIST, and stand down for a board (a34d0163).
    @State private var listViewMode: HeaderToggleSegment = .list
    @AppStorage("iPadBoardFullScreen") private var boardFullScreen: Bool = false
    // Expanded task detail (task c5ba07ed). Persisted like the Mac's macDetailFullScreen, so a
    // panel you expanded is still expanded next launch.
    @AppStorage("iPadDetailFullScreen") private var detailFullScreen: Bool = false

    // Portrait mode: sidebar shown via sliding overlay (like iPhone)
    @State private var showingSidebar = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasScrolledDuringDrag = false

    /// One canonical curve for the detail panel's slide, so every close path
    /// (tap-again, swipe, close button, list switch) feels identical and smooth.
    private static let panelAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.92)

    // Calculate animation progress for sidebar slide (portrait mode)
    private var sidebarProgress: CGFloat {
        let targetOffset = UIScreen.main.bounds.width * 0.40  // 40% width for iPad sidebar
        if showingSidebar {
            let currentOffset = targetOffset + dragOffset
            return max(0, min(1, currentOffset / targetOffset))
        } else {
            return max(0, min(1, dragOffset / targetOffset))
        }
    }

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    // Theme-aware background
    @ViewBuilder
    private var themeBackground: some View {
        switch effectiveTheme {
        case .ocean:
            Theme.Ocean.bgPrimary  // Cyan for Ocean
        case .dark:
            Theme.Dark.bgPrimary  // Dark gray for Dark theme
        case .light:
            Theme.bgPrimary  // White for Light theme
        case .auto:
            // Should never reach here since effectiveTheme resolves auto
            Theme.bgPrimary
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Use geometry to detect landscape (width > height) since iPad has .regular size class in both orientations
            let isLandscapeOrientation = geometry.size.width > geometry.size.height

            if isLandscapeOrientation {
                if landscapeColumns == 2 {
                    // Landscape 2-column: sliding sidebar (like portrait)
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: true)
                } else {
                    // Landscape 3-column: sidebar permanently visible | tasks | details
                    threeColumnLandscapeLayout(width: geometry.size.width)
                }
            } else {
                if portraitMode == "iPhone" {
                    // Portrait single-column is now handled by MainTabView using iPhoneLayout.
                    // This branch is a fallback — use portrait 2-column layout.
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: false)
                } else {
                    // Portrait 2-column: sliding sidebar
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: false)
                }
            }
        }
        .withReminderPresentation()
        // Route presenter-driven task opens (subtask rows, parent-task links,
        // deep links) into the side detail panel instead of the list column's
        // navigation stack.
        .onAppear {
            TaskPresenter.shared.panelHandler = { task in
                selectedTask = task
            }
        }
        .onDisappear {
            TaskPresenter.shared.panelHandler = nil
        }
        // Close task details when list changes. Bare assignment — the container's
        // panelAnimation drives the slide-out (a nested withAnimation here fought it).
        .onChange(of: selectedListId) { _, _ in
            selectedTask = nil
        }
    }

    // MARK: - 3-Column Landscape Layout (Sidebar permanently visible)

    @ViewBuilder
    private func threeColumnLandscapeLayout(width: CGFloat) -> some View {
        let showsMessages = showsMessagesPane(columns: 3)
        let panes = iPadPaneLayout.widths(total: width, columns: 3,
                                          showsMessages: showsMessages,
                                          boardFullScreen: isBoardFullScreen)
        let detailWidth = iPadPaneLayout.detailWidth(total: width, columns: 3,
                                                     showsMessages: showsMessages,
                                                     isFullScreen: detailFullScreen)

        ZStack {
            // Full-screen background (fills safe areas — fixes black in dark mode)
            themeBackground
                .ignoresSafeArea()

        HStack(spacing: 0) {
            // Left: list picker — permanently visible, except under a full-screen board.
            if panes.sidebar > 0 {
                NavigationStack {
                    ListSidebarView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        shouldScrollToTop: $shouldScrollSidebarToTop
                    )
                    .environmentObject(authManager)
                }
                .frame(width: panes.sidebar)
                .background(themeBackground)

                Divider()
            }

            // Centre: task list (or board). Right: list messages. The task detail is a
            // trailing OVERLAY sized to the messages pane, so opening a task covers the
            // messages and never the list you are working in (a34d0163).
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    Group {
                        if selectedListId == "settings" {
                            NavigationStack {
                                SettingsView()
                                    .environmentObject(authManager)
                            }
                        } else if selectedListId == "profile", let userId = authManager.userId {
                            NavigationStack {
                                UserProfileView(userId: userId, isRootDestination: true)
                                    .environmentObject(authManager)
                            }
                        } else {
                            // No onMenuTap - hamburger does nothing in landscape since sidebar is always visible
                            iPadTaskListView(
                                selectedListId: $selectedListId,
                                isViewingFromFeatured: $isViewingFromFeatured,
                                featuredList: $featuredList,
                                searchText: $searchText,
                                selectedTask: $selectedTask,
                                onMenuTap: nil,
                                onViewModeChange: { listViewMode = $0 }
                            )
                        }
                    }
                    .frame(width: panes.list)

                    if showsMessages, let listId = selectedListId {
                        messagesPane(listId: listId, width: panes.messages)
                    }
                }
                .frame(width: width - panes.sidebar)

                if let task = selectedTask {
                    taskDetailPanel(for: task)
                        .frame(width: detailWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: width - panes.sidebar)
            // Slide the detail overlay + board scroll room in/out on selection.
            .animation(Self.panelAnimation, value: selectedTask?.id)
        }
        } // ZStack
    }

    // MARK: - Panes (Task a34d0163)

    /// Does the messages pane belong beside the list right now?
    private func showsMessagesPane(columns: Int) -> Bool {
        iPadPaneLayout.showsMessages(columns: columns, viewMode: listViewMode,
                                     listId: selectedListId, boardFullScreen: isBoardFullScreen)
    }

    /// Full screen only means anything while a board is on screen — the flag persists, so a
    /// board you expanded stays expanded, but a list view must never lose its picker to it.
    private var isBoardFullScreen: Bool {
        boardFullScreen && listViewMode == .board
    }

    /// List messages, styled to sit beside the list rather than float over it.
    private func messagesPane(listId: String, width: CGFloat) -> some View {
        ChatPanelView(listId: listId)
            .frame(width: width)
            .background(themeBackground)
            .overlay(alignment: .leading) { Divider() }
    }

    // MARK: - Portrait Layout (Sliding sidebar like iPhone)
    // Portrait mode: sidebar slides in from left when hamburger button is tapped
    // Task list and details slide right to reveal sidebar underneath

    @ViewBuilder
    private func threeColumnPortraitLayout(width: CGFloat, isLandscape: Bool) -> some View {
        let sidebarWidth = width * 0.40  // 40% drawer width for iPad
        let showsMessages = showsMessagesPane(columns: 2)
        let panes = iPadPaneLayout.widths(total: width, columns: 2,
                                          showsMessages: showsMessages,
                                          boardFullScreen: isBoardFullScreen)
        let detailWidth = iPadPaneLayout.detailWidth(total: width, columns: 2,
                                                     showsMessages: showsMessages,
                                                     isFullScreen: detailFullScreen)

        ZStack(alignment: .leading) {
            // Full-screen background
            themeBackground
                .ignoresSafeArea()

            // Sidebar - always rendered underneath, visible when content slides right
            ZStack {
                themeBackground
                    .ignoresSafeArea()

                NavigationStack {
                    ListSidebarView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        shouldScrollToTop: $shouldScrollSidebarToTop,
                        onListTap: {
                            // Scroll sidebar to top first, then close
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                    )
                    .environmentObject(authManager)
                }
            }
            .frame(width: sidebarWidth)
            // Subtle rise animation synced with drag progress
            .scaleEffect(0.95 + (0.05 * sidebarProgress))
            .offset(y: 20 - (20 * sidebarProgress))
            .opacity(0.8 + (0.2 * sidebarProgress))

            // Main content - slides right to reveal sidebar. The task detail is a
            // trailing OVERLAY so the list/board keeps its full width (and doesn't
            // reflow) when a task opens.
            ZStack(alignment: .trailing) {
                // Task List, Settings, or Profile
                if selectedListId == "settings" {
                    NavigationStack {
                        SettingsView(onMenuTap: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        })
                            .environmentObject(authManager)
                    }
                    .frame(width: width)
                } else if selectedListId == "profile", let userId = authManager.userId {
                    NavigationStack {
                        UserProfileView(userId: userId, isRootDestination: true)
                            .environmentObject(authManager)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { value in
                                        let isHorizontal = value.translation.width > abs(value.translation.height)
                                        let isRight = value.translation.width > 0
                                        let meetsThreshold = value.translation.width > 80
                                            || value.predictedEndTranslation.width > 200
                                        if isHorizontal && isRight && meetsThreshold {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                showingSidebar = true
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                let impact = UIImpactFeedbackGenerator(style: .light)
                                                impact.impactOccurred()
                                            }
                                        }
                                    }
                            )
                    }
                    .frame(width: width)
                } else {
                    // Task list + list messages side by side. The picker stays the sliding
                    // drawer here, so it costs no width (a34d0163).
                    HStack(spacing: 0) {
                        iPadTaskListView(
                            selectedListId: $selectedListId,
                            isViewingFromFeatured: $isViewingFromFeatured,
                            featuredList: $featuredList,
                            searchText: $searchText,
                            selectedTask: $selectedTask,
                            onMenuTap: {
                                // Dismiss keyboard first
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                // Open sidebar
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    showingSidebar = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }
                            },
                            onViewModeChange: { listViewMode = $0 }
                        )
                        .frame(width: panes.list)

                        if showsMessages, let listId = selectedListId {
                            messagesPane(listId: listId, width: panes.messages)
                        }
                    }
                    .frame(width: width)
                }

                // Task Detail Panel — sized to the messages pane so details appear OVER the
                // messages and the task list stays visible. With no messages pane it keeps
                // the half-width it has always had. The panel self-styles (rounded card,
                // shadow, clear corners).
                if let task = selectedTask {
                    taskDetailPanel(for: task)
                        .frame(width: detailWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: width)
            // Slide the detail overlay (and the board's scroll room) in/out when
            // the selected task changes. The flat list opts out so its selected
            // row highlights instantly.
            .animation(Self.panelAnimation, value: selectedTask?.id)
            .offset(x: showingSidebar ? sidebarWidth + dragOffset : dragOffset)
            .shadow(color: .black.opacity(0.3 * sidebarProgress), radius: 10, x: -5, y: 0)
            .opacity(1.0 - (0.3 * sidebarProgress))
            .saturation(1.0 - (0.5 * sidebarProgress))
            .allowsHitTesting(sidebarProgress < 0.95)
            // Swipe left-to-right on the LIST. In PORTRAIT it reveals the sliding
            // sidebar (matches iPhone), closing any open task on the way. In
            // LANDSCAPE there's room for everything, so it only closes the open
            // task to reveal the list — it must NOT pull in the sidebar. A swipe
            // that starts over the open task's panel is handled by the panel's own
            // gesture, so it's excluded here.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard !showingSidebar else { return }
                        guard isRightwardSwipeGesture(
                            translationWidth: value.translation.width,
                            translationHeight: value.translation.height,
                            predictedEndTranslationWidth: value.predictedEndTranslation.width
                        ) else { return }
                        // Only act for swipes that begin in the list area; the task
                        // detail panel (the trailing pane when open) handles its own.
                        let listWidth = selectedTask != nil ? width - detailWidth : width
                        guard value.startLocation.x < listWidth else { return }
                        if isLandscape && selectedTask != nil {
                            // Landscape WITH a task open: just close it to reveal the
                            // list. Bare — the container animates the panel slide.
                            selectedTask = nil
                        } else {
                            // Otherwise — portrait, or a landscape list/board with no
                            // task open — reveal the sliding sidebar (the "open list
                            // menu" gesture), closing any open task on the way. The
                            // panel slide is driven by the container; only the sidebar
                            // drawer is animated here.
                            selectedTask = nil
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
            )

            // Overlay to capture taps/drags when sidebar is open
            if showingSidebar {
                HStack(spacing: 0) {
                    // Left side - sidebar area, taps pass through
                    Color.clear
                        .frame(width: sidebarWidth)
                        .allowsHitTesting(false)

                    // Right side - main content area, captures drags and taps to close
                    Color.clear
                        .frame(width: width - sidebarWidth)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if !hasScrolledDuringDrag && value.translation.width < 0 {
                                        shouldScrollSidebarToTop = true
                                        hasScrolledDuringDrag = true
                                    }
                                    if value.translation.width < 0 {
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    hasScrolledDuringDrag = false
                                    if value.translation.width < -100 || value.predictedEndTranslation.width < -200 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            showingSidebar = false
                                            dragOffset = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            shouldScrollSidebarToTop = false
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                            dragOffset = 0
                                        }
                                        shouldScrollSidebarToTop = false
                                    }
                                }
                        )
                        .onTapGesture {
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Task Detail Panel

    // Takes the task as a parameter (not read from selectedTask) so that when the
    // panel closes, SwiftUI keeps rendering this content through the slide-out
    // transition instead of it vanishing the instant selectedTask goes nil.
    @ViewBuilder
    private func taskDetailPanel(for task: Task) -> some View {
            // Wrap with theme background and padding to align with task list
            NavigationStack {
                TaskDetailViewNew(
                    task: task,
                    isReadOnly: shouldShowTaskAsReadOnly(task: task),
                    onClose: { selectedTask = nil },
                    isFullScreen: detailFullScreen,
                    onToggleFullScreen: {
                        withAnimation(Self.panelAnimation) { detailFullScreen.toggle() }
                    }
                )
            }
            .background(themeBackground)  // Fills BEHIND the rounded card only (inside the clip)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // compositingGroup so the shadow is cached and translated during the
            // slide, not re-rasterized from the clipped alpha every frame.
            .compositingGroup()
            // Shadow on the rounded card; the area outside it (padding + corners)
            // stays clear so the list/board shows through.
            .shadow(color: .black.opacity(0.18), radius: 10, x: -4, y: 0)
            .padding(.top, 8)      // Top margin (aligns with floating header)
            .padding(.bottom, 4)   // Bottom margin (aligns with quick add input)
            .padding(.trailing, 8) // Right margin (matches left side of screen)
            // Swipe left-to-right on the open task closes it (matches iPhone
            // swipe-back). The detail panel is a side panel on iPad, not a pushed
            // view, so this gesture is what dismisses it.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if isRightwardSwipeGesture(
                            translationWidth: value.translation.width,
                            translationHeight: value.translation.height,
                            predictedEndTranslationWidth: value.predictedEndTranslation.width
                        ) {
                            selectedTask = nil  // container animates the slide-out
                        }
                    }
            )
            .id(task.id) // Force view refresh when task changes
    }


    // MARK: - Helper Methods

    /// Determine if a task should be shown as read-only
    private func shouldShowTaskAsReadOnly(task: Task) -> Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return true
        }

        // Featured public lists are read-only unless you created the task
        if isViewingFromFeatured && !task.isCreatedBy(currentUserId) {
            return true
        }

        return false
    }
}
