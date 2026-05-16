import SwiftUI

/// Outer chrome for QuickAddTaskView.
///
/// Default (list view): a floating rounded card with a lift shadow and
/// an 8pt side margin.
///
/// Board footer: flush — no corner radius, no shadow, no side margin —
/// so the bar spans the full column width and sits flat against the
/// column's bottom edge. The column's own `.clipShape` rounds the
/// bottom corners.
private struct QuickAddOuterChrome: ViewModifier {
    let boardFooterStyle: Bool
    func body(content: Content) -> some View {
        if boardFooterStyle {
            content
        } else {
            content
                .cornerRadius(Theme.radiusLarge)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
                .padding(.horizontal, 8)  // Match task row horizontal margins
                .padding(.bottom, 0)      // Sit at bottom, SwiftUI handles keyboard avoidance
        }
    }
}

/// Quick add task view fixed at bottom (matching mobile web)
/// Allows adding multiple tasks in a row
struct QuickAddTaskView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared

    let selectedList: TaskList?
    var onTaskCreated: ((Task) -> Void)?
    /// Extra list ids the new task should join, beyond `selectedList`.
    /// Used by the board's per-column inline footer so a task added in
    /// the "Doing" column lands in BOTH the project's regular list AND
    /// the Doing status list. Defaults to empty so non-board callers
    /// keep their existing behavior.
    var additionalListIds: [String] = []
    /// When true, render as a flush board-column footer: full column
    /// width, no rounded card / shadow / side margin, and the inner
    /// content inset to 24pt so the add-task checkbox lines up with
    /// the task cards' checkboxes (8pt column inset + 16pt row inset).
    var boardFooterStyle: Bool = false

    @State private var taskTitle = ""
    @FocusState private var isFocused: Bool

    // Priority/Assignee picker state
    @State private var selectedPriority: Task.Priority = .none
    @State private var selectedAssigneeId: String?
    @State private var showingPicker = false

    // Submit debounce guard — prevents double-tap creating duplicate tasks
    @State private var isSubmitting = false

    // Height constraints for expandable input
    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 200  // Allow for longer task titles (~8-10 lines)

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            // Checkbox button for priority/assignee picker (vertically centered with text input)
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                showingPicker = true
            }) {
                quickAddCheckbox
            }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)

            // Expandable text input with @mention, #list, !task autocomplete
            ZStack(alignment: .topLeading) {
                // Hidden sizing text
                Text(taskTitle.isEmpty ? " " : taskTitle)
                    .font(Theme.Typography.body())
                    .foregroundColor(.clear)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Placeholder text
                if taskTitle.isEmpty {
                    Text(NSLocalizedString("tasks.add_task_placeholder", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(placeholderColor)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                // TextEditor — visible text, standard behavior
                TextEditor(text: $taskTitle)
                    .font(Theme.Typography.body())
                    .foregroundColor(textColor)
                    .focused($isFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Theme.spacing8)
                    .padding(.vertical, Theme.spacing4)
                    .onChange(of: taskTitle) { _, newValue in
                        // Detect return key press (newline)
                        if newValue.contains("\n") {
                            let cleanTitle = newValue.replacingOccurrences(of: "\n", with: "")
                            DispatchQueue.main.async {
                                taskTitle = cleanTitle
                                if cleanTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                                    isFocused = false
                                } else {
                                    addTask(navigateToDetails: false)
                                }
                            }
                        }
                    }
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(inputBackgroundColor)
            .cornerRadius(Theme.radiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(inputBorderColor, lineWidth: 1)
            )

            // Add button
            Button(action: {
                addTask(navigateToDetails: true)  // Plus button: add task and navigate to details
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(Theme.Typography.title2())
                    .foregroundColor(taskTitle.isEmpty ? mutedTextColor : Theme.accent)
            }
            .disabled(taskTitle.isEmpty)
            .buttonStyle(.plain)
        }
        // Board footer aligns its checkbox with the task cards: cards
        // sit at 8pt (column LazyVStack) + 14pt (row) = 22pt, so the
        // footer's inner inset is 22pt. List view keeps the 16pt inset.
        .padding(.horizontal, boardFooterStyle ? 22 : Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(containerBackground)
        .modifier(QuickAddOuterChrome(boardFooterStyle: boardFooterStyle))
        .simultaneousGesture(
            DragGesture().onChanged { value in
                if value.translation.height > 10 {
                    isFocused = false
                }
            }
        )
        .sheet(isPresented: $showingPicker) {
            QuickAddPickerSheet(
                selectedPriority: $selectedPriority,
                selectedAssigneeId: $selectedAssigneeId,
                availableMembers: availableMembers,
                colorScheme: colorScheme,
                listIds: selectedList?.id != nil ? [selectedList!.id] : nil
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Initialize from list defaults on first appear
            applyListDefaults()
        }
        .onChange(of: selectedList?.id) { _, _ in
            // Update when switching to a different list
            applyListDefaults()
        }
        .onChange(of: selectedList?.defaultAssigneeId) { _, _ in
            // Update when list default assignee changes
            applyListDefaults()
        }
        .onChange(of: selectedList?.defaultPriority) { _, _ in
            // Update when list default priority changes
            applyListDefaults()
        }
    }

    /// Apply list default priority and assignee to the quick add checkbox
    /// Virtual lists (like "Today") may have their own defaults which should be respected
    /// Only fall back to My Tasks preferences if no list selected or list has no defaults
    private func applyListDefaults() {
        let myTasksPrefs = MyTasksPreferencesService.shared.preferences

        // Check if list has a default priority set (works for both regular and virtual lists)
        if let defaultPriority = selectedList?.defaultPriority, defaultPriority > 0 {
            // List has a default priority - use it
            selectedPriority = Task.Priority(rawValue: defaultPriority) ?? .none
        } else if selectedList == nil {
            // No list selected (generic My Tasks view) - use filter if exactly one priority selected
            if let priorityFilter = myTasksPrefs.filterPriority, priorityFilter.count == 1 {
                selectedPriority = Task.Priority(rawValue: priorityFilter[0]) ?? .none
            } else {
                selectedPriority = .none
            }
        } else {
            // List exists but has no default priority - use none
            selectedPriority = .none
        }

        // Check if list has a default assignee set (works for both regular and virtual lists)
        if let defaultAssignee = selectedList?.defaultAssigneeId {
            if defaultAssignee == "unassigned" {
                // Explicitly unassigned
                selectedAssigneeId = nil
            } else if !defaultAssignee.isEmpty {
                // Specific user ID
                selectedAssigneeId = defaultAssignee
            } else {
                // Empty string - default to current user
                selectedAssigneeId = authManager.currentUser?.id
            }
        } else if selectedList == nil {
            // No list selected (generic My Tasks view) - default to current user
            selectedAssigneeId = authManager.currentUser?.id
        } else {
            // List exists but has no default assignee (nil) - means "task_creator" (current user)
            selectedAssigneeId = authManager.currentUser?.id
        }
    }

    // MARK: - Quick Add Checkbox

    /// Checkbox view showing priority color or assignee avatar
    @ViewBuilder
    private var quickAddCheckbox: some View {
        if let assigneeId = selectedAssigneeId,
           let assignee = availableMembers.first(where: { $0.id == assigneeId }),
           assignee.id != authManager.currentUser?.id {
            // Show assignee avatar with priority-colored border
            CachedAsyncImage(url: assignee.image.flatMap { URL(string: $0) }) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "3b82f6") ?? Theme.accent)
                    Text(assignee.name?.prefix(1).uppercased() ?? assignee.email?.prefix(1).uppercased() ?? "?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(priorityColor, lineWidth: 2)
            )
        } else {
            // Show priority-colored checkbox (unchecked state)
            Image("check_box_\(selectedPriority.rawValue)")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
        }
    }

    /// Get available members from selected list
    private var availableMembers: [User] {
        var membersMap: [String: User] = [:]

        guard let list = selectedList else {
            // No list - just include current user
            if let currentUser = authManager.currentUser {
                membersMap[currentUser.id] = currentUser
            }
            return Array(membersMap.values)
        }

        // Owner + listMembers are the canonical member sources (matches
        // what the web's lists endpoint returns; legacy admins/members
        // arrays are no longer populated).
        if let owner = list.owner {
            membersMap[owner.id] = owner
        }
        if let listMembers = list.listMembers {
            for listMember in listMembers {
                if let user = listMember.user {
                    membersMap[user.id] = user
                }
            }
        }

        // Always include current user
        if let currentUser = authManager.currentUser {
            membersMap[currentUser.id] = currentUser
        }

        return Array(membersMap.values).sorted { u1, u2 in
            // Sort by: current user first, then alphabetically
            if let currentUser = authManager.currentUser {
                if u1.id == currentUser.id { return true }
                if u2.id == currentUser.id { return false }
            }
            return (u1.name ?? u1.email ?? "") < (u2.name ?? u2.email ?? "")
        }
    }

    /// Priority color for checkbox border
    private var priorityColor: Color {
        switch selectedPriority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    // MARK: - Theme-aware colors

    private var isOceanTheme: Bool {
        effectiveTheme == .ocean
    }

    private var textColor: Color {
        if isOceanTheme {
            return Theme.Ocean.textPrimary
        }
        return effectiveTheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
    }

    private var mutedTextColor: Color {
        if isOceanTheme {
            return Theme.Ocean.textMuted
        }
        return effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted
    }

    private var placeholderColor: Color {
        if isOceanTheme {
            return Color(UIColor.darkGray)
        }
        return effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted
    }

    private var inputBackgroundColor: Color {
        // White input in both ocean and light modes, dark theme uses its own
        if effectiveTheme == .dark {
            return Theme.Dark.inputBg
        }
        return Color.white  // White text input on silver container (light & ocean)
    }

    private var inputBorderColor: Color {
        // Chrome border in both ocean and light modes
        if effectiveTheme == .dark {
            return Theme.Dark.inputBorder
        }
        return Theme.Ocean.inputBorder  // Chrome border for light & ocean
    }

    /// Container background with support for all themes
    @ViewBuilder
    private var containerBackground: some View {
        if effectiveTheme == .light {
            // Light theme: Use thin material for glass effect
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else {
            containerBackgroundColor
        }
    }

    private var containerBackgroundColor: Color {
        // 20% transparent white container in ocean mode (matches task row transparency)
        if effectiveTheme == .dark {
            return Theme.Dark.bgPrimary
        }
        return Color.white.opacity(0.8)  // 20% transparent white (light & ocean)
    }

    private func addTask(navigateToDetails: Bool = false) {
        guard !taskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isSubmitting else { return } // Prevent double-tap
        isSubmitting = true

        // Dismiss keyboard immediately before any navigation to prevent
        // keyboard staying visible when navigating to task details
        if navigateToDetails {
            isFocused = false
        }

        let rawTitle = taskTitle
        let taskPriority = selectedPriority
        let taskAssigneeId = selectedAssigneeId
        taskTitle = "" // Clear immediately for next task

        // OPTIMISTIC UI: Immediate haptic feedback for ALL interactions
        // No blocking UI - "smooth as butter"
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        _Concurrency.Task {
            do {
                // Smart Task Parsing: Extract dates, priorities, hashtags from title if enabled
                var title = rawTitle
                var parsedDueDateTime: Date? = nil
                var parsedPriority: Int? = nil
                var parsedListIds: [String] = []

                var parsedRepeating: Task.Repeating? = nil

                if UserSettingsService.shared.smartTaskCreationEnabled {
                    let parsed = SmartTaskParser.parse(rawTitle, lists: listService.lists)
                    title = parsed.title
                    parsedDueDateTime = parsed.dueDateTime
                    parsedPriority = parsed.priority
                    parsedListIds = parsed.listIds
                    parsedRepeating = parsed.repeating
                    print("📝 [SmartParsing] Parsed: title='\(title)', dueDateTime=\(parsedDueDateTime?.description ?? "nil"), priority=\(parsedPriority ?? -1), listIds=\(parsedListIds), repeating=\(parsedRepeating?.rawValue ?? "nil")")
                }

                // CRITICAL FIX: Get fresh list data from ListService in case settings were updated
                // The passed-in selectedList might be stale if list defaults were changed
                // while the QuickAddTaskView was active (e.g., user edited list settings)
                // Fall back to selectedList if not found in listService (e.g., temp list, race condition)
                let currentList: TaskList?
                if let listId = selectedList?.id {
                    currentList = listService.lists.first { $0.id == listId } ?? selectedList
                } else {
                    currentList = selectedList
                }

                // Use selected priority/assignee from checkbox picker (overrides list defaults)
                print("📝 [QuickAdd] Selected list: \(currentList?.name ?? "nil")")
                print("  Selected priority: \(taskPriority.rawValue)")
                print("  Selected assigneeId: \(taskAssigneeId ?? "nil (unassigned)")")
                print("  defaultDueDate: \(currentList?.defaultDueDate ?? "nil")")
                print("  defaultDueTime: \(currentList?.defaultDueTime ?? "nil")")

                // Use parsed priority if available, otherwise picker-selected priority
                let priority = parsedPriority ?? taskPriority.rawValue

                // Use the picker-selected assignee (nil means unassigned - respect user's choice)
                var assigneeId = taskAssigneeId

                // CRITICAL: Convert "unassigned" string to nil for database
                if assigneeId == "unassigned" {
                    assigneeId = nil
                }

                // Calculate due date/time based on list defaults or My Tasks filter
                // Virtual lists (like "Today") may have their own defaultDueDate which should be respected
                // Only fall back to My Tasks preferences if no list or no defaultDueDate set
                let myTasksPrefs = MyTasksPreferencesService.shared.preferences

                let effectiveDueDate: String?
                let effectiveDueTime: String?

                if let listDefaultDueDate = currentList?.defaultDueDate,
                   listDefaultDueDate != "none" && !listDefaultDueDate.isEmpty {
                    // List has a defaultDueDate set - use it (works for both regular and virtual lists)
                    effectiveDueDate = listDefaultDueDate
                    effectiveDueTime = currentList?.defaultDueTime
                } else if currentList == nil {
                    // No list selected (generic My Tasks view) - use filter date if active
                    effectiveDueDate = myTasksPrefs.filterDueDate
                    effectiveDueTime = nil // My Tasks filter dates are all-day by default
                } else {
                    // List exists but has no defaultDueDate - no default due date
                    effectiveDueDate = nil
                    effectiveDueTime = nil
                }

                // For all-day tasks (defaultDueTime=nil): only set 'when', keep 'whenTime' nil
                // For timed tasks (defaultDueTime set): set both 'when' and 'whenTime'
                let calculatedDate = calculateDateTime(
                    from: effectiveDueDate,
                    time: effectiveDueTime
                )

                // Determine if this is an all-day task (has date but no time)
                let hasDefaultDueTime = currentList?.defaultDueTime != nil

                // Use parsed due date if available (from smart parsing), otherwise use calculated date
                // Smart-parsed dates are always all-day
                let whenDate: Date?
                let whenTime: Date?

                if let parsedDate = parsedDueDateTime {
                    // Smart parsing detected a date - use it as all-day
                    whenDate = parsedDate
                    whenTime = nil // Smart-parsed dates are all-day
                    print("📝 [SmartParsing] Using parsed due date: \(parsedDate)")
                } else if let date = calculatedDate {
                    // We have a date from list defaults - check if it's all-day or timed
                    whenDate = date
                    if hasDefaultDueTime {
                        // Timed task - set whenTime to the date+time
                        whenTime = date
                    } else {
                        // All-day task - no time specified
                        whenTime = nil
                    }
                } else {
                    // No date at all
                    whenDate = nil
                    whenTime = nil
                }

                let isPrivate = currentList?.defaultIsPrivate
                // Use parsed repeating if available, otherwise use list default
                let repeating = parsedRepeating?.rawValue ?? currentList?.defaultRepeating

                print("📝 [QuickAdd] Creating task with selected values:")
                print("  Priority: \(priority)")
                print("  AssigneeId: \(assigneeId ?? "nil (unassigned)")")
                print("  WhenDate: \(whenDate?.description ?? "none")")
                print("  WhenTime: \(whenTime?.description ?? "none (all-day)")")
                print("  All-day: \(calculatedDate != nil && !hasDefaultDueTime)")
                print("  IsPrivate: \(isPrivate ?? false)")
                print("  Repeating: \(repeating ?? "never")")

                // CRITICAL: Only add list ID if it's NOT a virtual list
                // Virtual lists (saved filters) should NOT be added to tasks
                // They only SHOW tasks that meet filter criteria
                var listIdsToAdd: [String] = []

                // First, add parsed hashtag list IDs (from smart parsing)
                if !parsedListIds.isEmpty {
                    listIdsToAdd.append(contentsOf: parsedListIds)
                    print("  Adding parsed hashtag lists: \(parsedListIds)")
                }

                // Then, add selected list if it's a real list and not already included
                if let list = currentList, list.isVirtual != true, !listIdsToAdd.contains(list.id) {
                    listIdsToAdd.append(list.id)
                    print("  Adding to real list: \(list.name)")
                } else if parsedListIds.isEmpty {
                    // Virtual list or no list and no parsed lists - don't add any list ID
                    print("  Virtual list or no list - not adding list ID")
                }

                // Finally, append any extra list ids the caller wired in.
                // The board's per-column inline footer uses this so a
                // task added under the "Doing" column joins the Doing
                // status list on top of the project's regular list.
                for extraId in additionalListIds where !listIdsToAdd.contains(extraId) {
                    listIdsToAdd.append(extraId)
                }

                // Create task with defaults applied
                let createdTask = try await taskService.createTask(
                    listIds: listIdsToAdd,
                    title: title,
                    description: "",
                    priority: priority,
                    whenDate: whenDate,      // The date
                    whenTime: whenTime,      // The time (nil for all-day tasks)
                    assigneeId: assigneeId,
                    isPrivate: isPrivate,
                    repeating: repeating != "never" ? repeating : nil
                )

                // Navigate to task details only when explicitly requested (+ button tap)
                // TaskService already creates optimistic task, so createdTask is available instantly
                if navigateToDetails {
                    await MainActor.run {
                        onTaskCreated?(createdTask)
                    }
                }
                // For quick add, haptic already fired and user can keep typing
                await MainActor.run { isSubmitting = false }
            } catch {
                print("Failed to create task: \(error)")
                await MainActor.run {
                    // On error, restore title so user doesn't lose their input
                    if !navigateToDetails {
                        taskTitle = rawTitle
                    }
                    isSubmitting = false
                }
            }
        }
    }

    /// Calculate due date/time from list defaults or My Tasks filter
    /// Matches web behavior: defaultDueTime=nil means "all day" (midnight), not no date
    private func calculateDateTime(from defaultDueDate: String?, time defaultDueTime: String?) -> Date? {
        print("🗓️ [calculateDateTime] Input: defaultDueDate=\(defaultDueDate ?? "nil"), defaultDueTime=\(defaultDueTime ?? "nil")")

        let calendar = Calendar.current

        // First, determine the base date
        var whenDate: Date?

        if let dueDateValue = defaultDueDate, dueDateValue != "none" && dueDateValue != "all" && dueDateValue != "no_date" && dueDateValue != "overdue" {
            // We have a default due date - calculate it
            var components = calendar.dateComponents([.year, .month, .day], from: Date())

            switch dueDateValue {
            case "today":
                break // Use today's date
            case "tomorrow":
                components.day? += 1
            case "next_week":
                components.day? += 7
            case "next_month":
                components.month? += 1
            case "this_week":
                // Set to Friday of this week (end of work week)
                let daysUntilFriday = (5 - calendar.component(.weekday, from: Date()) + 8) % 7
                components.day? += (daysUntilFriday == 0 ? 7 : daysUntilFriday)
            case "this_month", "this_calendar_month":
                // Set to last day of current month
                let lastDay = calendar.range(of: .day, in: .month, for: Date())?.count ?? 1
                components.day = lastDay
            case "this_calendar_week":
                // Set to Sunday of this week
                let daysUntilSunday = (7 - calendar.component(.weekday, from: Date())) % 7
                components.day? += (daysUntilSunday == 0 ? 7 : daysUntilSunday)
            default:
                // Try to parse as ISO date string
                if let parsedDate = ISO8601DateFormatter().date(from: dueDateValue) {
                    components = calendar.dateComponents([.year, .month, .day], from: parsedDate)
                } else {
                    return nil // Invalid date format
                }
            }

            // Set initial time to midnight (all-day default)
            components.hour = 0
            components.minute = 0
            components.second = 0
            whenDate = calendar.date(from: components)
        } else if defaultDueTime != nil {
            // No date set, but we have a time - create today's date at that time
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.hour = 0
            components.minute = 0
            components.second = 0
            whenDate = calendar.date(from: components)
        } else {
            // No date and no time
            return nil
        }

        // Now apply the time if we have a date
        guard var dateToModify = whenDate else {
            return nil
        }

        if let timeString = defaultDueTime {
            // Specific time (HH:MM format) - override midnight with this time
            var components = calendar.dateComponents([.year, .month, .day], from: dateToModify)
            let timeParts = timeString.split(separator: ":")

            if timeParts.count == 2,
               let hour = Int(timeParts[0]),
               let minute = Int(timeParts[1]) {
                components.hour = hour
                components.minute = minute
                components.second = 0
                dateToModify = calendar.date(from: components) ?? dateToModify
            }
        }
        // else: defaultDueTime is nil (All Day) - keep time at midnight (already set)

        print("🗓️ [calculateDateTime] Result: \(dateToModify)")
        return dateToModify
    }
}

#Preview {
    QuickAddTaskView(selectedList: nil)
}

// MARK: - Quick Add Picker Sheet

/// Sheet for selecting priority and assignee when adding a task
struct QuickAddPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    @Binding var selectedPriority: Task.Priority
    @Binding var selectedAssigneeId: String?
    let availableMembers: [User]
    let colorScheme: ColorScheme
    var listIds: [String]? = nil

    @State private var aiAgents: [User] = []
    @State private var isLoadingAgents = false

    private let priorities: [Task.Priority] = [.none, .low, .medium, .high]

    // Combine available members with AI agents
    private var allMembers: [User] {
        var memberMap: [String: User] = [:]
        // Add AI agents first
        for agent in aiAgents {
            memberMap[agent.id] = agent
        }
        // Add available members (won't overwrite AI agents)
        for member in availableMembers {
            if memberMap[member.id] == nil {
                memberMap[member.id] = member
            }
        }
        // Sort: AI agents first, then current user, then alphabetically
        return Array(memberMap.values).sorted { u1, u2 in
            let u1IsAI = u1.isAIAgent == true
            let u2IsAI = u2.isAIAgent == true
            if u1IsAI && !u2IsAI { return true }
            if !u1IsAI && u2IsAI { return false }
            if let currentUser = authManager.currentUser {
                if u1.id == currentUser.id { return true }
                if u2.id == currentUser.id { return false }
            }
            return (u1.name ?? u1.email ?? "") < (u2.name ?? u2.email ?? "")
        }
    }

    var body: some View {
        // Use VStack instead of ScrollView to allow swipe-down-to-dismiss gesture
        // Content fits within .medium detent for typical team sizes
        VStack(alignment: .leading, spacing: Theme.spacing24) {
            // Priority Section - using same design as task details
            VStack(alignment: .leading, spacing: Theme.spacing12) {
                Text(NSLocalizedString("tasks.priority", comment: ""))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                HStack(spacing: Theme.spacing12) {
                    ForEach(priorities, id: \.self) { priority in
                        QuickAddPriorityButton(
                            priority: priority,
                            isSelected: selectedPriority == priority,
                            colorScheme: colorScheme
                        ) {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            selectedPriority = priority
                            dismiss()
                        }
                    }
                }
            }

            // Only show assignee section for logged-in users
            if authManager.isAuthenticated {
                Divider()

                // Assignee Section - scrollable for large teams
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    Text(NSLocalizedString("tasks.assignee", comment: ""))
                        .font(Theme.Typography.headline())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    ScrollView {
                        VStack(spacing: Theme.spacing8) {
                            // Unassigned option
                            AssigneeOptionButton(
                                user: nil,
                                isSelected: selectedAssigneeId == nil,
                                isCurrentUser: false,
                                colorScheme: colorScheme
                            ) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                selectedAssigneeId = nil
                                dismiss()
                            }

                            // Member options (including AI agents)
                            ForEach(allMembers) { member in
                                AssigneeOptionButton(
                                    user: member,
                                    isSelected: selectedAssigneeId == member.id,
                                    isCurrentUser: member.id == authManager.currentUser?.id,
                                    isAIAgent: member.isAIAgent == true,
                                    colorScheme: colorScheme
                                ) {
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                    selectedAssigneeId = member.id
                                    dismiss()
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }

            Spacer()
        }
        .padding(Theme.spacing16)
        .padding(.top, Theme.spacing8)
        .task {
            // Fetch AI agents when sheet appears
            await fetchAIAgents()
        }
    }

    private func fetchAIAgents() async {
        guard !isLoadingAgents else { return }
        isLoadingAgents = true

        // Try to load from cache first for instant display
        if let cachedAgents = AIAgentCache.shared.load() {
            await MainActor.run {
                self.aiAgents = cachedAgents
            }
        }

        // Then try to fetch fresh data from API
        do {
            let users = try await APIClient.shared.searchUsersWithAIAgents(
                query: "",
                taskId: nil,
                listIds: listIds
            )
            let agents = users.filter { $0.isAIAgent == true }
            await MainActor.run {
                self.aiAgents = agents
                self.isLoadingAgents = false
            }
            // Cache for offline use
            AIAgentCache.shared.save(agents)
        } catch {
            print("❌ [QuickAddPickerSheet] Failed to fetch AI agents: \(error)")
            await MainActor.run {
                // Keep cached agents if we have them, otherwise aiAgents stays as loaded from cache
                self.isLoadingAgents = false
            }
        }
    }
}

// MARK: - Quick Add Priority Button (matches task details design)

private struct QuickAddPriorityButton: View {
    let priority: Task.Priority
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var priorityColor: Color {
        switch priority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    /// Symbol matching mobile web design
    private var symbol: String {
        switch priority {
        case .none: return "○"   // Circle (U+25CB)
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 48, height: 44)
                .foregroundColor(isSelected ? .white : priorityColor)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(isSelected ? priorityColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(priorityColor, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Assignee Option Button

private struct AssigneeOptionButton: View {
    let user: User?
    let isSelected: Bool
    let isCurrentUser: Bool
    var isAIAgent: Bool = false
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing12) {
                // Avatar or icon
                if let user = user {
                    CachedAsyncImage(url: user.image.flatMap { URL(string: $0) }) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "3b82f6") ?? Theme.accent)
                            Text(user.name?.prefix(1).uppercased() ?? user.email?.prefix(1).uppercased() ?? "?")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.slash")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                // Name and subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(user?.displayName ?? NSLocalizedString("assignee.unassigned", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    if isCurrentUser {
                        Text(NSLocalizedString("assignee.you", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    } else if user?.isAIAgent == true {
                        Text(NSLocalizedString("profile.ai_agent", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.accent)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, Theme.spacing12)
            .padding(.vertical, Theme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(isSelected
                          ? (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
