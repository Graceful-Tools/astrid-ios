import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// New TaskDetailView with inline editing (matching mobile web app)
struct TaskDetailViewNew: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    // Effective theme - Auto resolves to Light or Dark based on system setting
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    @State private var task: Task
    let isReadOnly: Bool  // View-only mode for public lists
    var onClose: (() -> Void)?  // iPad panel close callback (clears selectedTask)
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @StateObject private var notificationPromptManager = NotificationPromptManager.shared

    // Editable state
    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedDueDate: Date?
    @State private var editedDueTime: Date?
    @State private var editedRepeating: Task.Repeating?
    @State private var editedRepeatingData: CustomRepeatingPattern?
    @State private var editedRepeatFrom: Task.RepeatFromMode?
    @State private var editedPriority: Task.Priority
    @State private var editedListIds: [String]
    @State private var editedAssigneeId: String?
    @State private var isCompleted: Bool
    @State private var showingCompleteSubtasksPrompt = false
    /// Priority / assignee / Complete, presented from the leading checkbox (42013da7).
    @State private var showingLeadingPicker = false
    @State private var isAllDay: Bool  // Track all-day state independently
    @State private var showTimer: Bool = false // New state for timer
    // Comment bar visibility: the bar lives in a bottom safeAreaInset, so it
    // rides up with the keyboard. When the keyboard belongs to ANOTHER input
    // (subtask field, description editor), the bar collapses (not unmounted —
    // that would drop the draft and, mid-race, dismiss its own keyboard).
    @State private var keyboardVisible = false
    @State private var commentInputFocused = false
    @State private var hideCommentBar = false

    /// Decide (slightly debounced) whether the comment bar should collapse:
    /// keyboard up + focus not on the comment input = some other editor owns
    /// it. The delay outlasts the keyboardWillShow ↔ focus-report race.
    private func reevaluateCommentBar(after delay: Double = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.2)) {
                hideCommentBar = keyboardVisible && !commentInputFocused
            }
        }
    }
    @FocusState private var isTitleFocused: Bool  // Focus state for title field

    // Action menu state (moved from TaskActionsView)
    @State private var showingCopySheet = false
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false

    // Comment input state (for fixed position input above keyboard)
    @State private var newCommentText = ""
    @State private var isSubmittingComment = false
    @FocusState private var isCommentFocused: Bool

    // Autocomplete state for comment input (@mentions, #lists, !tasks)
    @State private var activeTrigger: AutocompleteItem.AutocompleteType?
    @State private var triggerPosition: String.Index?
    @State private var autocompleteItems: [AutocompleteItem] = []
    @State private var insertedReferences: [InsertedReference] = []

    // Attachment state for comment input
    @State private var attachedFile: AttachedFileInfo?
    @State private var isUploadingFile = false
    @State private var showingPhotoPicker = false
    @State private var showingVideoPicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var uploadError: String?

    // Scroll actions (set by ScrollViewReader)
    @State private var scrollToTopAction: (() -> Void)?
    @State private var scrollToBottomAction: (() -> Void)?

    init(task: Task, isReadOnly: Bool = false, onClose: (() -> Void)? = nil) {
        self._task = State(initialValue: task)
        self.isReadOnly = isReadOnly
        self.onClose = onClose
        _editedTitle = State(initialValue: task.title)
        _editedDescription = State(initialValue: task.description)
        _editedDueDate = State(initialValue: task.dueDateTime)
        _editedDueTime = State(initialValue: task.isAllDay ? nil : task.dueDateTime)
        _editedRepeating = State(initialValue: task.repeating)
        _editedRepeatingData = State(initialValue: task.repeatingData)
        _editedRepeatFrom = State(initialValue: task.repeatFrom ?? .COMPLETION_DATE)
        _editedPriority = State(initialValue: task.priority)

        // 🔧 FIX: Compute listIds from lists array if not provided by API
        // This supports both old API (lists only) and new API (lists + listIds)
        let computedListIds: [String]
        if let listIds = task.listIds, !listIds.isEmpty {
            computedListIds = listIds
        } else if let lists = task.lists {
            computedListIds = lists.map { $0.id }
        } else {
            computedListIds = []
        }
        _editedListIds = State(initialValue: computedListIds)

        _editedAssigneeId = State(initialValue: task.assigneeId)
        _isCompleted = State(initialValue: task.completed)
        _isAllDay = State(initialValue: task.isAllDay)
    }

    // Check if task belongs to any PUBLIC list
    private var isPublicListTask: Bool {
        task.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header — avoids iOS 26 glass toolbar bubbles
            HStack {
                    Button {
                        if let onClose { onClose() } else { dismiss() }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        scrollToTopAction?()
                    } label: {
                        Text(NSLocalizedString("tasks.task_details", comment: ""))
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if !isReadOnly {
                        Menu {
                            Button {
                                showingCopySheet = true
                            } label: {
                                Label(NSLocalizedString("tasks.copy_task", comment: ""), systemImage: "doc.on.doc")
                            }

                            Button {
                                showingShareSheet = true
                            } label: {
                                Label(NSLocalizedString("tasks.share_task", comment: ""), systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label(NSLocalizedString("tasks.delete_task", comment: ""), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .rotationEffect(.degrees(90))  // SF Symbols has no ellipsis.vertical — rotate the horizontal one to match the web's vertical three-dot
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .frame(minWidth: 44, minHeight: 44)  // 44pt is Apple HIG min tap target
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("taskDetailActionsMenu")
                        .accessibilityLabel("Task actions")
                    } else {
                        // Spacer to balance the back button
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .opacity(0)
                    }
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.vertical, Theme.spacing12)
                .background(toolbarBackgroundColor)

            mainContent
        }
        .background(getBackgroundColor())  // Ensures consistent bg in dark mode on iPad panels
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableInteractivePopGesture()
            .sheet(isPresented: $showingCopySheet) {
                CopyTaskView(task: task, currentListId: task.listIds?.first ?? task.lists?.first?.id)
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareTaskView(task: task)
            }
            .confirmationDialog(
                NSLocalizedString("tasks.delete_confirm", comment: ""),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                    _Concurrency.Task {
                        try? await TaskService.shared.deleteTask(id: task.id, task: task)
                        dismiss()
                    }
                }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            }
            .task {
                await refreshTaskDetails()
            }
            .onDisappear {
                // Save any unsaved title/description changes when navigating away
                if !isReadOnly {
                    saveTitle()
                    saveDescription()
                }
            }
            .fullScreenCover(isPresented: $showTimer) {
                TaskTimerView(task: $task, onUpdate: { updatedTask in
                    self.task = updatedTask
                    // Sync local state with updated task
                    self.editedTitle = updatedTask.title
                    self.editedDescription = updatedTask.description
                    self.editedDueDate = updatedTask.dueDateTime
                    self.editedPriority = updatedTask.priority
                    self.isCompleted = updatedTask.completed
                })
            }
            .alert(NSLocalizedString("notifications.enable_push", comment: ""), isPresented: $notificationPromptManager.showPromptAlert) {
                Button(NSLocalizedString("notifications.not_now", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("notifications.enable", comment: "")) {
                    _Concurrency.Task {
                        _ = await notificationPromptManager.requestNotificationPermission()
                    }
                }
            } message: {
                Text(NSLocalizedString("notifications.enable_message", comment: ""))
            }
            .alert(NSLocalizedString("notifications.disabled", comment: ""), isPresented: $notificationPromptManager.showSettingsPrompt) {
                Button(NSLocalizedString("notifications.not_now", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("notifications.open_settings", comment: "")) {
                    notificationPromptManager.openSettings()
                }
            } message: {
                Text(NSLocalizedString("notifications.disabled_message", comment: ""))
            }
    }

    // MARK: - View Components

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {

                VStack(spacing: Theme.spacing12) {
                    // Anchor for scroll-to-top
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    // 1. Title and Completion Checkbox
                    HStack(alignment: .center, spacing: Theme.spacing12) {
                    // The SAME leading control the task row shows — checkbox, or the assignee's
                    // photo in a priority-coloured square when it belongs to someone else — and
                    // it now holds priority, assignee and Complete behind it (42013da7).
                    if !isReadOnly {
                        Button {
                            // Dismiss the keyboard first — otherwise the popover opens above it
                            // and the picker is squeezed into whatever is left (42013da7).
                            isTitleFocused = false
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                            to: nil, from: nil, for: nil)
                            showingLeadingPicker = true
                        } label: {
                            detailLeadingControl
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingLeadingPicker) {
                            leadingPickerContent
                                .presentationCompactAdaptation(.popover)
                        }
                        .confirmationDialog(
                            NSLocalizedString("task_detail.complete_subtasks_title", comment: "Complete sub-tasks?"),
                            isPresented: $showingCompleteSubtasksPrompt,
                            titleVisibility: .visible
                        ) {
                            Button(NSLocalizedString("task_detail.complete_all_subtasks", comment: "Mark all sub-tasks complete")) {
                                performCompletion(alsoCompleteSubtasks: true)
                            }
                            Button(NSLocalizedString("task_detail.complete_only_this", comment: "Only this task")) {
                                performCompletion(alsoCompleteSubtasks: false)
                            }
                            Button(NSLocalizedString("actions.cancel", comment: "Cancel"), role: .cancel) {}
                        }
                    }

                    // Title display
                    if isReadOnly {
                        Text(editedTitle)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.spacing12)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    } else {
                        titleTextField
                    }
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.top, Theme.spacing8)
                .onChange(of: isTitleFocused) {
                    if !isTitleFocused && !isReadOnly {
                        saveTitle()
                    }
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                // 2. Creator, for a public list task only. Priority and assignee moved BEHIND
                // the checkbox (42013da7) — that control already depicts both, so a row
                // repeating them was spending vertical space the description wanted.
                if isPublicListTask, let creator = task.creator {
                    TwoColumnRow(label: NSLocalizedString("tasks.created_by", comment: ""),
                                 icon: "person.crop.circle") {
                        NavigationLink(destination: UserProfileView(userId: creator.id)) {
                            HStack(spacing: Theme.spacing8) {
                                CachedAsyncImage(url: creator.image.flatMap { URL(string: $0) }) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    ZStack {
                                        Circle().fill(Theme.accent)
                                        Text(creator.initials)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.accentText)
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())

                                Text(creator.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 3. When — Date, Time and Repeat on ONE row (Task 42013da7). Five stacked field
                // rows were what pushed the description below the fold; this is where the room
                // for it comes from. Time and Repeat stay conditional on a date, so with no date
                // the row is a single "Add date" chip rather than three empty controls.
                if editedDueDate != nil || !isReadOnly {
                    TwoColumnRow(label: NSLocalizedString("tasks.when", comment: ""), icon: "calendar") {
                        if isReadOnly {
                            HStack(spacing: Theme.spacing8) {
                                if let date = editedDueDate {
                                    Text(formatDateReadOnly(date))
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                }
                                if let time = editedDueTime {
                                    Text(time, style: .time)
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                }
                                if let repeating = editedRepeating, repeating != .never {
                                    Label(repeating.rawValue.capitalized, systemImage: "repeat")
                                        .font(Theme.Typography.caption1())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                }
                            }
                        } else {
                            HStack(spacing: Theme.spacing8) {
                                InlineDatePicker(
                                    label: NSLocalizedString("tasks.due_date", comment: ""),
                                    date: $editedDueDate,
                                    onSave: saveDueDate,
                                    showLabel: false,
                                    isAllDay: isAllDay,
                                    compact: true
                                )
                                if editedDueDate != nil {
                                    InlineTimePicker(
                                        label: "Time",
                                        time: $editedDueTime,
                                        onSave: saveDueTime,
                                        showLabel: false,
                                        compact: true
                                    )
                                    InlineRepeatPicker(
                                        label: "Repeat",
                                        repeatPattern: $editedRepeating,
                                        repeatFrom: $editedRepeatFrom,
                                        repeatingData: $editedRepeatingData,
                                        onSave: saveRepeating,
                                        onSaveCustom: saveCustomRepeating,
                                        showLabel: false,
                                        compact: true
                                    )
                                }
                            }
                        }
                    }

                    // A CUSTOM repeat cannot say what it is in a chip — "Custom" tells you
                    // nothing, and the real pattern ("Every 2 weeks on Mon, Wed") does not fit
                    // beside a date and a time. It gets the next row to itself (42013da7).
                    if let repeating = editedRepeating, repeating == .custom,
                       let pattern = editedRepeatingData {
                        TwoColumnRow(label: NSLocalizedString("repeating.title", comment: "Repeat"),
                                     icon: "repeat") {
                            Text(CustomRepeatSummary.text(for: pattern, repeatFrom: editedRepeatFrom))
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // 7. Lists
                TwoColumnRow(label: NSLocalizedString("navigation.lists", comment: "Lists"),
                             icon: "list.bullet") {
                    if isReadOnly {
                        if let lists = task.lists, !lists.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.spacing4) {
                                ForEach(lists) { list in
                                    HStack(spacing: Theme.spacing8) {
                                        ListImageView(list: list, size: 8)
                                        Text(list.name)
                                            .font(Theme.Typography.caption1())
                                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    }
                                }
                            }
                        }
                    } else {
                        InlineListsPicker(
                            label: "Lists",
                            selectedListIds: $editedListIds,
                            availableLists: listService.lists,
                            onSave: saveLists,
                            showLabel: false
                        )
                    }
                }

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                // 8. Description
                if isReadOnly {
                    // View-only: Only show description if it exists
                    if !editedDescription.isEmpty {
                        TwoColumnRow(label: "Description") {
                            Text(editedDescription)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    InlineTextAreaEditor(
                        label: "Description",
                        text: $editedDescription,
                        placeholder: NSLocalizedString("task_edit.add_description", comment: "Add a description..."),
                        onSave: saveDescription
                    )
                    .padding(.horizontal, Theme.spacing16)
                }

                TaskAttachmentSectionView(task: task)

                // 9. Timer moved into the comment footer (send slot while empty);
                // only the last-timer caption remains inline.
                if let lastTimerValue = task.lastTimerValue {
                    Text(String(format: NSLocalizedString("task_edit.last_timer", comment: "Last timer value"), lastTimerValue))
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacing16)
                        .padding(.top, Theme.spacing4)
                }

                // Provenance: where a completed task was completed, when not Astrid.
                if task.completed, let src = task.completedSource, src != "astrid" {
                    let providerName = ["google": "Google Tasks", "github": "GitHub", "apple": "Apple Reminders"][src] ?? src
                    Text(String(format: NSLocalizedString("task_detail.completed_via", comment: "Completed via provider"), providerName))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.spacing16)
                        .padding(.top, Theme.spacing4)
                }

                // 9a. Parent task link (shown on subtasks, under the description)
                if let parentId = task.parentTaskId,
                   let parent = TaskService.shared.tasks.first(where: { $0.id == parentId }) {
                    Button { TaskPresenter.shared.showTask(parent) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.system(size: 13))
                            Text(NSLocalizedString("task_detail.parent_task", comment: "Parent task"))
                                .font(Theme.Typography.caption1())
                            Text(parent.title)
                                .font(Theme.Typography.caption1().weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.spacing16)
                    .padding(.top, Theme.spacing8)
                }

                // 9b. Sub tasks
                SubtasksSectionView(parentTask: task, isReadOnly: isReadOnly)
                    .padding(.horizontal, Theme.spacing16)
                    .padding(.top, Theme.spacing8)

                // 10. Comments Section (input is handled separately in fixed position)
                CommentSectionViewEnhanced(taskId: task.id, hideInput: true)
                    .padding(.horizontal, Theme.spacing16)

                // Bottom anchor for scrolling after adding comments
                Color.clear
                    .frame(height: 1)
                    .id("bottom")

                // Extra space at bottom for comment input bar (safeAreaInset handles positioning)
                Spacer().frame(height: Theme.spacing12)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onReceive(NotificationCenter.default.publisher(for: .astridTaskDeleted)) { notification in
                // The open task was deleted (locally or by external sync) —
                // close the pane instead of showing a dead task.
                let ids = [notification.userInfo?["taskId"] as? String,
                           notification.userInfo?["resolvedTaskId"] as? String].compactMap { $0 }
                let myIds = [task.id, TaskService.shared.mappedRealTaskId(for: task.id)].compactMap { $0 }
                if !Set(ids).isDisjoint(with: myIds) {
                    if let onClose { onClose() } else { dismiss() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
                reevaluateCommentBar()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
                reevaluateCommentBar(after: 0)
            }
            .onChange(of: commentInputFocused) { _, _ in
                // Covers focus moving directly between fields with the keyboard
                // staying up (no willShow/willHide fires).
                reevaluateCommentBar()
            }
            .onChange(of: isCommentFocused) { _, focused in
                // Scroll to bottom when comment input is focused (like messaging apps)
                if focused {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // Set scroll actions for use elsewhere
                scrollToTopAction = {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
                scrollToBottomAction = {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .withReferenceNavigation()
            .coordinateSpace(name: "scroll")
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await refreshTaskDetails()
            }
            .safeAreaInset(edge: .bottom) {
                // Fixed comment input above keyboard (like messaging apps).
                // Collapsed (state kept) while another input owns the keyboard.
                if !isReadOnly {
                    RichTextInput(
                        placeholder: "Add a comment...",
                        listId: task.listIds?.first,
                        uploadContext: task.listIds?.first != nil ? ["listId": task.listIds!.first!] : ["taskId": task.id],
                        onSend: { content, type, fileId in
                            _Concurrency.Task { await submitCommentFromRichInput(content: content, type: type, fileId: fileId) }
                        },
                        onTimerTap: { showTimer = true },
                        focusReport: $commentInputFocused
                    )
                        .frame(height: hideCommentBar ? 0 : nil)
                        .clipped()
                        .opacity(hideCommentBar ? 0 : 1)
                        .allowsHitTesting(!hideCommentBar)
                        .background(
                            // Extend background to cover home indicator area
                            taskDetailsBackground
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
            }
            .background(
                ZStack {
                    getBackgroundColor()  // Ocean cyan base layer
                    if effectiveTheme == .ocean {
                        Color.white.opacity(0.8)  // Transparent white overlay for ocean theme
                    }
                }
            )
        }
    }

    // MARK: - Theme Helpers

    /// Get base background color (ocean cyan for ocean theme)
    private func getBackgroundColor() -> Color {
        switch effectiveTheme {
        case .ocean:
            return Theme.Ocean.bgPrimary  // Ocean cyan base
        case .dark:
            return Theme.Dark.bgPrimary
        case .light, .auto:
            return Theme.bgPrimary
        }
    }

    /// Toolbar background color (matches content background)
    private var toolbarBackgroundColor: Color {
        switch effectiveTheme {
        case .ocean:
            // Ocean theme: cyan base with white overlay (same as content)
            return Color(red: 0.95, green: 0.98, blue: 0.99)  // Approximate ocean + white overlay
        case .dark:
            return Theme.Dark.bgPrimary
        case .light, .auto:
            return Theme.bgPrimary
        }
    }

    /// Task details background (matches main content background)
    @ViewBuilder
    private var taskDetailsBackground: some View {
        ZStack {
            getBackgroundColor()
            if effectiveTheme == .ocean {
                Color.white.opacity(0.8)
            }
        }
    }

    // MARK: - View Components (cont.)

    /// Fixed comment input bar that stays above the keyboard (styled like QuickAddTaskView)
    private var commentInputBar: some View {
        VStack(spacing: Theme.spacing8) {
            // Autocomplete popup — @mentions, #lists, !tasks
            if activeTrigger != nil && !autocompleteItems.isEmpty {
                AutocompletePopupView(
                    items: autocompleteItems,
                    activeTrigger: activeTrigger,
                    textColor: commentInputTextColor,
                    mutedColor: commentInputMutedColor,
                    backgroundColor: commentInputBackgroundColor,
                    borderColor: commentInputBorderColor,
                    onSelect: { item in insertCommentAutocompleteItem(item) },
                    onDismiss: { clearCommentAutocomplete() }
                )
            }

            // File attachment preview
            if let file = attachedFile {
                HStack(alignment: .bottom, spacing: Theme.spacing8) {
                    ZStack(alignment: .topTrailing) {
                        if file.isImage, let imageData = file.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                    .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                                    .frame(width: 64, height: 64)
                                VStack(spacing: 4) {
                                    Image(systemName: fileIcon(for: file.mimeType))
                                        .font(.system(size: 24))
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    Text(file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }

                        Button {
                            if file.fileId.hasPrefix("temp_") {
                                AttachmentService.shared.cancelUpload(tempFileId: file.fileId)
                            }
                            attachedFile = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                .background(Circle().fill(Color.black.opacity(0.3)))
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
            }

            HStack(alignment: .center, spacing: Theme.spacing12) {
                // Attachment menu button
                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label(NSLocalizedString("attachments.choose_photo", comment: ""), systemImage: "photo")
                    }
                    Button {
                        showingVideoPicker = true
                    } label: {
                        Label(NSLocalizedString("attachments.choose_video", comment: ""), systemImage: "video")
                    }
                    Button {
                        showingDocumentPicker = true
                    } label: {
                        Label(NSLocalizedString("attachments.choose_document", comment: ""), systemImage: "doc")
                    }
                } label: {
                    Image(systemName: isUploadingFile ? "arrow.up.circle" : "paperclip")
                        .font(.system(size: 20))
                        .foregroundColor(isUploadingFile ? .gray : commentInputMutedColor)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingFile || isSubmittingComment)

                // Expandable text input
                ZStack(alignment: .topLeading) {
                    // Placeholder text — offset to match TextEditor's natural text position
                    if newCommentText.isEmpty {
                        Text("Add a comment...")
                            .font(Theme.Typography.body())
                            .foregroundColor(commentInputPlaceholderColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    // Visible TextEditor — uses natural internal padding
                    TextEditor(text: $newCommentText)
                        .font(Theme.Typography.body())
                        .foregroundColor(commentInputTextColor)
                        .focused($isCommentFocused)
                        .scrollContentBackground(.hidden)
                        .onChange(of: newCommentText) { _, newValue in
                            handleCommentTextChange(newValue)
                        }
                }
                .frame(minHeight: 36, maxHeight: 200)
                .fixedSize(horizontal: false, vertical: true)
                .background(commentInputBackgroundColor)
                .cornerRadius(Theme.radiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(commentInputBorderColor, lineWidth: 1)
                )

                // Send button
                Button {
                    _Concurrency.Task { await submitComment() }
                } label: {
                    if isSubmittingComment {
                        ProgressView()
                            .tint(Theme.accent)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(canSubmitComment ? Theme.accent : commentInputMutedColor)
                    }
                }
                .frame(width: 34, height: 34)
                .buttonStyle(.plain)
                .disabled(!canSubmitComment || isSubmittingComment)
            }
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(commentInputContainerBackground)
        .cornerRadius(Theme.radiusLarge)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
        .simultaneousGesture(
            DragGesture().onChanged { value in
                if value.translation.height > 10 {
                    isCommentFocused = false
                }
            }
        )
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared())
        .photosPicker(isPresented: $showingVideoPicker, selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared())
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.pdf, .plainText, .zip, .image, .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!, UTType(filenameExtension: "mkv")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _Concurrency.Task { await uploadDocument(url) }
            case .failure(let error):
                print("❌ Document picker error: \(error)")
                uploadError = "Failed to select document: \(error.localizedDescription)"
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let photoItem = newValue else { return }
            _Concurrency.Task { await uploadPhotoItem(photoItem) }
        }
        .onChange(of: selectedVideoItem) { _, newValue in
            guard let videoItem = newValue else { return }
            _Concurrency.Task { await uploadVideoItem(videoItem) }
        }
        .alert("Upload Error", isPresented: .init(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("OK", role: .cancel) { uploadError = nil }
        } message: {
            if let error = uploadError { Text(error) }
        }
    }

    // MARK: - Comment Input Theme Helpers

    private var canSubmitComment: Bool {
        !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedFile != nil
    }

    private var commentInputTextColor: Color {
        if effectiveTheme == .ocean {
            return Theme.Ocean.textPrimary
        }
        return effectiveTheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary
    }

    private var commentInputMutedColor: Color {
        if effectiveTheme == .ocean {
            return Theme.Ocean.textMuted
        }
        return effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted
    }

    private var commentInputPlaceholderColor: Color {
        if effectiveTheme == .ocean {
            return Color(UIColor.darkGray)
        }
        return effectiveTheme == .dark ? Theme.Dark.textMuted : Theme.textMuted
    }

    private var commentInputBackgroundColor: Color {
        if effectiveTheme == .dark {
            return Theme.Dark.inputBg
        }
        return Color.white
    }

    private var commentInputBorderColor: Color {
        if effectiveTheme == .dark {
            return Theme.Dark.inputBorder
        }
        return Theme.Ocean.inputBorder
    }

    @ViewBuilder
    private var commentInputContainerBackground: some View {
        if effectiveTheme == .light {
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else {
            commentInputContainerColor
        }
    }

    private var commentInputContainerColor: Color {
        if effectiveTheme == .dark {
            return Theme.Dark.bgPrimary
        }
        return Color.white.opacity(0.8)
    }

    private func fileIcon(for mimeType: String) -> String {
        let lowercased = mimeType.lowercased()
        if lowercased.hasPrefix("image/") { return "photo" }
        else if lowercased.hasPrefix("video/") { return "video" }
        else if lowercased.hasPrefix("audio/") { return "waveform" }
        else if lowercased.contains("pdf") { return "doc.text" }
        else if lowercased.contains("zip") || lowercased.contains("archive") { return "archivebox" }
        else { return "doc" }
    }

    /// Submit a new comment
    // MARK: - Comment Autocomplete

    private func handleCommentTextChange(_ text: String) {
        insertedReferences.removeAll { ref in !text.contains(ref.displayText) }
        if let trigger = detectAutocompleteTrigger(in: text) {
            activeTrigger = trigger.type
            triggerPosition = trigger.position
            let results: [AutocompleteItem]
            switch trigger.type {
            case .mention:
                results = filterMentionItems(users: buildMentionableUsers(), search: trigger.search)
            case .list:
                results = filterListItems(search: trigger.search)
            case .task:
                results = filterTaskItems(search: trigger.search)
            }
            autocompleteItems = results
        } else {
            clearCommentAutocomplete()
        }
    }

    private func insertCommentAutocompleteItem(_ item: AutocompleteItem) {
        guard let pos = triggerPosition else { return }
        let displayText = "\(item.triggerChar)\(item.label)"
        let textBefore = String(newCommentText[newCommentText.startIndex..<pos])
        newCommentText = textBefore + displayText + " "
        insertedReferences.append(InsertedReference(id: item.id, type: item.type, displayText: displayText))
        clearCommentAutocomplete()
    }

    private func clearCommentAutocomplete() {
        activeTrigger = nil
        triggerPosition = nil
        autocompleteItems = []
    }

    /// Called by RichTextInput when user sends a comment
    private func submitCommentFromRichInput(content: String, type: Comment.CommentType, fileId: String?) async {
        guard !content.isEmpty || fileId != nil else { return }

        // Resolve temp fileId if needed
        var resolvedFileId = fileId
        if let tempFileId = fileId, tempFileId.hasPrefix("temp_") {
            if let realFileId = AttachmentService.shared.getRealFileId(for: tempFileId) {
                resolvedFileId = realFileId
            }
            // Otherwise keep the temp fileId: the upload only starts with the
            // enqueued upload→comment chain, which resolves the real id itself —
            // waiting here would deadlock.
        }

        do {
            _ = try await CommentService.shared.createComment(
                taskId: task.id,
                content: content,
                type: type,
                fileId: resolvedFileId,
                parentCommentId: nil,
                authorId: AuthManager.shared.userId
            )

            NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": task.id])

            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run { scrollToBottomAction?() }
        } catch {
            print("❌ [TaskDetailViewNew] Failed to submit comment: \(error)")
        }
    }

    private func submitComment() async {
        // Reconstruct @[Name](id) format from display text before sending
        let reconstructed = reconstructReferencesInText(newCommentText, references: insertedReferences)
        let trimmedText = reconstructed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || attachedFile != nil else { return }
        insertedReferences = []
        clearCommentAutocomplete()

        isSubmittingComment = true

        // Determine comment type
        let commentType: Comment.CommentType = attachedFile != nil ? .ATTACHMENT : .MARKDOWN

        // Get file ID (wait for upload if needed, unless offline/authoritative)
        var fileIdToSend = attachedFile?.fileId
        if let tempFileId = fileIdToSend, tempFileId.hasPrefix("temp_") {
            if let realFileId = AttachmentService.shared.getRealFileId(for: tempFileId) {
                fileIdToSend = realFileId
            }
            // Otherwise keep the temp fileId: the upload only starts with the
            // enqueued upload→comment chain, which resolves the real id itself —
            // waiting here would deadlock.
        }

        do {
            _ = try await CommentService.shared.createComment(
                taskId: task.id,
                content: trimmedText,
                type: commentType,
                fileId: fileIdToSend,
                parentCommentId: nil,
                authorId: AuthManager.shared.userId
            )

            // Clear input on success
            await MainActor.run {
                newCommentText = ""
                attachedFile = nil
                // Keep focus on input for quick follow-up comments (like texting apps)
            }

            // Notify CommentSectionViewEnhanced to refresh
            NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": task.id])

            // Scroll to bottom to show the new comment (after a brief delay for UI to update)
            try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)  // 200ms
            await MainActor.run {
                scrollToBottomAction?()
            }

        } catch {
            print("❌ [TaskDetailViewNew] Failed to submit comment: \(error)")
        }

        isSubmittingComment = false
    }

    // MARK: - File Upload Helpers

    private let maxFileSize = 100 * 1024 * 1024  // 100 MB

    private func uploadPhotoItem(_ photoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            // No-network PhotoKit read first: on-device photos attach offline,
            // cloud-only photos fail fast with a clear message.
            let online = await MainActor.run { NetworkMonitor.shared.isConnected }
            let imageData: Data
            switch await LocalPhotoLoader.loadImageData(for: photoItem, isConnected: online) {
            case .data(let data):
                imageData = data
            case .notLocallyAvailable:
                await MainActor.run { uploadError = OfflinePhotoPolicy.unavailableMessage(isConnected: false) }
                return
            case .failed:
                await MainActor.run { uploadError = OfflinePhotoPolicy.unavailableMessage(isConnected: online) }
                return
            }

            if imageData.count > maxFileSize {
                await MainActor.run { uploadError = "Photo is too large. Maximum size is 100 MB." }
                return
            }

            let fileName = "photo_\(UUID().uuidString).jpg"
            let mimeType = "image/jpeg"

            let tempFileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                fileData: imageData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: task.id
            )

            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: imageData.count,
                    mimeType: mimeType,
                    imageData: imageData
                )
                if let uiImage = UIImage(data: imageData) {
                    ThumbnailCache.shared.set(uiImage, for: tempFileId)
                }
                selectedPhotoItem = nil
            }
        }
    }

    private func uploadVideoItem(_ videoItem: PhotosPickerItem) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            guard let videoData = try await videoItem.loadTransferable(type: Data.self) else {
                await MainActor.run { uploadError = "Failed to load video. Please try again." }
                return
            }

            if videoData.count > maxFileSize {
                await MainActor.run { uploadError = "Video is too large. Maximum size is 100 MB." }
                return
            }

            let fileName = "video_\(UUID().uuidString).mp4"
            let mimeType = "video/mp4"

            let tempFileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                fileData: videoData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: task.id
            )

            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: videoData.count,
                    mimeType: mimeType,
                    imageData: nil
                )
                selectedVideoItem = nil
            }
        } catch {
            await MainActor.run { uploadError = "Failed to load video: \(error.localizedDescription)" }
        }
    }

    private func uploadDocument(_ url: URL) async {
        isUploadingFile = true
        defer { isUploadingFile = false }

        do {
            guard url.startAccessingSecurityScopedResource() else {
                await MainActor.run { uploadError = "Failed to access document. Please try again." }
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let fileData = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            let mimeType = AttachmentService.shared.getMimeType(for: url.pathExtension)

            if fileData.count > maxFileSize {
                await MainActor.run { uploadError = "Document is too large. Maximum size is 100 MB." }
                return
            }

            let tempFileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                taskId: task.id
            )

            await MainActor.run {
                attachedFile = AttachedFileInfo(
                    fileId: tempFileId,
                    fileName: fileName,
                    fileSize: fileData.count,
                    mimeType: mimeType,
                    imageData: nil
                )
            }
        } catch {
            await MainActor.run { uploadError = "Failed to load document: \(error.localizedDescription)" }
        }
    }

    private var titleTextField: some View {
        TextField("Task title", text: $editedTitle, axis: .vertical)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
            .textFieldStyle(.plain)
            .disabled(isReadOnly)
            .focused($isTitleFocused)
            .onChange(of: editedTitle) { _, newValue in
                // Detect return key press (newline) and dismiss keyboard
                if newValue.contains("\n") {
                    editedTitle = newValue.replacingOccurrences(of: "\n", with: "")
                    isTitleFocused = false
                }
            }
            .padding(Theme.spacing12)
            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }

    // MARK: - Helper Methods

    private func refreshTaskDetails() async {
        // First, sync any pending attachments and comments (if online)
        if NetworkMonitor.shared.isConnected {
            print("🔄 [TaskDetailViewNew] Pull to refresh - draining outbox first...")
            await OutboxManager.shared.drain()
        }

        do {
            // Fetch fresh task data from the API with force refresh
            let freshTask = try await taskService.fetchTask(id: task.id, forceRefresh: true)

            // Update local state variables with fresh data
            await MainActor.run {
                self.task = freshTask
                editedTitle = freshTask.title
                editedDescription = freshTask.description
                editedDueDate = freshTask.dueDateTime
                editedDueTime = freshTask.isAllDay ? nil : freshTask.dueDateTime
                editedRepeating = freshTask.repeating
                editedRepeatingData = freshTask.repeatingData
                editedRepeatFrom = freshTask.repeatFrom ?? .COMPLETION_DATE
                editedPriority = freshTask.priority

                // Compute listIds from lists array if not provided by API
                let computedListIds: [String]
                if let listIds = freshTask.listIds, !listIds.isEmpty {
                    computedListIds = listIds
                } else if let lists = freshTask.lists {
                    computedListIds = lists.map { $0.id }
                } else {
                    computedListIds = []
                }
                editedListIds = computedListIds

                editedAssigneeId = freshTask.assigneeId
                isCompleted = freshTask.completed
                isAllDay = freshTask.isAllDay
            }

            // Force-refresh comments too — CommentSectionViewEnhanced only reloads
            // off the .commentDidSync notification, which fires from inside fetchComments
            // after a network call. Without useCache: false here, pull-to-refresh would
            // never re-hit the network for comments.
            _ = try? await CommentService.shared.fetchComments(taskId: task.id, useCache: false)
        } catch {
            // Silent failure - just fail gracefully if offline
            print("⚠️ [TaskDetailViewNew] Failed to refresh task details: \(error)")
        }
    }

    private var priorityColor: Color {
        switch editedPriority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }

    /// Custom checkbox image matching task row design
    /// Mirrors TaskRowView's leading control: the assignee's photo in a priority-coloured square
    /// when the task belongs to someone else, the completion checkbox otherwise (42013da7).
    @ViewBuilder private var detailLeadingControl: some View {
        if let assignee = effectiveAssignee,
           let currentUser = AuthManager.shared.currentUser,
           assignee.id != currentUser.id {
            CachedAsyncImage(url: assignee.cachedImageURL.flatMap { URL(string: $0) }) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.accent)
                    Text(assignee.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(priorityColor(editedPriority), lineWidth: 2))
            // Keyed on the assignee: SwiftUI reuses a view whose identity has not changed, which
            // is the other half of "the photo didn't change" (42013da7).
            .id(AssigneeResolver.avatarIdentity(for: editedAssigneeId))
            .accessibilityLabel(Text(assignee.displayName))
        } else {
            checkboxImage
        }
    }

    /// Priority, assignee and Complete — everything that used to be its own row, behind the
    /// control that already depicts all three (42013da7).
    @ViewBuilder private var leadingPickerContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Each choice dismisses the popover straight away — you came here to set ONE thing,
            // and leaving it open makes you tap outside to confirm nothing happened (42013da7).
            PriorityButtonPicker(priority: $editedPriority, onSave: { newPriority in
                _ = try await taskService.updateTask(taskId: task.id, priority: newPriority.rawValue, task: task)
                await MainActor.run { showingLeadingPicker = false }
            })

            InlineAssigneePicker(
                label: NSLocalizedString("tasks.assignee", comment: ""),
                assigneeId: $editedAssigneeId,
                taskListIds: editedListIds,
                taskId: task.id,
                availableLists: listService.lists,
                onSave: { newAssigneeId in
                    await saveAssignee(newAssigneeId)
                    await MainActor.run { showingLeadingPicker = false }
                },
                showLabel: false
            )

            Divider()

            Button {
                showingLeadingPicker = false
                toggleCompletion()
            } label: {
                Label(isCompleted ? NSLocalizedString("mac.mark_incomplete", comment: "")
                                  : NSLocalizedString("tasks.complete_task", comment: ""),
                      systemImage: isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill")
                    .font(Theme.Typography.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacing12)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacing16)
        .frame(width: 320)
    }

    /// The assignee to depict — the full object when we have it, otherwise a minimal User built
    /// from the id so UserImageCache can still resolve a photo (same as TaskRowView).
    private var effectiveAssignee: User? {
        // No member list here — the picker fetches its own — so the resolver falls through to the
        // task's assignee, then to a minimal User that UserImageCache can still supply a photo for.
        AssigneeResolver.resolve(id: editedAssigneeId, members: [], taskAssignee: task.assignee,
                                 agents: AIAgentCache.shared.load() ?? [])
    }

    private var checkboxImage: some View {
        let priorityValue = editedPriority.rawValue
        let isRepeating = editedRepeating != nil && editedRepeating != .never
        let isChecked = isCompleted

        // Build image name: check_box[_repeat][_checked]_<priority>
        var imageName = "check_box"
        if isRepeating {
            imageName += "_repeat"
        }
        if isChecked {
            imageName += "_checked"
        }
        imageName += "_\(priorityValue)"

        return Image(imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 34, height: 34)
    }

    private func toggleCompletion() {
        // Completing a parent with open subtasks? Offer bulk completion first
        // (feature request 26170974: "mark all sub-tasks as complete").
        if !isCompleted && !openSubtasks.isEmpty {
            showingCompleteSubtasksPrompt = true
            return
        }
        performCompletion(alsoCompleteSubtasks: false)
    }

    private var openSubtasks: [Task] {
        TaskService.shared.tasks.filter { $0.parentTaskId == task.id && !$0.completed }
    }

    private func performCompletion(alsoCompleteSubtasks: Bool) {
        // Complete subtasks FIRST, each through completeTask (canonical control
        // point — repeating subtasks roll forward instead of just closing).
        if alsoCompleteSubtasks {
            let toComplete = openSubtasks
            _Concurrency.Task {
                for sub in toComplete {
                    _ = try? await taskService.completeTask(id: sub.id, completed: true, task: sub)
                }
            }
        }

        // Optimistic UI update
        isCompleted.toggle()

        // CRITICAL: Propagate ALL edited fields that affect repeat rollover
        // before handing off to TaskService. If the user changed the due
        // date, time, all-day flag, or repeat configuration in the detail
        // view but hasn't saved yet, `task` still holds the old values. The
        // repeat calculator anchors on these fields, so stale values produce
        // the wrong next occurrence.
        var taskWithEdits = task
        taskWithEdits.repeating = editedRepeating
        taskWithEdits.repeatingData = editedRepeatingData
        taskWithEdits.repeatFrom = editedRepeatFrom
        taskWithEdits.isAllDay = isAllDay
        // For timed tasks, editedDueTime carries the full datetime; for
        // all-day tasks, editedDueDate is the source of truth.
        taskWithEdits.dueDateTime = isAllDay ? editedDueDate : (editedDueTime ?? editedDueDate)

        // Sync to server in background
        _Concurrency.Task {
            do {
                let updatedTask = try await taskService.completeTask(id: task.id, completed: isCompleted, task: taskWithEdits)

                // For repeating tasks, server may roll forward (set completed back to false)
                // Update local state to match server response
                await MainActor.run {
                    isCompleted = updatedTask.completed

                    // Also update other fields that may have changed (due date for repeating tasks)
                    editedDueDate = updatedTask.dueDateTime
                    editedDueTime = updatedTask.isAllDay ? nil : updatedTask.dueDateTime

                    editedRepeating = updatedTask.repeating
                    editedRepeatingData = updatedTask.repeatingData

                    // Only set repeatFrom if task is still repeating
                    if updatedTask.repeating != nil && updatedTask.repeating != .never {
                        editedRepeatFrom = updatedTask.repeatFrom ?? .COMPLETION_DATE
                    } else {
                        editedRepeatFrom = nil
                        editedRepeatingData = nil
                    }
                }
            } catch {
                // On error, revert optimistic update
                await MainActor.run {
                    isCompleted.toggle()
                }
            }
        }
    }

    private func saveTitle() {
        guard editedTitle != task.title else { return }
        _Concurrency.Task {
            // Custom repeating saves use TaskService's server-first path to
            // avoid optimistic view recreation during inline editing.
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(title: editedTitle)
                _ = try? await taskService.updateTaskOnServer(taskId: task.id, updates: request)
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, title: editedTitle, task: task)
            }
        }
    }

    private func saveDescription() {
        guard editedDescription != task.description else { return }
        _Concurrency.Task {
            // Custom repeating saves use TaskService's server-first path to
            // avoid optimistic view recreation during inline editing.
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(description: editedDescription)
                _ = try? await taskService.updateTaskOnServer(taskId: task.id, updates: request)
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, description: editedDescription, task: task)
            }
        }
    }

    private func saveDueDate() {
        _Concurrency.Task {
            // If removing the due date, also clear repeating settings (matching web behavior)
            if editedDueDate == nil {
                editedRepeating = .never
                editedRepeatingData = nil
                editedDueTime = nil  // Also clear time when clearing date

                await MainActor.run {
                    isAllDay = true  // No date = all-day by default
                }

                // Use Date.distantPast as sentinel to signal "clear the date"
                _ = try? await taskService.updateTask(
                    taskId: task.id,
                    when: Date.distantPast,
                    whenTime: Date.distantPast,
                    repeating: "never",
                    repeatingData: nil,
                    task: task
                )
            } else {
                // If there's no time, it's an all-day task
                if editedDueTime == nil {
                    await MainActor.run {
                        isAllDay = true
                    }
                }

                // Use the server-first service path to avoid intermediate
                // optimistic state churn while editing custom repeats.
                if editedRepeating == .custom {
                    await saveDirectToAPI()
                } else {
                    // Set date only - preserve existing time if it exists
                    // Only pass whenTime if we need to change it (nil = don't update)
                    _ = try? await taskService.updateTask(
                        taskId: task.id,
                        when: editedDueDate,
                        whenTime: nil,  // nil = don't update time, preserve existing
                        task: task
                    )
                }

                // Check if we should prompt user to enable push notifications
                // This prompts 3 times initially, then once per month thereafter
                await notificationPromptManager.checkAndPromptAfterDateSet()
            }
        }
    }

    /// Server-first save for custom repeating tasks. This stays behind
    /// TaskService while avoiding optimistic view recreation during save.
    private func saveDirectToAPI() async {
        guard let dueDate = editedDueDate else { return }

        // Format date for API
        var dueDateTimeString: String
        if isAllDay {
            // Normalize to UTC midnight for all-day tasks
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let startOfDay = utcCalendar.startOfDay(for: dueDate)
            dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
        } else if let time = editedDueTime {
            dueDateTimeString = ISO8601DateFormatter().string(from: time)
        } else {
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let startOfDay = utcCalendar.startOfDay(for: dueDate)
            dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
        }

        let request = UpdateTaskRequest(
            dueDateTime: dueDateTimeString,
            isAllDay: isAllDay
        )

        do {
            _ = try await taskService.updateTaskOnServer(taskId: task.id, updates: request)
        } catch {
            print("⚠️ [TaskDetailViewNew] Server-first save failed: \(error)")
            // Silent failure - data will sync on next refresh
        }
    }

    private func savePriority() {
        guard editedPriority != task.priority else { return }
        _Concurrency.Task {
            // Custom repeating saves use TaskService's server-first path to
            // avoid optimistic view recreation during inline editing.
            if editedRepeating == .custom {
                let request = UpdateTaskRequest(priority: editedPriority.rawValue)
                _ = try? await taskService.updateTaskOnServer(taskId: task.id, updates: request)
            } else {
                _ = try? await taskService.updateTask(taskId: task.id, priority: editedPriority.rawValue, task: task)
            }
        }
    }

    private func saveDueTime() async {
        _Concurrency.Task {
            guard let date = editedDueDate else { return }

            if let time = editedDueTime {
                // Extract date components based on current all-day state
                let dateComponents: DateComponents

                if isAllDay {
                    // All-day → timed: Extract UTC components from UTC midnight date
                    var utcCalendar = Calendar(identifier: .gregorian)
                    utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                    dateComponents = utcCalendar.dateComponents([.year, .month, .day], from: date)
                } else {
                    // Timed → timed: Extract LOCAL components to preserve date
                    let localCalendar = Calendar.current
                    dateComponents = localCalendar.dateComponents([.year, .month, .day], from: date)
                }

                // Extract LOCAL time components (hour, minute) - user's intended time
                let localCalendar = Calendar.current
                let timeComponents = localCalendar.dateComponents([.hour, .minute], from: time)

                // Combine: extracted date + local time = user's intended datetime
                var combined = DateComponents()
                combined.year = dateComponents.year
                combined.month = dateComponents.month
                combined.day = dateComponents.day
                combined.hour = timeComponents.hour
                combined.minute = timeComponents.minute
                combined.timeZone = localCalendar.timeZone  // User's timezone

                if let combinedDate = localCalendar.date(from: combined) {
                    // Update state immediately
                    await MainActor.run {
                        editedDueDate = combinedDate
                        isAllDay = false  // Now it's a timed task
                    }

                    // Custom repeats use TaskService's server-first path.
                    // to prevent view recreation crashes during save
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        // Send update to server
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: combinedDate,
                            whenTime: combinedDate,
                            task: task
                        )
                    }
                }
            } else {
                // Time cleared - convert back to all-day task
                // CRITICAL: Update editedDueDate to UTC midnight
                // This ensures the date picker displays correctly when isAllDay becomes true
                // Use fresh Gregorian calendar to avoid device settings interference
                var utcCalendar = Calendar(identifier: .gregorian)
                utcCalendar.timeZone = TimeZone(identifier: "UTC")!

                // Extract current date components from the local date
                let localCalendar = Calendar.current
                let dateComponents = localCalendar.dateComponents([.year, .month, .day], from: date)

                // Create UTC midnight date with same calendar day
                if let utcMidnight = utcCalendar.date(from: dateComponents) {
                    await MainActor.run {
                        editedDueDate = utcMidnight
                        isAllDay = true  // Now it's an all-day task
                    }

                    // Custom repeats use TaskService's server-first path.
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: utcMidnight,
                            whenTime: Date.distantPast,  // Clear time
                            task: task
                        )
                    }
                } else {
                    await MainActor.run {
                        isAllDay = true  // Now it's an all-day task
                    }

                    // Custom repeats use TaskService's server-first path.
                    if editedRepeating == .custom {
                        await saveDirectToAPI()
                    } else {
                        _ = try? await taskService.updateTask(
                            taskId: task.id,
                            when: date,
                            whenTime: Date.distantPast,  // Clear time
                            task: task
                        )
                    }
                }
            }
        }
    }

    private func saveRepeating() async {
        _Concurrency.Task {
            let repeatingString = editedRepeating?.rawValue ?? "never"
            // Only send repeatingData if repeating is 'custom', otherwise clear it
            let dataToSend = (editedRepeating == .custom) ? editedRepeatingData : nil
            // Only send repeatFrom if repeating is not 'never'
            let repeatFromString = (editedRepeating != nil && editedRepeating != .never) ? editedRepeatFrom?.rawValue : nil
            _ = try? await taskService.updateTask(
                taskId: task.id,
                repeating: repeatingString,
                repeatingData: dataToSend,
                repeatFrom: repeatFromString,
                task: task
            )
        }
    }

    /// Direct save for custom repeating patterns - bypasses TaskService optimistic update
    /// to prevent view recreation crashes during save
    private func saveCustomRepeating(_ repeating: Task.Repeating, _ repeatFromMode: Task.RepeatFromMode, _ data: CustomRepeatingPattern?) async {
        // Update local state
        editedRepeating = repeating
        editedRepeatFrom = repeatFromMode
        editedRepeatingData = data

        // Use TaskService's server-first path to prevent view hierarchy churn.
        let taskId = task.id
        do {
            let request = UpdateTaskRequest(
                repeating: repeating.rawValue,
                repeatingData: data,
                repeatFrom: repeatFromMode.rawValue
            )
            _ = try await taskService.updateTaskOnServer(taskId: taskId, updates: request)
        } catch {
            print("⚠️ [TaskDetailViewNew] Failed to save custom repeating: \(error)")
            // Silent failure - data will sync on next refresh
        }
    }

    private func saveLists() async {
        _Concurrency.Task {
            try? await taskService.updateTaskLists(taskId: task.id, listIds: editedListIds)
        }
    }

    private func saveAssignee(_ assigneeId: String?) async {
        _Concurrency.Task {
            // Convert nil to empty string to signal unassignment
            // nil = don't update, "" = unassign, "userId" = assign
            let assigneeIdForUpdate = assigneeId ?? ""
            _ = try? await taskService.updateTask(taskId: task.id, assigneeId: assigneeIdForUpdate, task: task)
        }
    }

    // MARK: - Read-Only Helpers

    private func formatDateReadOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        // For all-day tasks, use UTC timezone to show correct date
        if isAllDay {
            formatter.timeZone = TimeZone(identifier: "UTC")
        }

        return formatter.string(from: date)
    }

    private func priorityColor(_ priority: Task.Priority) -> Color {
        switch priority {
        case .none:
            return .gray
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func priorityText(_ priority: Task.Priority) -> String {
        switch priority {
        case .none:
            return "None"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

#Preview {
    NavigationStack {
        TaskDetailViewNew(task: Task(
            id: "1",
            title: "Sample Task",
            description: "This is a sample task",
            creatorId: "user1",
            isAllDay: false,
            repeating: .never,
            priority: .high,
            isPrivate: false,
            completed: false
        ))
    }
}
