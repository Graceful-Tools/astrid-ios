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
    /// Full-screen task details (42013da7). Shared with MacRootView through AppStorage rather than
    /// a binding threaded through the pop-out, exactly as the board's full screen is.
    @AppStorage("macDetailFullScreen") private var detailFullScreen = false
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @ObservedObject private var appModel = MacAppModel.shared
    @Environment(\.openWindow) private var openWindow
    @State private var shareURL: URL?
    @State private var generatingShare = false

    @State private var title = ""
    @State private var notes = ""
    /// One editor at a time, one save rule (55010e29). The session decides WHICH editor is
    /// live; each field still saves on blur, so exclusivity and saving stay separable.
    @StateObject private var editing = EditingSession()
    private static let titleEditor: EditorID = "mac.detail.title"
    private static let notesEditor: EditorID = "mac.detail.notes"
    private static let commentEditor: EditorID = "mac.detail.comment"

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
    /// Files picked but not yet posted (task 3b3d70ce). Rendered as previews above the field;
    /// nothing reaches the server as a comment until Post.
    @State private var stagedFiles: [AttachedFileInfo] = []
    @State private var editingComment: Comment?
    @State private var editingCommentText = ""
    @State private var previewURL: URL?           // QuickLook target (local temp copy)
    @State private var previewLoadingId: String?  // attachment being downloaded for preview
    /// System comments ("marked complete", "moved to …") are hidden until asked for — iOS parity
    /// (CommentSectionViewEnhanced). Task 9c24d16c.
    @State private var showSystemComments = false
    @State private var expandedStreaks: Set<String> = []   // folded completion runs (dd3fda86)
    @State private var profileTarget: MacProfileTarget?      // author name tapped → profile sheet (0994eabb)
    @ObservedObject private var network = NetworkMonitor.shared
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
            // Full screen (42013da7) — the point of the redesign is room for the description, and
            // the widest the pop-out can ever be is the detail column. This takes the window.
            // Same affordance and icons as the board's full screen (a34d0163).
            Button {
                withAnimation(MacMotion.fast) { detailFullScreen.toggle() }
            } label: {
                Image(systemName: detailFullScreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless).foregroundStyle(Theme.textMuted)
            .help(NSLocalizedString(detailFullScreen ? "board.exit_full_screen" : "board.full_screen",
                                    comment: ""))
            .accessibilityIdentifier("taskDetail.fullScreen")
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
            } label: {
                // A real symbol, stood on end: macOS has no "ellipsis.vertical", and asking for
                // one rendered an empty label so only the menu's own chevron showed (59d51b80).
                Image(systemName: MacSymbols.detailMenu)
                    .rotationEffect(.degrees(MacSymbols.detailMenuRotation))
            }
            // Hide that chevron too — the ⋮ IS the affordance, and the indicator was half of
            // what made the control read as "^".
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(Theme.textMuted)
            .accessibilityIdentifier("taskDetail.overflowMenu")
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

        Form {
            // The task's fields — title, when, lists, description — and the leading
            // control that holds priority, assignee and completion. The SAME view the
            // board's inline card editor renders, so the two cannot drift apart the way
            // they did when this panel's date control was rebuilt and the board kept the
            // old toggle (MacTaskFieldsView).
            Section {
                MacTaskFieldsView(task: task, density: .detail, showsTitle: true)
            }

            Section {
                // "Last: …" timer caption under the description (web parity — df22157f).
                if let last = task.lastTimerValue, !last.isEmpty {
                    Text(String(format: NSLocalizedString("mac.last_timer", comment: ""), last))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            Section(NSLocalizedString("Subtasks", comment: "")) {
                ForEach(subtasks) { st in
                    HStack(spacing: MacSubtaskRow.checkboxGap) {
                        // The app's own checkbox artwork, in the subtask's priority — not a
                        // green SF-Symbol circle, which was the one checkbox in the app that
                        // did not look like the others.
                        Button { toggleSubtask(st) } label: {
                            MacTaskCheckbox(completed: st.completed, priority: st.priority,
                                            size: MacSubtaskRow.checkboxSize,
                                            repeating: MacCheckboxAsset.isRepeating(st.repeating ?? .never))
                        }
                        .buttonStyle(.plain)
                        .macPointingHand()
                        Text(st.title)
                            .font(MacTypography.detailBody)
                            .strikethrough(st.completed)
                            .foregroundStyle(st.completed ? Theme.textMuted : Theme.textPrimary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(NSLocalizedString("mac.rename_ellipsis", comment: "")) { editingSubtask = st; editingSubtaskText = st.title }
                        Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) { deleteSubtask(st) }
                    }
                }
                // The add row IS a subtask row: same checkbox column, same text position.
                // It was a labelled field plus an "Add" button, which lined up with neither
                // the rows above it nor anything else in the panel.
                HStack(spacing: MacSubtaskRow.checkboxGap) {
                    MacTaskCheckbox(completed: false,
                                    priority: MacSubtaskRow.placeholderPriority(
                                        for: task, lists: listService.listsById),
                                    size: MacSubtaskRow.checkboxSize)
                        .opacity(MacSubtaskRow.placeholderOpacity)
                        .accessibilityHidden(true)
                    TextField(NSLocalizedString("mac.add_subtask", comment: ""), text: $newSubtask)
                        .textFieldStyle(.plain)
                        .font(MacTypography.detailBody)
                        .onSubmit(addSubtask)
                }
            }

            // Web-style comments (df22157f): "Comments (N)" header + Refresh; own comments as
            // right-aligned lavender bubbles with an avatar and a "You · date" caption.
            Section {
                if comments.isEmpty {
                    Text(NSLocalizedString("mac.no_comments", comment: "")).foregroundStyle(Theme.textMuted).font(.callout)
                }
                // A repeating task appends a completion line per rollover; a run of them folds
                // into one streak row you can expand (dd3fda86).
                ForEach(CompletionStreak.fold(
                    MacSystemComments.displayed(comments, showingSystem: showSystemComments,
                                                isOffline: !network.isConnected))) { item in
                    switch item {
                    case .comment(let c):
                        commentBubble(c)
                    case .streak(let streak):
                        streakRow(streak)
                    }
                }
            } header: {
                HStack {
                    Text(String(format: NSLocalizedString("mac.comments_count", comment: ""),
                                MacSystemComments.count(comments, showingSystem: showSystemComments,
                                                        isOffline: !network.isConnected)))
                    if MacSystemComments.showsToggle(comments, isOffline: !network.isConnected) {
                        Button(MacSystemComments.toggleTitle(showingSystem: showSystemComments)) {
                            showSystemComments.toggle()
                        }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(Theme.textMuted)
                    }
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
        // A grouped Form ignores `scrollIndicators`, so the bar stayed on the right of the details
        // whether or not there was anything to scroll (1a112a44). This reaches the NSScrollView.
        .macFormScrollBars(showScrollBars)
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
        stagedAttachments
        HStack(spacing: 8) {
            Button { attachComment() } label: { Image(systemName: "paperclip") }
                .buttonStyle(.borderless).help(NSLocalizedString("mac.attach_file", comment: ""))
                .disabled(AttachmentQueue.isFull(stagedFiles))
            TextField(NSLocalizedString("comments.add_placeholder", comment: ""), text: $newComment)
                .textFieldStyle(.plain)
                .focused($commentFocused)
                .onChange(of: commentFocused) { _, focused in
                    if focused { editing.begin(Self.commentEditor) } else { editing.end(Self.commentEditor) }
                }
                .onChange(of: newComment) { updateCommentSuggestions() }
                .onSubmit(addComment)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if timerRunning {
                    Text(hms(loggedSeconds)).font(.caption.monospaced()).foregroundStyle(Theme.accent)
                }
            }
            // The trailing slot becomes Send as soon as there is something to send (AITD-303).
            // Return already posted; nothing said so, and a staged screenshot had no visible way
            // out. Stopping a running timer stays reachable — the detail shows a Timer section
            // with Stop while one runs.
            if MacCommentSend.showsSend(text: newComment, stagedCount: stagedFiles.count) {
                Button(action: addComment) { Image(systemName: "paperplane.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                    .macPointingHand()
                    .help(NSLocalizedString("chat.send", comment: ""))
                    .accessibilityIdentifier("comment.send")
            } else {
                Button { toggleTimer() } label: { Image(systemName: "timer") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(timerRunning ? Theme.accent : Theme.textMuted)
                    .help(timerRunning ? "Stop timer" : "Start timer")
            }
        }
        .padding(10)
        }
        .background(MacDetailChrome.background)
        .macTextSelection()
        .quickLookPreview($previewURL)   // native macOS Quick Look for a downloaded attachment
        // Field-focus bare keys (d/i/s/c) routed from MacAppModel (9a60b697). Only the
        // comment field still lives here — description, date and lists moved into
        // MacTaskFieldsView, which handles their half of the same request.
        .onChange(of: appModel.shortcutRequest) { _, req in
            guard let req, case .focus(let field) = req.kind else { return }
            if field == .comment { commentFocused = true }
        }
        .task(id: task.id) { load() }
        // Exclusivity, applied: when the session hands the editor over, the fields that lost it
        // actually resign — and resigning is what saves, so the displaced edit is committed
        // rather than dropped (55010e29).
        .onChange(of: editing.activeEditor) { _, active in
            if active != Self.titleEditor { titleFocused = false }
            if active != Self.notesEditor { notesFocused = false }
            if active != Self.commentEditor { commentFocused = false }
        }
        // Leaving the detail — closing it, or switching to another task — commits whatever was
        // open. Same click-out rule, applied to the view going away.
        .onDisappear { editing.commitAll() }
        .sheet(item: $profileTarget) { target in MacUserProfileView(userId: target.id) }
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
    ///
    /// The bubble also draws the comment's OWN files (AITD-304). It used to draw `c.content` and
    /// nothing else, so a file posted without a caption arrived as an empty pill — which is what
    /// "the attachment is broken" turned out to mean: it attached, and nothing ever showed it.
    @ViewBuilder private func commentBubble(_ c: Comment) -> some View {
        // One shared decision for every surface that shows an author (283a03df).
        let who = MacAuthorDisplay.of(c, currentUser: AuthManager.shared.currentUser)
        let mine = who.isCurrentUser
        let files = MacCommentBubble.attachments(of: c)
        VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                if mine { Spacer(minLength: 30) }
                if !mine { commentAvatar(who, authorId: c.authorId) }
                VStack(alignment: .leading, spacing: 6) {
                    if !files.isEmpty {
                        MacCommentAttachmentsView(files: files) { previewSecureFile($0) }
                    }
                    // No text, no text bubble — an empty pill under a photo reads as a failure.
                    if MacCommentBubble.showsText(c.content) {
                        Text(c.content)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Theme.accent.opacity(0.12) : Theme.bgSecondary,
                            in: RoundedRectangle(cornerRadius: 12))
                if mine { commentAvatar(who, authorId: c.authorId) }
                if !mine { Spacer(minLength: 30) }
            }
            HStack(spacing: 4) {
                // Names open the profile, as on iOS. System comments have no id and stay plain.
                Text(who.name).macOpensProfile(c.authorId, target: $profileTarget)
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

    /// The photo opens the profile too — people click the face at least as often as the name.
    /// A folded run of completions (dd3fda86) — one line, expanding to the actual dates on click.
    @ViewBuilder private func streakRow(_ streak: CompletionStreak.Streak) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(MacMotion.fast) {
                    if expandedStreaks.contains(streak.id) { expandedStreaks.remove(streak.id) }
                    else { expandedStreaks.insert(streak.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(Theme.accent)
                    Text(CompletionStreak.summary(for: streak))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: expandedStreaks.contains(streak.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textMuted)
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).macPointingHand()

            if expandedStreaks.contains(streak.id) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(streak.dates, id: \.self) { date in
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func commentAvatar(_ who: MacAuthorDisplay, authorId: String?) -> some View {
        MacAuthorAvatar(display: who, size: 20)
            .macOpensProfile(authorId, target: $profileTarget)
    }

    /// Delete this task via the canonical service, closing the pop-out first.
    private func deleteTask() {
        onClose?()
        MacActions.perform("Delete task") { try await taskService.deleteTask(id: task.id, task: task) }
    }

    /// Labeled field row (web design language, matches MacBoardCardEditor) — Task 913216a9.

    /// Small reusable edit sheet for a single text value.
    private func editSheet(title: String, text: Binding<String>, onSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("", text: text, axis: .vertical).lineLimit(2...6).textFieldStyle(.roundedBorder)
                .macTextSelection()
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
        // Ask parentage directly. Walking the parent's lists could not see a child of a listless
        // task at all — every task added from My Tasks — and duplicated children when the parent
        // sat in several lists (effc7112).
        subtasks = MacSubtasks.of(parent: task, in: taskService.tasks)
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

    /// Open a comment's file in Quick Look (AITD-304). The SHARED preparer resolves the bytes —
    /// a still-uploading staged file from the local copy, anything else from the cache or the
    /// server — so a photo can be opened full size the moment it is posted, offline included.
    private func previewSecureFile(_ file: SecureFile) {
        previewLoadingId = file.id
        _Concurrency.Task {
            defer { previewLoadingId = nil }
            let items = await AttachmentService.shared.prepareFilesForPreview(files: [file])
            if let first = items.first { previewURL = first.url }
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

    /// STAGE a file on the comment being written (task 3b3d70ce).
    ///
    /// This used to post immediately, with the filename as the body — so the paperclip meant
    /// "post a comment that is a file" rather than "attach to this comment". You could not see
    /// what you had picked, and you could not say anything alongside it.
    ///
    /// The upload still starts now rather than on send: it is offline-first and returns a temp
    /// id straight away, so by the time you press Post the bytes are usually already gone. What
    /// changed is only WHEN the comment is created.
    private func attachComment() {
        guard !AttachmentQueue.isFull(stagedFiles) else { return }
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
                // The SHARED queue owns the cap and the duplicate rule. Its header records why:
                // hand-rolling this got "pick a second file" wrong once already, and the first
                // pick vanished silently.
                stagedFiles = AttachmentQueue.adding(
                    AttachedFileInfo(fileId: fileId, fileName: name, fileSize: data.count,
                                     mimeType: mime,
                                     imageData: mime.hasPrefix("image/") ? data : nil),
                    to: stagedFiles)
            }
        }
    }

    /// The staged files, above the comment field — a strip, since several can be queued.
    @ViewBuilder private var stagedAttachments: some View {
        if !stagedFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stagedFiles, id: \.fileId) { file in
                        ZStack(alignment: .topTrailing) {
                            if file.isImage, let data = file.imageData, let image = NSImage(data: data) {
                                Image(nsImage: image)
                                    .resizable().aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6).fill(Theme.bgSecondary)
                                        .frame(width: 56, height: 56)
                                    VStack(spacing: 2) {
                                        Image(systemName: "doc").font(.system(size: 18))
                                        Text(file.fileName.components(separatedBy: ".").last?.uppercased() ?? "FILE")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(Theme.textMuted)
                                }
                            }
                            // Without this a mis-picked file could only be got rid of by posting it.
                            Button {
                                if file.fileId.hasPrefix("temp_") {
                                    AttachmentService.shared.cancelUpload(tempFileId: file.fileId)
                                }
                                stagedFiles = AttachmentQueue.removing(fileId: file.fileId, from: stagedFiles)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white, Color.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .help(NSLocalizedString("actions.remove", comment: ""))
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 8)
            }
        }
    }

    private func addComment() {
        let c = newComment.trimmingCharacters(in: .whitespaces)
        // Either text or a staged file is enough to post; neither is not.
        guard !c.isEmpty || !stagedFiles.isEmpty else { return }
        commentSuggestions = []; commentHit = nil
        // The SHARED splitter. The comments endpoint takes a single fileId, so several files
        // become several comments — with the typed text on the FIRST only, since repeating a
        // caption under every photo reads as a stutter. iOS sends through this same function.
        let drafts = CommentAttachmentBatch.drafts(text: c,
                                                   fileIds: stagedFiles.map(\.fileId),
                                                   useMarkdown: false)
        guard !drafts.isEmpty else { return }
        let author = MacCommentPost.authorId(currentUserId: AuthManager.shared.userId)
        // Keep the draft until the post succeeds; surface failures instead of losing the text.
        MacActions.perform("Post comment") {
            // One at a time so they land in the order they were picked.
            for draft in drafts {
                _ = try await CommentService.shared.createComment(
                    taskId: task.id, content: draft.content,
                    fileId: draft.fileId, authorId: author)
            }
            newComment = ""
            stagedFiles = []
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
