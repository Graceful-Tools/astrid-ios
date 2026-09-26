//  MacBoardCardEditor.swift
//  Astrid for Mac — inline board-card editor (Tasks efaf8120 + 8e09d3c9). Clicking a card expands it
//  vertically to edit in place, laid out like Astrid Web: labeled Who / Date / Priority / Lists /
//  Description rows, a Comments section, and a STICKY 'Add a comment…' footer with paperclip +
//  timer. All writes go through the shared services (TaskService / CommentService / AttachmentService).
//
//  The comments and the composer are the SAME views the task details draw (AITD-432). The card
//  had its own, which never got paste-to-attach, staging, Send, autocomplete, or a bubble that
//  shows a comment's files — so ⌘V with a screenshot on the board did nothing at all.

#if os(macOS)
import SwiftUI
import AppKit
import QuickLook

/// Pure expand/collapse toggle — tapping the open card collapses it; tapping another opens it.
enum MacBoardExpand {
    static func toggle(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }
    /// The field labels, in order, matching Astrid Web (locks the layout contract).
    static let fieldLabels = ["Who", "Date", "Priority", "Lists", "Description"]
}

struct MacBoardCardEditor: View {
    let task: Task
    let onDone: () -> Void

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var notes = ""
    @State private var profileTarget: MacProfileTarget?   // author name → profile (0994eabb)
    @State private var priority: Task.Priority = .none
    @State private var hasDue = false
    @State private var due = Date()
    @State private var members: [ListMember] = []
    @State private var comments: [Comment] = []
    @StateObject private var commentDraft = MacCommentDraft()
    @FocusState private var commentFocused: Bool
    @State private var showSystemComments = false
    @State private var editingComment: Comment?
    @State private var editingCommentText = ""
    @State private var previewURL: URL?
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var timerRunning = false
    @State private var timerStart: Date?

    private var taskLists: [TaskList] {
        (task.listIds ?? []).compactMap { id in listService.lists.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // The SAME fields the detail panel renders — not a second set of rows.
                    // This card used to carry its own labels, its own "Who" Picker and the
                    // date TOGGLE the detail had already replaced, which is exactly the
                    // drift that comes of two implementations of one screen. The title is
                    // omitted: the card face above already shows it.
                    MacTaskFieldsView(task: task, density: .boardCard, showsTitle: false)
                    Divider()
                    commentsSection
                }
                .padding(10)
            }
            .frame(maxHeight: 320)

            // Sticky footer — Add a comment with paperclip + timer, always visible (web parity).
            Divider()
            MacCommentComposerBar(draft: commentDraft, taskId: task.id, members: members,
                                  focus: $commentFocused, onPosted: refreshComments) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if timerRunning { Text(hms(loggedSeconds)).font(.caption.monospaced()).foregroundStyle(Theme.accent) }
                }
            } idle: {
                Button { toggleTimer() } label: { Image(systemName: "timer") }
                    .buttonStyle(.borderless).foregroundStyle(timerRunning ? Theme.accent : Theme.textMuted)
                    .help(timerRunning ? NSLocalizedString("mac.timer_stop_menu", comment: "") : NSLocalizedString("mac.timer_start_menu", comment: ""))
            }
        }
        .macTextSelection()
        .task(id: task.id) { await load() }
        .onDisappear { saveNotes() }
        .sheet(item: $profileTarget) { target in MacUserProfileView(userId: target.id) }
        .sheet(item: $editingComment) { c in
            MacTextEditSheet(title: NSLocalizedString("mac.edit_comment", comment: ""), text: $editingCommentText,
                             onCancel: { editingComment = nil }) {
                editingComment = nil
                MacCommentThreadList.saveEdit(of: c, text: editingCommentText, taskId: task.id, into: $comments)
            }
        }
        .quickLookPreview($previewURL)
    }

    // MARK: rows

    @ViewBuilder private var commentsSection: some View {
        MacCommentsHeader(comments: comments, showSystem: $showSystemComments,
                          isOffline: !network.isConnected) {
            _Concurrency.Task { await refreshComments() }
        }
        .font(.caption).bold().foregroundStyle(Theme.textSecondary)
        MacCommentThreadList(comments: $comments, taskId: task.id,
                             showSystem: showSystemComments, isOffline: !network.isConnected,
                             profileTarget: $profileTarget,
                             onPreviewFile: { file in
                                 _Concurrency.Task { previewURL = await MacCommentThreadList.previewURL(for: file) }
                             },
                             onEdit: { editingComment = $0; editingCommentText = $0.content })
        // Expanding to full screen and closing the card BOTH live in the header now, beside the
        // caret (7017c3c1). They were at opposite ends of a card whose height changes with its
        // content, so the way out and the way further in were nowhere near each other. Done stays
        // as the explicit close for anyone who has scrolled to the bottom of a long card.
        HStack {
            Spacer(); Button(NSLocalizedString("actions.done", comment: ""), action: onDone).controlSize(.small) }
    }

    // MARK: data

    private var loggedSeconds: Int {
        let base = task.timerDuration ?? 0
        if timerRunning, let s = timerStart { return base + Int(Date().timeIntervalSince(s)) }
        return base
    }
    private func hms(_ s: Int) -> String { String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }

    private func load() async {
        notes = task.description; priority = task.priority
        if let d = task.dueDateTime { hasDue = true; due = d } else { hasDue = false }
        if let listId = task.listIds?.first {
            try? await ListMemberService.shared.fetchMembers(listId: listId)
            members = ListMemberService.shared.membersByList[listId] ?? []
        }
        comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
    }

    private func setAssignee(_ id: String?) {
        AppActions.perform("Update assignee") { _ = try await taskService.updateTask(taskId: task.id, assigneeId: MacTaskDetailUpdate.assigneeArg(id), task: task) }
    }
    private func saveNotes() {
        guard notes != task.description else { return }
        AppActions.perform("Save notes") { _ = try await taskService.updateTask(taskId: task.id, description: notes, task: task) }
    }
    private func savePriority() {
        guard priority != task.priority else { return }
        AppActions.perform("Save priority") { _ = try await taskService.updateTask(taskId: task.id, priority: priority.rawValue, task: task) }
    }
    private func saveDue() {
        AppActions.perform("Save due date") {
            _ = try await taskService.updateTask(taskId: task.id,
                dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due), isAllDay: false, task: task)
        }
    }
    private func refreshComments() async {
        comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? comments
    }
    private func toggleTimer() {
        if timerRunning, let s = timerStart {
            let total = (task.timerDuration ?? 0) + Int(Date().timeIntervalSince(s))
            timerRunning = false; timerStart = nil
            AppActions.perform("Save timer") { _ = try await taskService.updateTask(taskId: task.id, timerDuration: total, task: task) }
        } else { timerRunning = true; timerStart = Date() }
    }
}
#endif
