//  MacTaskDetailView.swift
//  Astrid for Mac — full task detail (C1): edit fields + subtasks + comments.
//
//  Native Mac form styled with the shared Theme. Every write goes through the shared
//  services (TaskService / CommentService); no business logic here.

#if os(macOS)
import SwiftUI

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

    @State private var subtasks: [Task] = []
    @State private var newSubtask = ""
    @State private var comments: [Comment] = []
    @State private var newComment = ""

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
                Toggle("Due date", isOn: $hasDue).onChange(of: hasDue) { if hasDue { saveDue() } }
                if hasDue {
                    DatePicker("When", selection: $due,
                               displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .onChange(of: due) { saveDue() }
                    Toggle("All day", isOn: $isAllDay).onChange(of: isAllDay) { saveDue() }
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
                }
                HStack {
                    TextField("Add a comment…", text: $newComment).onSubmit(addComment)
                    Button("Post", action: addComment).disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button { openWindow(id: "task", value: task.id) } label: {
                    Label("Open in New Window", systemImage: "macwindow.on.rectangle")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: task.id) { load() }
    }

    // MARK: load + save

    private func load() {
        title = task.title
        notes = task.description
        priority = task.priority
        isAllDay = task.isAllDay
        if let d = task.dueDateTime { hasDue = true; due = d } else { hasDue = false }
        subtasks = (task.listIds ?? []).flatMap { taskService.getTasksForList($0) }
            .filter { $0.parentTaskId == task.id }
        _Concurrency.Task {
            comments = (try? await CommentService.shared.fetchComments(taskId: task.id)) ?? []
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
        guard hasDue else { return }
        _Concurrency.Task { _ = try? await taskService.updateTask(taskId: task.id, dueDateTime: due, isAllDay: isAllDay, task: task) }
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
