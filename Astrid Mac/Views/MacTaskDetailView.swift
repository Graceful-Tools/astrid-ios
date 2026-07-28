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
    var onClose: (() -> Void)? = nil   // shown as ✕ in the header when presented as a pop-out
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false
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
        VStack(spacing: 0) {
        // Web-style header (df22157f): ✕ · "Task Details" · ⋯ actions menu.
        HStack {
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(Theme.textMuted).help(NSLocalizedString("actions.close", comment: ""))
            }
            Spacer()
            Text(NSLocalizedString("tasks.task_details", comment: "")).font(.headline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Menu {
                Menu(NSLocalizedString("lists.copy_to_list", comment: "")) {
                    ForEach(MacTaskCopy.targets(lists: listService.lists)) { t in
                        Button(t.label) { copyTask(to: t.listId) }
                    }
                }
                // Share — iOS parity (ShareTaskView): make the shortcode link, then offer the
                // native share sheet (Mail/Messages/AirDrop…) as well as copy-to-clipboard.
                if MacAttachmentsSection.offersAddInMenu(attachments: task.attachments?.count ?? 0,
                                                         secureFiles: task.secureFiles?.count ?? 0) {
                    Button(NSLocalizedString("mac.add_file", comment: ""), systemImage: "paperclip") { addFile() }
                }
                if MacTimerSection.offersStartInMenu(running: timerRunning) {
                    Button(NSLocalizedString("mac.timer_start_menu", comment: ""), systemImage: "play.fill") {
                        toggleTimer()
                    }
                }
                Button(NSLocalizedString("actions.share", comment: "")) { shareTask() }
                if let shareURL {
                    Button(NSLocalizedString("mac.copy_share_link", comment: "")) {
                        MacTaskActions.copyToPasteboard(shareURL.absoluteString)
                    }
                }
                Button(NSLocalizedString("actions.copy", comment: "")) {
                    MacTaskActions.copyToPasteboard(
                        MacTaskActions.clipboardText(title: task.title, shareURL: shareURL))
                }
                Button(NSLocalizedString("mac.open_new_window", comment: "")) { openWindow(id: "task", value: task.id) }
                Divider()
                Button(NSLocalizedString("tasks.delete_task", comment: ""), role: .destructive) { deleteTask() }
            } label: { Image(systemName: "ellipsis.vertical") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

        Form {
            Section {
                HStack(spacing: 10) {
                    // A `Button` here does not fire: inside a Form row (as inside a List row) the
                    // row's own click handling swallows it — the same defect that left the task-row
                    // checkbox dead in 652edb22. A tap gesture DOES receive the click, and keeps
                    // full button semantics for VoiceOver and UI tests.
                    MacTaskCheckbox(completed: task.completed, priority: priority,
                                    size: MacTaskVisuals.detailCheckboxSize,
                                    repeating: MacCheckboxAsset.isRepeating(repeating))
                        .contentShape(Rectangle())
                        .onTapGesture { setCompleted(!task.completed) }
                        .macPointingHand()
                        .help(task.completed ? "Mark incomplete" : "Mark complete")
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
                        .accessibilityAction { setCompleted(!task.completed) }
                    // `labelsHidden()`: inside a Form, macOS renders a TextField's first argument
                    // as a leading label — the stray "Title" prefix on the detail header
                    // (task 4a3360c3). It stays as the empty-state placeholder.
                    TextField(NSLocalizedString("mac.title", comment: ""), text: $title)
                        .labelsHidden()
                        .font(MacTypography.detailTitle)
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                        .focused($titleFocused)
                        .onSubmit(saveTitle)
                }
            }

            // Web-order labeled fields (913216a9) — same design language as the board's inline
            // editor: Who / Date / Priority / Lists / Repeat / Description.
            Section {
                labeled("Who") {
                    Picker("", selection: Binding(
                        get: { task.assigneeId ?? "" },
                        set: { setAssignee($0.isEmpty ? nil : $0) }
                    )) {
                        Text(NSLocalizedString("No one", comment: "")).tag("")
                        ForEach(members) { m in Text(m.user?.displayName ?? m.userId).tag(m.userId) }
                    }
                    .labelsHidden()
                }
                labeled("Date") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(NSLocalizedString("lists.due_date", comment: ""), isOn: $hasDue).onChange(of: hasDue) { saveDue() }
                        if hasDue {
                            DatePicker("", selection: $due,
                                       displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                                .labelsHidden()
                                .onChange(of: due) { saveDue() }
                            Toggle(NSLocalizedString("All day", comment: ""), isOn: $isAllDay).onChange(of: isAllDay) { saveDue() }
                        }
                    }
                }
                labeled("Priority") {
                    MacPriorityPicker(selection: $priority)
                        .onChange(of: priority) { savePriority() }
                }
                labeled("Lists") {
                    HStack(spacing: 4) {
                        let chips = (task.listIds ?? []).compactMap { listService.listsById[$0] }
                        ForEach(chips) { l in
                            HStack(spacing: 4) { MacListIcon(list: l, size: 11); Text(l.name).font(MacTypography.rowMeta) }
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .foregroundStyle(Theme.accent)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                        }
                        if chips.isEmpty { Text("—").foregroundStyle(Theme.textMuted) }
                    }
                }
                labeled("Repeat") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("", selection: $repeating) {
                            ForEach([Task.Repeating.never, .daily, .weekly, .monthly, .yearly, .custom], id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: repeating) { handleRepeatChange() }
                        if repeating == .custom {
                            HStack {
                                Text(customPattern.map(MacCustomRepeat.summary) ?? "Custom…")
                                    .foregroundStyle(Theme.textSecondary).font(.callout)
                                Spacer()
                                Button(NSLocalizedString("actions.edit", comment: "")) { showCustomRepeat = true }
                            }
                        }
                    }
                }
                // Description spans the FULL width below its own label (web/iOS parity —
                // task e4b4f87c). The inline `labeled` row shape squeezed the editor into the
                // ~2/3 left over beside the 80pt label column.
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("tasks.description", comment: ""))
                        .font(MacTypography.label)
                        .foregroundStyle(Theme.textMuted)
                    TextEditor(text: $notes)
                        .frame(minHeight: 70)
                        .frame(maxWidth: .infinity)
                        .focused($notesFocused)
                        .onChange(of: notesFocused) { if !notesFocused { saveNotes() } }
                        .overlay(alignment: .topLeading) {
                            if notes.isEmpty && !notesFocused {
                                Text(NSLocalizedString("mac.click_add_description", comment: ""))
                                    .foregroundStyle(Theme.textMuted)
                                    .padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                // "Last: …" timer caption under the description (web parity — df22157f).
                if let last = task.lastTimerValue, !last.isEmpty {
                    Text(String(format: NSLocalizedString("mac.last_timer", comment: ""), last))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Section(NSLocalizedString("Subtasks", comment: "")) {
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
                        Button(NSLocalizedString("mac.rename_ellipsis", comment: "")) { editingSubtask = st; editingSubtaskText = st.title }
                        Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteSubtask(st) }
                    }
                }
                HStack {
                    TextField(NSLocalizedString("mac.add_subtask", comment: ""), text: $newSubtask).onSubmit(addSubtask)
                    Button(NSLocalizedString("actions.add", comment: ""), action: addSubtask).disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            // Web-style comments (df22157f): "Comments (N)" header + Refresh; own comments as
            // right-aligned lavender bubbles with an avatar and a "You · date" caption.
            Section {
                if comments.isEmpty {
                    Text(NSLocalizedString("mac.no_comments", comment: "")).foregroundStyle(Theme.textMuted).font(.callout)
                }
                ForEach(comments) { c in commentBubble(c) }
            } header: {
                HStack {
                    Text(String(format: NSLocalizedString("mac.comments_count", comment: ""), comments.count))
                    Spacer()
                    Button {
                        _Concurrency.Task { comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? comments }
                    } label: { Label(NSLocalizedString("mac.refresh", comment: ""), systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless).font(.caption)
                }
            }

            // Only while a timer is RUNNING (b2785c35). Starting one lives in the ⋮ menu, and a
            // task with recorded time keeps the caption below, so nothing is hidden — just the
            // permanent 00:00:00 that sat on every task.
            if MacTimerSection.showsSection(running: timerRunning) {
                Section(NSLocalizedString("tasks.timer", comment: "")) {
                    HStack {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(hms(loggedSeconds)).font(.system(.title3, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer()
                        Button(NSLocalizedString("mac.timer_stop", comment: ""), systemImage: "stop.fill") {
                            toggleTimer()
                        }
                    }
                }
            } else if MacTimerSection.showsLoggedCaption(running: timerRunning, loggedSeconds: loggedSeconds) {
                // iOS parity: one caption line instead of a section (task_edit.last_timer).
                Text(String(format: NSLocalizedString("mac.timer_logged", comment: ""), hms(loggedSeconds)))
                    .font(.caption).foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }

            // Only when the task actually carries something (cb2702a9). "Attachments" was also
            // being used as its own key, so every language rendered the raw English word.
            if MacAttachmentsSection.isVisible(attachments: task.attachments?.count ?? 0,
                                               secureFiles: task.secureFiles?.count ?? 0) {
            Section(NSLocalizedString("mac.attachments", comment: "")) {
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
                            .buttonStyle(.borderless).help(NSLocalizedString("attachments.quick_look", comment: ""))
                            .disabled(previewLoadingId == a.id)
                        Button { deleteAttachment(a) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(Theme.error).help(NSLocalizedString("actions.delete", comment: ""))
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
                Button { addFile() } label: { Label(NSLocalizedString("mac.add_file", comment: ""), systemImage: "paperclip") }
            }
            }

            // (Copy / Share / Open-in-Window / Delete live in the header's ⋯ menu — df22157f.)
            if let shareURL {
                Section {
                    HStack {
                        Text(shareURL.absoluteString).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Spacer()
                        Button(NSLocalizedString("actions.copy", comment: "")) { copyToPasteboard(shareURL.absoluteString) }
                        ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .macScrollBars(showScrollBars)
        .scrollContentBackground(.hidden)   // white detail card (like web); dark-safe via MacDetailChrome
        // The grouped style draws each Section on the SYSTEM control background, which is not the
        // card colour — so the panel read as a different shade from the pop-out arrow (which fills
        // MacDetailChrome.background). Painting the rows with the same colour makes the whole card
        // one flat surface, like the web, and the arrow matches by construction.
        .environment(\.defaultMinListRowHeight, 0)
        .listRowBackground(MacDetailChrome.background)

        // STICKY Add-a-comment footer (e13e4959) — board-editor design: pinned to the bottom with
        // the paperclip + timer visible, autocomplete popping above it. Never scrolls away.
        Divider()
        if !commentSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(commentSuggestions) { s in
                    Button { applyCommentSuggestion(s) } label: {
                        Label(s.label, systemImage: s.icon).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .macHoverHighlight()
                }
            }
            .background(Theme.bgSecondary).clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
        }
        HStack(spacing: 8) {
            Button { attachComment() } label: { Image(systemName: "paperclip") }
                .buttonStyle(.borderless).help(NSLocalizedString("mac.attach_file", comment: ""))
            TextField(NSLocalizedString("comments.add_placeholder", comment: ""), text: $newComment)
                .textFieldStyle(.plain)
                .focused($commentFocused)
                .onChange(of: newComment) { updateCommentSuggestions() }
                .onSubmit(addComment)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if timerRunning {
                    Text(hms(loggedSeconds)).font(.caption.monospaced()).foregroundStyle(Theme.accent)
                }
            }
            Button { toggleTimer() } label: { Image(systemName: "timer") }
                .buttonStyle(.borderless)
                .foregroundStyle(timerRunning ? Theme.accent : Theme.textMuted)
                .help(timerRunning ? "Stop timer" : "Start timer")
        }
        .padding(10)
        }
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
        .sheet(item: $editingComment) { _ in editSheet(title: NSLocalizedString("mac.edit_comment", comment: ""), text: $editingCommentText, onSave: saveEditedComment) }
        .sheet(item: $editingSubtask) { _ in editSheet(title: NSLocalizedString("mac.rename_subtask", comment: ""), text: $editingSubtaskText, onSave: renameSubtask) }
        .sheet(isPresented: $showCustomRepeat) {
            MacCustomRepeatEditor(initial: customPattern) { pattern in
                customPattern = pattern
                saveRepeat()
            }
        }
    }

    /// Web-style comment bubble (df22157f): own comments right-aligned in a lavender card with an
    /// avatar and a "You · date" caption; others left-aligned with the author's name.
    @ViewBuilder private func commentBubble(_ c: Comment) -> some View {
        // One shared decision for every surface that shows an author (283a03df).
        let who = MacAuthorDisplay.of(c, currentUser: AuthManager.shared.currentUser)
        let mine = who.isCurrentUser
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 30) }
                if !mine { commentAvatar(who) }
                Text(c.content)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Theme.accent.opacity(0.12) : Theme.bgSecondary,
                                in: RoundedRectangle(cornerRadius: 12))
                if mine { commentAvatar(who) }
                if !mine { Spacer(minLength: 30) }
            }
            HStack(spacing: 4) {
                Text(who.name)
                if let d = c.createdAt { Text("·"); Text(d, style: .relative) }
            }
            .font(.caption2).foregroundStyle(Theme.textMuted)
            .padding(mine ? .trailing : .leading, 30)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .contentShape(Rectangle())
        .contextMenu {
            // Edit/Delete only your own comments (permission-safe).
            if mine {
                Button(NSLocalizedString("actions.edit", comment: "")) { editingComment = c; editingCommentText = c.content }
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteComment(c) }
            }
        }
    }

    private func commentAvatar(_ who: MacAuthorDisplay) -> some View {
        MacAuthorAvatar(display: who, size: 20)
    }

    /// Delete this task via the canonical service, closing the pop-out first.
    private func deleteTask() {
        onClose?()
        MacActions.perform("Delete task") { try await taskService.deleteTask(id: task.id, task: task) }
    }

    /// Labeled field row (web design language, matches MacBoardCardEditor) — Task 913216a9.
    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(MacTypography.label).foregroundStyle(Theme.textMuted)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    /// Small reusable edit sheet for a single text value.
    private func editSheet(title: String, text: Binding<String>, onSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("", text: text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { editingComment = nil; editingSubtask = nil }.keyboardShortcut(.escape, modifiers: [])
                Button(NSLocalizedString("actions.save", comment: ""), action: onSave).buttonStyle(.borderedProminent)
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
        MacActions.perform("Save repeat") {
            _ = try await taskService.updateTask(
                taskId: task.id, repeating: repeating.rawValue,
                repeatingData: repeating == .custom ? customPattern : nil,
                repeatFrom: MacTaskDetailUpdate.repeatFromArg(task), task: task)
        }
    }

    private func setAssignee(_ id: String?) {
        // Empty string unassigns per the TaskService contract; "No one" (nil) must clear.
        MacActions.perform("Update assignee") { _ = try await taskService.updateTask(taskId: task.id, assigneeId: MacTaskDetailUpdate.assigneeArg(id), task: task) }
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
            MacActions.perform("Save timer") { _ = try await taskService.updateTask(taskId: task.id, timerDuration: total, task: task) }
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

    /// Attach a file/photo to the task (2bdd5df3). The upload only happens through an Outbox
    /// upload→comment dependency chain (saveLocallyAndUploadAsync alone starts NO upload — the
    /// old implementation stranded files in the local cache forever). Same working path as the
    /// comment paperclip: persist locally, then post an attachment comment that owns the upload.
    private func addFile() {
        attachComment()
    }

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != task.title else { return }
        MacActions.perform("Save title") { _ = try await taskService.updateTask(taskId: task.id, title: t, task: task) }
    }

    private func saveNotes() {
        guard notes != task.description else { return }
        MacActions.perform("Save notes") { _ = try await taskService.updateTask(taskId: task.id, description: notes, task: task) }
    }

    private func savePriority() {
        guard priority != task.priority else { return }
        MacActions.perform("Save priority") { _ = try await taskService.updateTask(taskId: task.id, priority: priority.rawValue, task: task) }
    }

    private func saveDue() {
        // hasDue OFF sends Date.distantPast (the shared clear sentinel) so the due date is cleared.
        MacActions.perform("Save due date") {
            _ = try await taskService.updateTask(taskId: task.id,
                                                 dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due),
                                                 isAllDay: isAllDay, task: task)
        }
    }

    private func setCompleted(_ value: Bool) {
        // Surface failures instead of swallowing them with `try?` — a silently failing completion
        // is indistinguishable from a dead checkbox (652edb22).
        MacActions.perform("Complete task") {
            _ = try await TaskService.shared.completeTask(id: task.id, completed: value, task: task)
        }
    }

    /// Copy this task into another list (or My Tasks only) via the canonical service.
    private func copyTask(to listId: String?) {
        MacActions.perform("Copy task") {
            _ = try await taskService.copyTask(id: task.id, targetListId: listId, includeComments: true)
        }
    }

    /// Share: generate the link if we don't have one yet, then present the native share sheet.
    /// The link itself comes from the SAME shared service iOS uses (RemoteResourceService).
    private func shareTask() {
        if let shareURL {
            MacTaskActions.presentShareSheet(url: shareURL, relativeTo: nil)
            return
        }
        generatingShare = true
        MacActions.perform("Share task") {
            defer { generatingShare = false }
            let url = try await MacTaskActions.makeShareURL(taskId: task.id)
            shareURL = url
            if let url { MacTaskActions.presentShareSheet(url: url, relativeTo: nil) }
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
        MacActions.perform("Complete subtask") {
            defer { load() }
            _ = try await taskService.completeTask(id: st.id, completed: !st.completed, task: st)
        }
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        newSubtask = ""
        MacActions.perform("Add subtask") {
            defer { load() }
            _ = try await taskService.createTask(listIds: task.listIds ?? [], title: t, parentTaskId: task.id)
        }
    }

    private func deleteSubtask(_ st: Task) {
        MacActions.perform("Delete subtask") { defer { load() }; try await taskService.deleteTask(id: st.id) }
    }

    private func renameSubtask() {
        guard let st = editingSubtask else { return }
        let t = editingSubtaskText.trimmingCharacters(in: .whitespaces)
        editingSubtask = nil
        guard !t.isEmpty, t != st.title else { return }
        MacActions.perform("Rename subtask") { defer { load() }; _ = try await taskService.updateTask(taskId: st.id, title: t, task: st) }
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
