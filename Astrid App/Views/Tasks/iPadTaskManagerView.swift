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

    var body: some View {
        TaskListView(
            selectedListId: $selectedListId,
            isViewingFromFeatured: $isViewingFromFeatured,
            featuredList: $featuredList,
            searchText: $searchText,
            selectedTaskForPanel: $selectedTask,
            onMenuTap: onMenuTap
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
    @EnvironmentObject var authManager: AuthManager

    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?

    // Search state (managed at this level, passed to sidebar and task list)
    @State private var searchText = ""
    @State private var shouldScrollSidebarToTop = false

    // Selected task for detail panel
    @State private var selectedTask: Task?
    @State private var showChatPanel = false  // Toggle chat in right panel

    // Portrait mode: sidebar shown via sliding overlay (like iPhone)
    @State private var showingSidebar = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasScrolledDuringDrag = false

    // Detect orientation
    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

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
                // Landscape: 3-column layout (sidebar permanently visible | tasks | details)
                threeColumnLandscapeLayout(width: geometry.size.width)
            } else {
                // Portrait: sliding sidebar like iPhone
                threeColumnPortraitLayout(width: geometry.size.width)
            }
        }
        .withReminderPresentation()
        // Close task details when list changes
        .onChange(of: selectedListId) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTask = nil
                showChatPanel = false
            }
        }
    }

    // MARK: - 3-Column Landscape Layout (Sidebar permanently visible)

    @ViewBuilder
    private func threeColumnLandscapeLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left: Sidebar (28% - permanently visible)
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
            .frame(width: width * 0.28)
            .background(themeBackground)

            Divider()

            // Middle: Task List or Settings (37% when detail/chat shown, 72% when neither)
            if selectedListId == "settings" {
                NavigationStack {
                    SettingsView()
                        .environmentObject(authManager)
                }
                .frame(width: (selectedTask != nil || showChatPanel) ? width * 0.37 : width * 0.72)
            } else {
                // No onMenuTap - hamburger button does nothing in landscape since sidebar is always visible
                iPadTaskListView(
                    selectedListId: $selectedListId,
                    isViewingFromFeatured: $isViewingFromFeatured,
                    featuredList: $featuredList,
                    searchText: $searchText,
                    selectedTask: $selectedTask,
                    onMenuTap: nil  // Sidebar always visible in landscape
                )
                .frame(width: (selectedTask != nil || showChatPanel) ? width * 0.37 : width * 0.72)
            }

            // Right panel: Task Detail or Chat (35%)
            if selectedTask != nil {
                Divider()

                VStack(spacing: 0) {
                    if showChatPanel, let listId = selectedListId {
                        ChatPanelView(listId: listId, onSignedIn: { showChatPanel = false })
                    } else {
                        taskDetailPanel
                    }
                }
                .frame(width: width * 0.35)
            } else if showChatPanel, let listId = selectedListId {
                // Show chat panel even with no task selected
                Divider()

                ChatPanelView(listId: listId, onSignedIn: { showChatPanel = false })
                    .frame(width: width * 0.35)
            }
        }
    }

    // MARK: - Portrait Layout (Sliding sidebar like iPhone)
    // Portrait mode: sidebar slides in from left when hamburger button is tapped
    // Task list and details slide right to reveal sidebar underneath

    @ViewBuilder
    private func threeColumnPortraitLayout(width: CGFloat) -> some View {
        let sidebarWidth = width * 0.40  // 40% sidebar width for iPad

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

            // Main content - slides right to reveal sidebar
            HStack(spacing: 0) {
                // Task List or Settings
                if selectedListId == "settings" {
                    NavigationStack {
                        SettingsView()
                            .environmentObject(authManager)
                    }
                    .frame(width: selectedTask != nil ? width * 0.40 : width)
                } else {
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
                        }
                    )
                    .frame(width: selectedTask != nil ? width * 0.40 : width)
                }

                // Task Detail Panel - animates with task list
                if selectedTask != nil {
                    Divider()
                    taskDetailPanel
                        .frame(width: width * 0.60)
                }
            }
            .frame(width: width)
            .offset(x: showingSidebar ? sidebarWidth + dragOffset : dragOffset)
            .shadow(color: .black.opacity(0.3 * sidebarProgress), radius: 10, x: -5, y: 0)
            .opacity(1.0 - (0.3 * sidebarProgress))
            .saturation(1.0 - (0.5 * sidebarProgress))
            .allowsHitTesting(sidebarProgress < 0.95)
            .simultaneousGesture(
                // Edge swipe from left to open sidebar
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if !showingSidebar {
                            let isNearLeftEdge = value.startLocation.x < 50
                            if isNearLeftEdge && value.translation.width > 0 {
                                dragOffset = value.translation.width
                            }
                        }
                    }
                    .onEnded { value in
                        if !showingSidebar {
                            let isNearLeftEdge = value.startLocation.x < 50
                            if isNearLeftEdge && (value.translation.width > 100 || value.predictedEndTranslation.width > 200) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    showingSidebar = true
                                    dragOffset = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }
                            } else {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
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

    @ViewBuilder
    private var taskDetailPanel: some View {
        if let task = selectedTask {
            // Wrap with theme background and padding to align with task list
            NavigationStack {
                TaskDetailViewNew(task: task, isReadOnly: shouldShowTaskAsReadOnly(task: task))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.top, 8)      // Top margin (aligns with floating header)
            .padding(.bottom, 4)   // Bottom margin (aligns with quick add input)
            .padding(.trailing, 8) // Right margin (matches left side of screen)
            .background(themeBackground)
            .id(task.id) // Force view refresh when task changes
        }
    }


    // MARK: - iPad Panel Toggle (Detail / Chat)

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
