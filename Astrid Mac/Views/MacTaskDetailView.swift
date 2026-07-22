//  MacTaskDetailView.swift
//  Astrid for Mac — full task detail (C1): edit fields + subtasks + comments.
//
//  Native Mac form styled with the shared Theme. Every write goes through the shared
//  services (TaskService / CommentService); no business logic here.

#if os(macOS)
import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers

struct MacTaskDetailView: View {
    let task: Task
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @ObservedObject private var appModel = MacAppModel.shared
    @Environment(\.openWindow) private var openWindow
    @State private var shareURL: URL?
    @State private var generatingShare = false

    @State private var title = ""
    @State private var notes = ""
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool
    @FocusState private var commentFocused: Bool
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
    @State private var previewURL: URL?           // QuickLook target (local temp copy)
    @State private var previewLoadingId: String?  // attachment being downloaded for preview
    @State private var commentSuggestions: [MacAutocomplete.Suggestion] = []
    @State private var commentHit: MacAutocompleteHit?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Button { setCompleted(!task.completed) } label: {
                        MacTaskCheckbox(completed: task.completed, priority: priority, size: 22)
                    }
                    .buttonStyle(.plain)
                    .help(task.completed ? "Mark incomplete" : "Mark complete")
                    TextField("Title", text: $title)
                        .font(.title3)
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                        .focused($titleFocused)
                        .onSubmit(saveTitle)
                }
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
                MacPriorityPicker(selection: $priority)
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
                // @/#/! autocomplete suggestions (shared with chat via MacAutocomplete) — eda86d23.
                if !commentSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(commentSuggestions) { s in
                            Button { applyCommentSuggestion(s) } label: {
                                Label(s.label, systemImage: s.icon).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    Button { attachComment() } label: { Image(systemName: "paperclip") }
                        .buttonStyle(.borderless).help("Attach a file")
                    TextField("Add a comment…  (@ mention, # list, ! task)", text: $newComment)
                        .focused($commentFocused)
                        .onChange(of: newComment) { updateCommentSuggestions() }
                        .onSubmit(addComment)
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
                // URL-backed attachments: type icon + name + size, QuickLook preview + delete.
                ForEach(task.attachments ?? []) { a in
                    HStack(spacing: 8) {
                        Image(systemName: MacAttachmentIcon.symbol(type: a.type, name: a.name))
                            .foregroundStyle(Theme.accent).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            let size = MacAttachmentIcon.humanSize(a.size)
                            if !size.isEmpty { Text(size).font(.caption2).foregroundStyle(Theme.textMuted) }
                        }
                        Spacer()
                        Button { previewAttachment(a) } label: { Image(systemName: "eye") }
                            .buttonStyle(.borderless).help("Quick Look")
                            .disabled(previewLoadingId == a.id)
                        Button { deleteAttachment(a) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.error).help("Delete")
                    }
                }
                // Secure files have no direct URL / delete API — show name + type icon only.
                ForEach(task.secureFiles ?? [], id: \.id) { f in
                    HStack(spacing: 8) {
                        Image(systemName: MacAttachmentIcon.symbol(type: f.mimeType, name: f.name))
                            .foregroundStyle(Theme.textMuted).frame(width: 18)
                        Text(f.name).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                    }
                }
                Button { addFile() } label: { Label("Add File…", systemImage: "paperclip") }
            }

            Section {
                Menu {
                    ForEach(MacTaskCopy.targets(lists: listService.lists)) { t in
                        Button(t.label) { copyTask(to: t.listId) }
                    }
                } label: { Label("Copy to List", systemImage: "doc.on.doc") }

                if let shareURL {
                    HStack {
                        Text(shareURL.absoluteString).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Spacer()
                        Button("Copy") { copyToPasteboard(shareURL.absoluteString) }
                        ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                    }
                } else {
                    Button { generateShareLink() } label: {
                        HStack { Label("Share…", systemImage: "square.and.arrow.up")
                            if generatingShare { Spacer(); ProgressView().controlSize(.small) } }
                    }
                    .disabled(generatingShare)
                }

                Button { openWindow(id: "task", value: task.id) } label: {
                    Label("Open in New Window", systemImage: "macwindow.on.rectangle")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // white detail card (like web); dark-safe via MacDetailChrome
        .background(MacDetailChrome.background)
        .quickLookPreview($previewURL)   // native macOS Quick Look for a downloaded attachment
        // Field-focus bare keys (d/i/s/c) routed from MacAppModel (9a60b697). Mac task detail has no
        // dedicated lists editor yet, so `lists` reveals the schedule/date area as the closest control.
        .onChange(of: appModel.shortcutRequest) { _, req in
            guard let req, case .focus(let field) = req.kind else { return }
            switch field {
            case .description: notesFocused = true
            case .comment:     commentFocused = true
            case .date:        if !hasDue { hasDue = true; saveDue() }
            case .lists:       titleFocused = true
            }
        }
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

    /// Download the attachment to a temp file (Quick Look needs a local URL), then present it.
    private func previewAttachment(_ a: Attachment) {
        guard let remote = URL(string: a.url) else { return }
        previewLoadingId = a.id
        let name = a.name
        _Concurrency.Task {
            defer { previewLoadingId = nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: remote)
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let fileURL = tmp.appendingPathComponent(name)
                try data.write(to: fileURL)
                previewURL = fileURL
            } catch {
                // Fall back to opening in the default app if the download/preview fails.
                PlatformApplication.open(remote)
            }
        }
    }

    /// Delete a URL-backed attachment via the canonical service, then refresh.
    private func deleteAttachment(_ a: Attachment) {
        MacActions.perform("Delete attachment") {
            try await AttachmentService.shared.deleteAttachment(taskId: task.id, attachmentId: a.id)
            load()
        }
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

    /// Copy this task into another list (or My Tasks only) via the canonical service.
    private func copyTask(to listId: String?) {
        MacActions.perform("Copy task") {
            _ = try await taskService.copyTask(id: task.id, targetListId: listId, includeComments: true)
        }
    }

    /// Generate a shareable shortcode URL (then Copy / ShareLink present it).
    private func generateShareLink() {
        generatingShare = true
        MacActions.perform("Create share link") {
            defer { generatingShare = false }   // resets on success AND on thrown error
            let resp = try await RemoteResourceService.shared.createShortcode(targetType: "task", targetId: task.id)
            shareURL = URL(string: resp.url)
        }
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
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
        MacActions.perform("Delete comment") {
            try await CommentService.shared.deleteComment(id: c.id)
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }

    private func saveEditedComment() {
        guard let c = editingComment else { return }
        let text = editingCommentText.trimmingCharacters(in: .whitespaces)
        editingComment = nil
        guard !text.isEmpty, text != c.content else { return }
        MacActions.perform("Edit comment") {
            _ = try await CommentService.shared.updateComment(id: c.id, content: text)
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }

    // MARK: comment autocomplete + attachments (eda86d23)

    private func updateCommentSuggestions() {
        guard let hit = MacAutocomplete.detectTrigger(in: newComment) else { commentSuggestions = []; commentHit = nil; return }
        commentHit = hit
        commentSuggestions = MacAutocomplete.suggestions(for: hit, members: members,
                                                         lists: listService.lists, tasks: taskService.tasks)
    }

    private func applyCommentSuggestion(_ s: MacAutocomplete.Suggestion) {
        guard let hit = commentHit else { return }
        newComment = MacAutocomplete.insert(label: s.label, into: newComment, hit: hit)
        commentSuggestions = []; commentHit = nil
    }

    /// Attach a file to a comment: offline-first upload, then post a comment referencing it.
    private func attachComment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let taskId = task.id
        _Concurrency.Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return }
            await MainActor.run {
                let fileId = AttachmentService.shared.saveLocallyAndUploadAsync(
                    fileData: data, fileName: name, mimeType: mime, taskId: taskId)
                MacActions.perform("Attach to comment") {
                    _ = try await CommentService.shared.createComment(taskId: taskId, content: name, fileId: fileId)
                    comments = (try? await CommentService.shared.fetchComments(taskId: taskId)) ?? []
                }
            }
        }
    }

    private func addComment() {
        let c = newComment.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        commentSuggestions = []; commentHit = nil
        // Keep the draft until the post succeeds; surface failures instead of losing the text.
        MacActions.perform("Post comment") {
            _ = try await CommentService.shared.createComment(taskId: task.id, content: c)
            newComment = ""
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
