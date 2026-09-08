import SwiftUI


struct TaskEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared

    let task: Task?
    let list: TaskList?

    @State private var title = ""
    @State private var description = ""
    @State private var priority: Task.Priority = .none
    @State private var dueDate: Date?
    @State private var hasDueDate = false
    @State private var isPrivate = false
    @State private var assigneeId: String?
    @State private var repeating: String = "never"
    @State private var selectedListIds: Set<String> = []
    // isLoading removed - we now dismiss immediately with optimistic updates
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingListPicker = false
    @State private var wasCancelled = false
    @State private var hasSaved = false
    
    init(task: Task? = nil, list: TaskList? = nil) {
        self.task = task
        self.list = list

        if let task = task {
            // Editing existing task - use task values
            _title = State(initialValue: task.title)
            _description = State(initialValue: task.description)
            _priority = State(initialValue: task.priority)
            _dueDate = State(initialValue: task.dueDateTime)
            _hasDueDate = State(initialValue: task.dueDateTime != nil)
            _isPrivate = State(initialValue: task.isPrivate)
            _assigneeId = State(initialValue: task.assigneeId)
            _repeating = State(initialValue: task.repeating?.rawValue ?? "never")
            _selectedListIds = State(initialValue: Set(task.listIds ?? []))
        } else if let list = list {
            // Creating new task - apply list defaults
            AppLog.debug("📝 [TaskEditView] Creating new task for list: \(list.name)")
            AppLog.debug("  - defaultAssigneeId from list: \(list.defaultAssigneeId ?? "nil")")
            AppLog.debug("  - defaultPriority: \(list.defaultPriority ?? -1)")
            _selectedListIds = State(initialValue: [list.id])

            // Apply list defaults
            if let defaultPriority = list.defaultPriority {
                _priority = State(initialValue: Task.Priority(rawValue: defaultPriority) ?? .none)
            }
            if let defaultIsPrivate = list.defaultIsPrivate {
                _isPrivate = State(initialValue: defaultIsPrivate)
            }
            if let defaultAssigneeId = list.defaultAssigneeId {
                AppLog.debug("  - Applying defaultAssigneeId: \(defaultAssigneeId)")
                _assigneeId = State(initialValue: defaultAssigneeId)
            }
            if let defaultRepeating = list.defaultRepeating {
                _repeating = State(initialValue: defaultRepeating)
            }

            // Calculate due date from list defaults
            let calculatedDate = Self.calculateDateTime(
                from: list.defaultDueDate,
                time: list.defaultDueTime
            )
            if let date = calculatedDate {
                _dueDate = State(initialValue: date)
                _hasDueDate = State(initialValue: true)
            }
        }
    }

    /// Check if the due date is an "all day" task (time is midnight)
    private var isAllDayTask: Bool {
        guard let date = dueDate else { return false }
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return components.hour == 0 && components.minute == 0 && components.second == 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                        .onSubmit {
                            // Enter key on title field saves the task
                            _Concurrency.Task { await saveTask() }
                        }

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(Task.Priority.allCases, id: \.self) { priority in
                            Label(priority.displayName, systemImage: "circle.fill")
                                .foregroundColor(Color(hex: priority.color) ?? .gray)
                                .tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Due date",
                            selection: Binding(
                                get: {
                                    guard let existingDate = dueDate else { return Date() }

                                    // For all-day tasks: Convert UTC midnight to local date for display
                                    if isAllDayTask {
                                        var utcCalendar = Calendar(identifier: .gregorian)
                                        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                                        let components = utcCalendar.dateComponents([.year, .month, .day], from: existingDate)

                                        let localCalendar = Calendar.current
                                        if let localDate = localCalendar.date(from: components) {
                                            return localDate
                                        }
                                    }

                                    return existingDate
                                },
                                set: { newDate in
                                    // For all-day tasks: Convert local date to UTC midnight
                                    if isAllDayTask {
                                        let localCalendar = Calendar.current
                                        let components = localCalendar.dateComponents([.year, .month, .day], from: newDate)
                                        guard let year = components.year, let month = components.month, let day = components.day else {
                                            dueDate = newDate
                                            return
                                        }

                                        // Use fresh Gregorian calendar to avoid device settings interference
                                        var utcCalendar = Calendar(identifier: .gregorian)
                                        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

                                        // Don't set calendar on components - let utcCalendar interpret them
                                        let utcComponents = DateComponents(
                                            year: year,
                                            month: month,
                                            day: day,
                                            hour: 0,
                                            minute: 0,
                                            second: 0
                                        )

                                        dueDate = utcCalendar.date(from: utcComponents) ?? newDate
                                    } else {
                                        dueDate = newDate
                                    }
                                }
                            ),
                            displayedComponents: isAllDayTask ? [.date] : [.date, .hourAndMinute]
                        )

                        Toggle("All Day", isOn: Binding(
                            get: { isAllDayTask },
                            set: { newValue in
                                if newValue {
                                    // Set to midnight UTC for all-day tasks
                                    if let dateValue = dueDate {
                                        // Extract local calendar day
                                        let localCalendar = Calendar.current
                                        let components = localCalendar.dateComponents([.year, .month, .day], from: dateValue)
                                        guard let year = components.year, let month = components.month, let day = components.day else { return }

                                        // Create UTC midnight with same day/month/year
                                        // Use fresh Gregorian calendar to avoid device settings interference
                                        var utcCalendar = Calendar(identifier: .gregorian)
                                        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

                                        // Don't set calendar on components - let utcCalendar interpret them
                                        let utcComponents = DateComponents(
                                            year: year,
                                            month: month,
                                            day: day,
                                            hour: 0,
                                            minute: 0,
                                            second: 0
                                        )

                                        dueDate = utcCalendar.date(from: utcComponents)
                                    }
                                }
                            }
                        ))
                    }
                }
                
                Section("Lists") {
                    if selectedListIds.isEmpty {
                        Button {
                            showingListPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.plus")
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("task_edit.add_to_list", comment: "Add to list"))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                        }
                    } else {
                        ForEach(Array(selectedListIds), id: \.self) { listId in
                            if let list = listService.lists.first(where: { $0.id == listId }) {
                                HStack {
                                    ListImageView(list: list, size: 12)
                                    Text(list.name)
                                    Spacer()
                                    Button {
                                        selectedListIds.remove(listId)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }

                        Button {
                            showingListPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Theme.accent)
                                Text(NSLocalizedString("task_edit.add_another_list", comment: "Add another list"))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }

                Section("Privacy") {
                    Toggle("Private task", isOn: $isPrivate)

                    if isPrivate {
                        Text(NSLocalizedString("task_edit.only_you", comment: "Only you can see this task"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if showError {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        wasCancelled = true
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Create" : "Save") {
                        _Concurrency.Task { await saveTask() }
                    }
                    .disabled(title.isEmpty || (task == nil && selectedListIds.isEmpty))
                }
            }
            .sheet(isPresented: $showingListPicker) {
                TaskListPickerView(selectedListIds: $selectedListIds)
            }
        }
        .task {
            if listService.lists.isEmpty {
                _ = try? await listService.fetchLists()
            }
        }
        .onDisappear {
            // Auto-save when view disappears (swipe dismiss, background tap, etc.)
            // Skip if: cancelled, already saved, or nothing meaningful to save
            guard !wasCancelled, !hasSaved else { return }

            // For new tasks: only auto-save if there's a title and at least one list
            // For existing tasks: always auto-save changes
            let hasContent = !title.isEmpty && (!selectedListIds.isEmpty || task != nil)
            guard hasContent else { return }

            _Concurrency.Task { await saveTask() }
        }
    }
    
    private func saveTask() async {
        // Prevent double-save from onDisappear
        guard !hasSaved else { return }
        hasSaved = true

        showError = false

        // Validate list selection for new tasks
        if task == nil && selectedListIds.isEmpty {
            errorMessage = "Please select at least one list for this task"
            showError = true
            hasSaved = false  // Allow retry if validation fails
            return
        }

        // OPTIMISTIC UI: Dismiss immediately, sync in background
        // TaskService already implements optimistic updates internally
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
        dismiss()

        // Capture all values for background task
        let taskToUpdate = task
        let titleValue = title
        let descriptionValue = description
        let priorityValue = priority.rawValue
        let dueDateValue = hasDueDate ? dueDate : nil
        let isAllDay = isAllDayTask
        let assigneeIdValue = assigneeId
        let isPrivateValue = isPrivate
        let repeatingValue = repeating
        let listIds = Array(selectedListIds)

        // Fire-and-forget API call - TaskService handles optimistic updates
        _Concurrency.Task.detached {
            do {
                if let task = taskToUpdate {
                    // Update existing task
                    _ = try await TaskService.shared.updateTask(
                        taskId: task.id,
                        title: titleValue,
                        description: descriptionValue,
                        priority: priorityValue,
                        completed: nil,
                        whenTime: dueDateValue,
                        assigneeId: nil
                    )
                } else {
                    // Create new task
                    // CRITICAL: Convert "unassigned" string to nil for database
                    var finalAssigneeId = assigneeIdValue
                    if finalAssigneeId == "unassigned" {
                        finalAssigneeId = nil
                    }

                    // For all-day tasks: send 'when' with date, but keep 'whenTime' nil
                    // For timed tasks: send both 'when' and 'whenTime' with the same value
                    let whenTimeValue = (dueDateValue != nil && !isAllDay) ? dueDateValue : nil

                    _ = try await TaskService.shared.createTask(
                        listIds: listIds,
                        title: titleValue,
                        description: descriptionValue.isEmpty ? nil : descriptionValue,
                        priority: priorityValue,
                        whenDate: dueDateValue,           // The date
                        whenTime: whenTimeValue,   // The time (nil for all-day tasks)
                        assigneeId: finalAssigneeId,
                        isPrivate: isPrivateValue,
                        repeating: repeatingValue != "never" ? repeatingValue : nil
                    )
                }
            } catch {
                AppLog.debug("⚠️ [TaskEditView] Background save failed: \(error)")
                // TaskService keeps optimistic version as pending for offline sync
            }
        }
    }

    /// Calculate due date/time from list defaults
    /// Matches web behavior: defaultDueTime=nil means "all day" (midnight), not no date
    private static func calculateDateTime(from defaultDueDate: String?, time defaultDueTime: String?) -> Date? {
        let calendar = Calendar.current

        // First, determine the base date
        var whenDate: Date?

        if let dueDateValue = defaultDueDate, dueDateValue != "none" {
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

        return dateToModify
    }
}

#Preview {
    TaskEditView()
}
