//  MacBoardCardEditor.swift
//  Astrid for Mac — inline board-card editor (Task efaf8120). Clicking a card expands it vertically
//  to edit in place (like Astrid Web), instead of only opening the side panel. Compact subset of the
//  full detail; all writes go through the shared TaskService.

#if os(macOS)
import SwiftUI

/// Pure expand/collapse toggle — tapping the open card collapses it; tapping another opens it.
enum MacBoardExpand {
    static func toggle(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }
}

struct MacBoardCardEditor: View {
    let task: Task
    let onOpenPanel: () -> Void
    let onDone: () -> Void

    @StateObject private var taskService = TaskService.shared
    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Task.Priority = .none
    @State private var hasDue = false
    @State private var due = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder).onSubmit(saveTitle)

            MacPriorityPicker(selection: $priority).onChange(of: priority) { savePriority() }

            Toggle("Due date", isOn: $hasDue).onChange(of: hasDue) { saveDue() }.font(.caption)
            if hasDue {
                DatePicker("", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().onChange(of: due) { saveDue() }
            }

            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)

            HStack {
                Button("Open…", action: onOpenPanel).buttonStyle(.link).font(.caption)
                Spacer()
                Button("Done") { saveTitle(); saveNotes(); onDone() }.controlSize(.small)
            }
        }
        .padding(.top, 4)
        .task(id: task.id) { load() }
        .onDisappear { saveNotes() }
    }

    private func load() {
        title = task.title; notes = task.description; priority = task.priority
        if let d = task.dueDateTime { hasDue = true; due = d } else { hasDue = false }
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
        _Concurrency.Task {
            _ = try? await taskService.updateTask(taskId: task.id,
                dueDateTime: MacTaskDetailUpdate.dueDateArg(hasDue: hasDue, due: due), isAllDay: false, task: task)
        }
    }
}
#endif
