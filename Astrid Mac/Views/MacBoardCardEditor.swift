//  MacBoardCardEditor.swift
//  Astrid for Mac — inline board-card editor (Tasks efaf8120 + 8e09d3c9). Clicking a card expands it
//  vertically to edit in place, laid out like Astrid Web: labeled Who / Date / Priority / Lists /
//  Description rows, a Comments section, and a STICKY 'Add a comment…' footer with paperclip +
//  timer. All writes go through the shared services (TaskService / CommentService / AttachmentService).

#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    let onOpenPanel: () -> Void
    let onDone: () -> Void

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var notes = ""
    @State private var priority: Task.Priority = .none
    @State private var hasDue = false
    @State private var due = Date()
    @State private var members: [ListMember] = []
    @State private var comments: [Comment] = []
    @State private var newComment = ""
    @State private var timerRunning = false
    @State private var timerStart: Date?
    @State private var attaching = false

    private var taskLists: [TaskList] {
        (task.listIds ?? []).compactMap { id in listService.lists.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    labeled("Who") { whoControl }
                    labeled("Date") { dateControl }
                    labeled("Priority") { MacPriorityPicker(selection: $priority).onChange(of: priority) { savePriority() } }
                    labeled("Lists") { listChips }
                    labeled("Description") {
                        TextField("Add a description…", text: $notes, axis: .vertical)
                            .lineLimit(2...6).textFieldStyle(.roundedBorder).onSubmit(saveNotes)
                    }
                    Divider()
                    commentsSection
                }
                .padding(10)
            }
            .frame(maxHeight: 320)

            // Sticky footer — Add a comment with paperclip + timer, always visible (web parity).
            Divider()
            HStack(spacing: 8) {
                Button { attach() } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.borderless).disabled(attaching).help("Attach a file")
                TextField("Add a comment…", text: $newComment).textFieldStyle(.plain).onSubmit(postComment)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if timerRunning { Text(hms(loggedSeconds)).font(.caption.monospaced()).foregroundStyle(Theme.accent) }
                }
                Button { toggleTimer() } label: { Image(systemName: "timer") }
                    .buttonStyle(.borderless).foregroundStyle(timerRunning ? Theme.accent : Theme.textMuted)
                    .help(timerRunning ? "Stop timer" : "Start timer")
            }
            .padding(8)
        }
        .task(id: task.id) { await load() }
        .onDisappear { saveNotes() }
    }

    // MARK: rows

    private func labeled<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        // Compact 56pt label so the row fits within a ~250pt board column (vs popping out).
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(Theme.textMuted).frame(width: 56, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var whoControl: some View {
        Picker("", selection: Binding(
            get: { task.assigneeId ?? "" },
            set: { setAssignee($0.isEmpty ? nil : $0) }
        )) {
            Text("Unassigned").tag("")
            ForEach(members) { m in Text(m.user?.displayName ?? m.userId).tag(m.userId) }
        }
        .labelsHidden()   // no fixedSize — let it shrink to the column width
    }

    @ViewBuilder private var dateControl: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $hasDue).labelsHidden().onChange(of: hasDue) { saveDue() }
            if hasDue {
                DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().onChange(of: due) { saveDue() }
            } else {
                Text("No date").foregroundStyle(Theme.textMuted).font(.callout)
            }
        }
    }

    @ViewBuilder private var listChips: some View {
        HStack(spacing: 4) {
            ForEach(taskLists) { l in
                HStack(spacing: 4) { MacListIcon(list: l, size: 11); Text(l.name).font(.caption) }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            if taskLists.isEmpty { Text("—").foregroundStyle(Theme.textMuted) }
        }
    }

    @ViewBuilder private var commentsSection: some View {
        Text("Comments (\(comments.count))").font(.caption).bold().foregroundStyle(Theme.textSecondary)
        ForEach(comments) { c in
            VStack(alignment: .leading, spacing: 1) {
                Text(c.author?.name ?? c.author?.email ?? "Someone").font(.caption2).bold().foregroundStyle(Theme.textSecondary)
                Text(c.content).font(.callout).foregroundStyle(Theme.textPrimary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack { Button("Open full detail…", action: onOpenPanel).buttonStyle(.link).font(.caption)
            Spacer(); Button("Done", action: onDone).controlSize(.small) }
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
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, assigneeId: MacTaskDetailUpdate.assigneeArg(id), task: task) }
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
        _Concurrency.Task {
            _ = try? await taskService.updateTask(taskId: task.id,
                dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due), isAllDay: false, task: task)
        }
    }
    private func postComment() {
        let c = newComment.trimmingCharacters(in: .whitespaces); guard !c.isEmpty else { return }
        MacActions.perform("Post comment") {
            _ = try await CommentService.shared.createComment(taskId: task.id, content: c)
            newComment = ""
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
        }
    }
    private func toggleTimer() {
        if timerRunning, let s = timerStart {
            let total = (task.timerDuration ?? 0) + Int(Date().timeIntervalSince(s))
            timerRunning = false; timerStart = nil
            _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, timerDuration: total, task: task) }
        } else { timerRunning = true; timerStart = Date() }
    }
    private func attach() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseFiles = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let taskId = task.id
        attaching = true
        _Concurrency.Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { await MainActor.run { attaching = false }; return }
            await MainActor.run {
                let fileId = AttachmentService.shared.saveLocallyAndUploadAsync(fileData: data, fileName: name, mimeType: mime, taskId: taskId)
                attaching = false
                MacActions.perform("Attach to comment") {
                    _ = try await CommentService.shared.createComment(taskId: taskId, content: name, fileId: fileId)
                    comments = (try? await CommentService.shared.fetchComments(taskId: taskId)) ?? []
                }
            }
        }
    }
}
#endif
