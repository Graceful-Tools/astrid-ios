//  MacTaskDetailView.swift
//  Astrid for Mac — full task detail (C1): edit fields + subtasks + comments.
//
//  Native Mac form styled with the shared Theme. Every write goes through the shared
//  services (TaskService / CommentService); no business logic here.

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacTaskDetailView: View {
    let task: Task
    @StateObject private var taskService = TaskService.shared
    @Environment(\.openWindow) private var openWindow

    @State private var title = ""
    @State private var notes = ""
    @FocusState private var notesFocused: Bool
    @State private var hasDue = false
    @State private var due = Date()
    @State private var isAllDay = false
    @State private var priority: Task.Priority = .none
    @State private var repeating: Task.Repeating = .never
    @State private var customPattern: CustomRepeatingPattern?
    @State private var showCustomRepeat = false
    @State private var members: [ListMember] = []
    @State private var timerRunning = false
    @State private var timerStart: Date?

    @State private var subtasks: [Task] = []
    @State private var newSubtask = ""
    @State private var editingSubtask: Task?
    @State private var editingSubtaskText = ""
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var editingComment: Comment?
    @State private var editingCommentText = ""

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title).font(.title3).onSubmit(saveTitle)
                Toggle("Completed", isOn: Binding(get: { task.completed }, set: setCompleted))
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 70)
                    .focused($notesFocused)
                    .onChange(of: notesFocused) { if !notesFocused { saveNotes() } }
            }

            Section("Schedule") {
                Toggle("Due date", isOn: $hasDue).onChange(of: hasDue) { saveDue() }
                if hasDue {
                    DatePicker("When", selection: $due,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .onChange(of: due) { saveDue() }
                    Toggle("All day", isOn: $isAllDay).onChange(of: isAllDay) { saveDue() }
                }
                Picker("Repeat", selection: $repeating) {
                    ForEach([Task.Repeating.never, .daily, .weekly, .monthly, .yearly, .custom], id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .onChange(of: repeating) { handleRepeatChange() }
                if repeating == .custom {
                    HStack {
                        Text(customPattern.map(MacCustomRepeat.summary) ?? "Custom…")
                            .foregroundStyle(Theme.textSecondary).font(.callout)
                        Spacer()
                        Button("Edit…") { showCustomRepeat = true }
                    }
                }
            }

            Section("Assignee") {
                Picker("Assigned to", selection: Binding(
                    get: { task.assigneeId ?? "" },
                    set: { setAssignee($0.isEmpty ? nil : $0) }
                )) {
                    Text("No one").tag("")
                    ForEach(members) { m in Text(m.user?.displayName ?? m.userId).tag(m.userId) }
                }
            }

            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    Text("None").tag(Task.Priority.none)
                    Text("Low").tag(Task.Priority.low)
                    Text("Medium").tag(Task.Priority.medium)
                    Text("High").tag(Task.Priority.high)
                }
                .pickerStyle(.segmented)
                .onChange(of: priority) { savePriority() }
            }

            Section("Subtasks") {
                ForEach(subtasks) { st in
                    HStack {
                        Button { toggleSubtask(st) } label: {
                            Image(systemName: st.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(st.completed ? Theme.success : Theme.textMuted)
                        }.buttonStyle(.plain)
                        Text(st.title).strikethrough(st.completed)
                            .foregroundStyle(st.completed ? Theme.textMuted : Theme.textPrimary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Rename…") { editingSubtask = st; editingSubtaskText = st.title }
                        Button("Delete", role: .destructive) { deleteSubtask(st) }
                    }
                }
                HStack {
                    TextField("Add subtask", text: $newSubtask).onSubmit(addSubtask)
                    Button("Add", action: addSubtask).disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Comments") {
                if comments.isEmpty {
                    Text("No comments yet").foregroundStyle(Theme.textMuted).font(.callout)
                }
                ForEach(comments) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.author?.name ?? c.author?.email ?? "Someone")
                                .font(.caption).bold().foregroundStyle(Theme.textSecondary)
                            if let d = c.createdAt {
                                Text(d, style: .relative).font(.caption2).foregroundStyle(Theme.textMuted)
                            }
                        }
                        Text(c.content).foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        // Edit/Delete only your own comments (permission-safe).
                        if let uid = AuthManager.shared.userId, c.authorId == uid {
                            Button("Edit…") { editingComment = c; editingCommentText = c.content }
                            Button("Delete", role: .destructive) { deleteComment(c) }
                        }
                    }
                }
                HStack {
                    TextField("Add a comment…", text: $newComment).onSubmit(addComment)
                    Button("Post", action: addComment).disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Timer") {
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(hms(loggedSeconds)).font(.system(.title3, design: .monospaced))
                            .foregroundStyle(timerRunning ? Theme.accent : Theme.textPrimary)
                    }
                    Spacer()
                    Button(timerRunning ? "Stop" : "Start", systemImage: timerRunning ? "stop.fill" : "play.fill") {
                        toggleTimer()
                    }
                }
            }

            Section("Attachments") {
                ForEach(attachmentRows, id: \.id) { a in
                    HStack {
                        Image(systemName: "paperclip").foregroundStyle(Theme.textMuted)
                        Text(a.name).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if let s = a.url, let u = URL(string: s) {
                            Button("Open") { PlatformApplication.open(u) }
                        }
                    }
                }
                Button { addFile() } label: { Label("Add File…", systemImage: "paperclip") }
            }

            Section {
                Button { openWindow(id: "task", value: task.id) } label: {
                    Label("Open in New Window", systemImage: "macwindow.on.rectangle")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: task.id) { load() }
        .sheet(item: $editingComment) { _ in editSheet(title: "Edit Comment", text: $editingCommentText, onSave: saveEditedComment) }
        .sheet(item: $editingSubtask) { _ in editSheet(title: "Rename Subtask", text: $editingSubtaskText, onSave: renameSubtask) }
        .sheet(isPresented: $showCustomRepeat) {
            MacCustomRepeatEditor(initial: customPattern) { pattern in
                customPattern = pattern
                saveRepeat()
            }
        }
    }

    /// Small reusable edit sheet for a single text value.
    private func editSheet(title: String, text: Binding<String>, onSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("", text: text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { editingComment = nil; editingSubtask = nil }.keyboardShortcut(.escape, modifiers: [])
                Button("Save", action: onSave).buttonStyle(.borderedProminent)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 360)
    }

    // MARK: load + save

    private func load() {
        title = task.title
        notes = task.description
        priority = task.priority
        isAllDay = task.isAllDay
        repeating = task.repeating ?? .never
        customPattern = task.repeatingData
        if let d = task.dueDateTime { hasDue = true; due = d } else { hasDue = false }
        subtasks = (task.listIds ?? []).flatMap { taskService.getTasksForList($0) }
            .filter { $0.parentTaskId == task.id }
        _Concurrency.Task {
            if let listId = task.listIds?.first {
                try? await ListMemberService.shared.fetchMembers(listId: listId)
                members = ListMemberService.shared.membersByList[listId] ?? []
            }
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }

    /// Repeat picker changed: for Custom, open the editor (persist happens on Save); otherwise save now.
    private func handleRepeatChange() {
        if repeating == .custom {
            if customPattern == nil { showCustomRepeat = true } else { saveRepeat() }
        } else {
            customPattern = nil
            saveRepeat()
        }
    }

    private func saveRepeat() {
        _Concurrency.Task {
            _ = try? await taskService.updateTask(
                taskId: task.id, repeating: repeating.rawValue,
                repeatingData: repeating == .custom ? customPattern : nil,
                repeatFrom: MacTaskDetailUpdate.repeatFromArg(task), task: task)
        }
    }

    private func setAssignee(_ id: String?) {
        // Empty string unassigns per the TaskService contract; "No one" (nil) must clear.
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, assigneeId: MacTaskDetailUpdate.assigneeArg(id), task: task) }
    }

    private var loggedSeconds: Int {
        let base = task.timerDuration ?? 0
        if timerRunning, let s = timerStart { return base + Int(Date().timeIntervalSince(s)) }
        return base
    }

    private func toggleTimer() {
        if timerRunning, let s = timerStart {
            let total = (task.timerDuration ?? 0) + Int(Date().timeIntervalSince(s))
            timerRunning = false; timerStart = nil
            _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, timerDuration: total, task: task) }
        } else {
            timerRunning = true; timerStart = Date()
        }
    }

    private func hms(_ s: Int) -> String { String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }

    private var attachmentRows: [(id: String, name: String, url: String?)] {
        (task.attachments ?? []).map { ($0.id, $0.name, Optional($0.url)) }
            + (task.secureFiles ?? []).map { ($0.id, $0.name, nil as String?) }
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let taskId = task.id
        // Read the file OFF the main actor (large files must not freeze the UI), then hand it to
        // the offline-first path: it persists locally and lets the Outbox own the upload (Task 46b669dd).
        _Concurrency.Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return }
            await MainActor.run {
                _ = AttachmentService.shared.saveLocallyAndUploadAsync(
                    fileData: data, fileName: name, mimeType: mime, taskId: taskId)
            }
        }
    }

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != task.title else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, title: t, task: task) }
    }

    private func saveNotes() {
        guard notes != task.description else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, description: notes, task: task) }
    }

    private func savePriority() {
        guard priority != task.priority else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, priority: priority.rawValue, task: task) }
    }

    private func saveDue() {
        // hasDue OFF sends Date.distantPast (the shared clear sentinel) so the due date is cleared.
        _Concurrency.Task {
            _ = try? await taskService.updateTask(taskId: task.id,
                                                  dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due),
                                                  isAllDay: isAllDay, task: task)
        }
    }

    private func setCompleted(_ value: Bool) {
        _Concurrency.Task { _ = try? await taskService.completeTask(id: task.id, completed: value, task: task) }
    }

    // MARK: subtasks + comments

    private func toggleSubtask(_ st: Task) {
        _Concurrency.Task {
            _ = try? await taskService.completeTask(id: st.id, completed: !st.completed, task: st)
            load()
        }
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        newSubtask = ""
        _Concurrency.Task {
            _ = try? await taskService.createTask(listIds: task.listIds ?? [], title: t, parentTaskId: task.id)
            load()
        }
    }

    private func deleteSubtask(_ st: Task) {
        _Concurrency.Task { try? await taskService.deleteTask(id: st.id); load() }
    }

    private func renameSubtask() {
        guard let st = editingSubtask else { return }
        let t = editingSubtaskText.trimmingCharacters(in: .whitespaces)
        editingSubtask = nil
        guard !t.isEmpty, t != st.title else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: st.id, title: t, task: st); load() }
    }

    private func deleteComment(_ c: Comment) {
        _Concurrency.Task {
            try? await CommentService.shared.deleteComment(id: c.id)
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }

    private func saveEditedComment() {
        guard let c = editingComment else { return }
        let text = editingCommentText.trimmingCharacters(in: .whitespaces)
        editingComment = nil
        guard !text.isEmpty, text != c.content else { return }
        _Concurrency.Task {
            _ = try? await CommentService.shared.updateComment(id: c.id, content: text)
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }

    private func addComment() {
        let c = newComment.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        newComment = ""
        _Concurrency.Task {
            _ = try? await CommentService.shared.createComment(taskId: task.id, content: c)
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }
}

/// A torn-off single-task window (opened by id via openWindow(id: "task", value:)).
struct MacTaskWindowView: View {
    let taskId: String?
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared

    private var task: Task? {
        guard let id = taskId else { return nil }
        return listService.lists.lazy.compactMap { list in
            taskService.getTasksForList(list.id).first { $0.id == id }
        }.first
    }

    var body: some View {
        if let task {
            MacTaskDetailView(task: task).frame(minWidth: 400, minHeight: 420)
        } else {
            ContentUnavailableView("Task not found", systemImage: "questionmark.square.dashed")
        }
    }
}
#endif
