//  MacTaskFieldsView.swift
//  Astrid for Mac — a task's editable fields. ONE implementation.
//
//  The detail panel and the board's inline card editor both render this. They
//  used to be separate bodies with separate state and separate save paths, and
//  they drifted exactly as you'd expect: when the detail's date control was
//  rebuilt to match iOS, the board kept the old on/off toggle, and the board's
//  "Who" row was a plain system Picker while the detail had faces. Density is a
//  parameter; the fields are not.
//
//  MacTaskFields states which rows exist; MacTaskFieldsTests pins it.

#if os(macOS)
import SwiftUI

struct MacTaskFieldsView: View {
    let task: Task
    var density: MacTaskFields.Density = .detail
    /// The board card already draws the title on the card face.
    var showsTitle: Bool = true

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    /// Which layout to draw (task 729a190e). Observed rather than read once, so switching the
    /// setting in Appearance redraws an open detail instead of waiting for it to be reopened.
    @StateObject private var userSettings = UserSettingsService.shared
    /// One editor at a time, one save rule (55010e29).
    @StateObject private var editing = EditingSession()
    private static let titleEditor: EditorID = "mac.fields.title"
    private static let notesEditor: EditorID = "mac.fields.notes"

    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Task.Priority = .none
    @State private var hasDue = false
    @State private var due = Date()
    @State private var isAllDay = false
    @State private var repeating: Task.Repeating = .never
    @State private var customPattern: CustomRepeatingPattern?
    @State private var members: [ListMember] = []
    /// Drives the list popover, so the "focus lists" shortcut can open it. The
    /// detail used to route that key at the DATE area, because there was no
    /// lists editor to send it to.
    @State private var showListPicker = false
    /// The description reads as text until clicked (iOS/web parity).
    @State private var editingNotes = false

    /// Resolved through `TaskDisplayMode(stored:)` rather than compared as a string, so a
    /// null (every row written before the column existed) and an unknown value from a newer
    /// build both land on the usable layout instead of an empty one.
    private var displayMode: TaskDisplayMode {
        TaskDisplayMode(stored: userSettings.settings.taskDisplayMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.rowSpacing) {
            ForEach(Array(MacTaskFields.rows(showsTitle: showsTitle,
                                             displayMode: displayMode).enumerated()),
                    id: \.offset) { _, row in
                fieldRow(row)
            }
        }
        .task(id: task.id) { await load() }
        .onDisappear { saveNotes() }
        // Field-focus bare keys (d/i/s/c) for the fields this view owns (9a60b697).
        .onChange(of: MacAppModel.shared.shortcutRequest) { _, req in
            guard let req, case .focus(let field) = req.kind else { return }
            switch field {
            case .description:
                // The editor only EXISTS once the row is in edit mode now, so the
                // shortcut has to open it before asking for focus.
                editingNotes = true
                notesFocused = true
            case .lists:       showListPicker = true
            case .date:        if !hasDue { hasDue = true; saveDue() }
            case .comment:     break   // the detail owns the comment field
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ row: MacTaskFieldRow) -> some View {
        switch row {
        case .title:
            titleRow
        case .when:
            labeled(icon: "calendar", NSLocalizedString("tasks.when", comment: "")) { whenRow }
        case .lists:
            labeled(icon: "list.bullet",
                    NSLocalizedString("navigation.lists", comment: "Lists")) { listsRow }
        case .description:
            descriptionRow
        case .priority:
            // Only reached in list mode — `MacTaskFields.rows` omits it in project mode,
            // where the leading control already depicts priority as its colour.
            labeled(icon: "flag",
                    NSLocalizedString("tasks.priority", comment: "Priority")) { priorityRow }
        case .assignee:
            labeled(icon: "person.crop.circle",
                    NSLocalizedString("tasks.assignee", comment: "Assignee")) { assigneeRow }
        }
    }

    // MARK: - Priority and assignee, as rows (list mode only — task 729a190e)

    /// The SAME pickers the leading control's popover uses, built the same way, so the two
    /// layouts cannot drift into offering different choices for the same field.
    ///
    /// `onSelect` rather than watching the binding, for the reason task a6cd1367 recorded:
    /// a tap that picks the value the task already has changes nothing to observe, so a
    /// value-watcher swallows it and the control sits there looking dead.
    private var priorityRow: some View {
        MacPriorityPicker(selection: $priority, onSelect: { savePriority($0) })
    }

    private var assigneeRow: some View {
        MacAssigneePicker(
            options: MacAssigneeOptions.build(
                members: members,
                currentUserId: AuthManager.shared.userId,
                taskAssignee: task.assignee),
            selectedId: task.assigneeId,
            priority: priority,
            onSelect: { setAssignee($0) }
        )
    }

    // MARK: - Title + the control that holds priority, assignee and completion

    private var titleRow: some View {
        HStack(spacing: MacDetailRowMetrics.columnGap) {
            MacLeadingControlButton(
                task: task,
                priority: $priority,
                members: members,
                onPriority: { savePriority($0) },
                onAssignee: { setAssignee($0) },
                onToggleComplete: { setCompleted(!task.completed) }
            )
            // `labelsHidden()`: inside a Form, macOS renders a TextField's first argument
            // as a leading label — the stray "Title" prefix on the detail header (4a3360c3).
            TextField(NSLocalizedString("mac.title", comment: ""), text: $title)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(MacTypography.detailTitle)
                .strikethrough(task.completed)
                .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                .focused($titleFocused)
                .onSubmit(saveTitle)
                // Resign-to-save, like every other editor (55010e29).
                .onChange(of: titleFocused) { _, focused in
                    if focused { editing.begin(Self.titleEditor) }
                    else { editing.end(Self.titleEditor); saveTitle() }
                }
        }
    }

    // MARK: - When

    private var whenRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The SHARED wrapping layout iOS uses: the controls stay on one line
            // while they fit and wrap when they do not. The Mac used to force a
            // minimum width on each so all three would fit one line, which is
            // exactly what truncated the date to "Sat, Aug 15,…".
            FlowLayout(spacing: MacTaskFields.chipSpacing, rowSpacing: 6) {
                ForEach(Array(TaskWhenRowLayout.controls(hasDate: hasDue)
                    .enumerated()), id: \.offset) { _, control in
                    whenControl(control)
                }
            }
        }
    }

    @ViewBuilder
    private func whenControl(_ control: TaskWhenControl) -> some View {
        switch control {
        case .date:
            MacDueDatePicker(date: dueDateBinding, isAllDay: $isAllDay) { saveDue() }
        case .time:
            MacDueTimePicker(due: $due, isAllDay: $isAllDay) { saveDue() }
        case .repeatPattern:
            MacRepeatPicker(repeating: $repeating, customPattern: $customPattern) {
                saveRepeat()
            }
        }
    }

    /// The list's default time of day, if it has one.
    private var listDefaultTimeOfDay: (hour: Int, minute: Int)? {
        (task.listIds ?? [])
            .compactMap { listService.listsById[$0]?.defaultDueTime }
            .compactMap { NewTaskDefaults.timeOfDay($0) }
            .first
    }

    private var dueDateBinding: Binding<Date?> {
        Binding(
            get: { hasDue ? due : nil },
            set: { newValue in
                if let newValue {
                    // FIRST date on this task: the time comes from the LIST's default,
                    // not the clock. `due` starts at Date(), so dating a task at 4pm
                    // was making it due at 4pm — the shared NewTaskDefaults is what
                    // iOS resolves this from.
                    if !hasDue, let time = listDefaultTimeOfDay {
                        let day = isAllDay ? MacWhenDate.localDay(ofAllDay: newValue) : newValue
                        due = Calendar.current.date(bySettingHour: time.hour,
                                                    minute: time.minute,
                                                    second: 0,
                                                    of: day) ?? newValue
                        isAllDay = false
                    } else {
                        due = newValue
                    }
                    hasDue = true
                } else {
                    hasDue = false
                    // Clearing the date clears the repeat too — matching iOS, and because
                    // a repeat with no date to repeat from produces phantom rollovers.
                    repeating = .never
                    customPattern = nil
                }
            }
        )
    }

    // MARK: - Lists

    private var listsRow: some View {
        MacListPicker(
            selectedIds: task.listIds ?? [],
            lists: listService.lists,
            onToggle: { listId in
                setLists(MacTaskFields.toggling(listId: listId, in: task.listIds ?? []))
            },
            isPresented: $showListPicker
        )
    }

    // MARK: - Description

    /// Read until you click it, then an editor that GROWS instead of scrolling.
    ///
    /// It used to be a permanently-live TextEditor with a fixed minimum height:
    /// an empty task showed an editing box with a scrollbar, and a long
    /// description scrolled inside a 70pt window rather than taking the room the
    /// panel had. iOS and web both read as text and become editable on tap.
    private var descriptionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("tasks.description", comment: ""))
                .font(MacTypography.label)
                .foregroundStyle(Theme.textMuted)

            if editingNotes {
                ZStack(alignment: .topLeading) {
                    // A clear copy of the text sizes the row, so the editor is
                    // always exactly as tall as its content — which is what
                    // removes the scrollbar rather than just hiding it.
                    Text(notes.isEmpty ? " " : notes)
                        .font(MacTypography.detailBody)
                        .foregroundStyle(.clear)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TextEditor(text: $notes)
                        .font(MacTypography.detailBody)
                        .scrollDisabled(true)
                        .scrollContentBackground(.hidden)
                        .focused($notesFocused)
                }
                .frame(minHeight: MacDescriptionRow.minEditorHeight)
                .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: notesFocused) { _, focused in
                    if focused {
                        editing.begin(Self.notesEditor)
                    } else {
                        editing.end(Self.notesEditor)
                        saveNotes()
                        editingNotes = false
                    }
                }
            } else {
                Button {
                    editingNotes = true
                    notesFocused = true
                } label: {
                    Group {
                        switch MacTaskFields.descriptionDisplay(notes) {
                        case .body(let text):
                            // Rendered when you are LOOKING at it; the editor above stays
                            // plain text, because what you edit has to be the characters you
                            // typed (task f5520874).
                            MacMarkdownText(source: text)
                        case .placeholder:
                            Text(NSLocalizedString("mac.click_add_description", comment: ""))
                                .font(MacTypography.detailBody)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .macPointingHand()
            }
        }
    }

    // MARK: - Row chrome

    /// An icon in the checkbox's column, then content starting where the title
    /// text starts. See MacDetailRowMetrics.
    private func labeled<V: View>(icon: String,
                                  _ accessibilityLabel: String,
                                  @ViewBuilder _ content: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacDetailRowMetrics.columnGap) {
            // `Text(Image(…))` rather than a bare Image: only Text participates in
            // firstTextBaseline alignment.
            Text(Image(systemName: icon))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .frame(width: MacDetailRowMetrics.leadingColumnWidth)
                .accessibilityLabel(accessibilityLabel)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: - load + save

    private func load() async {
        title = task.title
        notes = task.description
        priority = task.priority
        isAllDay = task.isAllDay
        repeating = task.repeating ?? .never
        customPattern = task.repeatingData
        if let d = task.dueDateTime { hasDue = true; due = d } else { hasDue = false }
        if let listId = task.listIds?.first {
            try? await ListMemberService.shared.fetchMembers(listId: listId)
            members = ListMemberService.shared.membersByList[listId] ?? []
        }
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        MacActions.perform("Save title") {
            _ = try await taskService.updateTask(taskId: task.id, title: trimmed, task: task)
        }
    }

    private func saveNotes() {
        guard notes != task.description else { return }
        MacActions.perform("Save notes") {
            _ = try await taskService.updateTask(taskId: task.id, description: notes, task: task)
        }
    }

    private func savePriority(_ newValue: Task.Priority) {
        priority = newValue
        guard newValue != task.priority else { return }
        MacActions.perform("Save priority") {
            _ = try await taskService.updateTask(taskId: task.id, priority: newValue.rawValue, task: task)
        }
    }

    private func setAssignee(_ userId: String?) {
        MacActions.perform("Assign task") {
            _ = try await taskService.updateTask(taskId: task.id, assigneeId: userId ?? "", task: task)
        }
    }

    private func setLists(_ listIds: [String]) {
        MacActions.perform("Save lists") {
            _ = try await taskService.updateTask(taskId: task.id, listIds: listIds, task: task)
        }
    }

    private func saveDue() {
        // hasDue OFF sends Date.distantPast (the shared clear sentinel).
        MacActions.perform("Save due date") {
            _ = try await taskService.updateTask(
                taskId: task.id,
                dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due),
                isAllDay: isAllDay, task: task)
        }
    }

    /// Custom opens the editor (persist happens on Save); everything else saves now.
    private func handleRepeatChange() {
        if repeating == .custom {
            // The repeat picker owns the custom editor now, so reaching Custom
            // here means a pattern already exists.
            saveRepeat()
        } else {
            customPattern = nil
            saveRepeat()
        }
    }

    private func saveRepeat() {
        MacActions.perform("Save repeat") {
            _ = try await taskService.updateTask(taskId: task.id,
                                                 repeating: repeating.rawValue,
                                                 repeatingData: customPattern,
                                                 task: task)
        }
    }

    private func setCompleted(_ value: Bool) {
        // Surface failures instead of swallowing them — a silently failing completion
        // is indistinguishable from a dead checkbox (652edb22).
        MacActions.perform("Complete task") {
            _ = try await TaskService.shared.completeTask(id: task.id, completed: value, task: task)
        }
    }
}
#endif
