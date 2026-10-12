//  TaskDetailOccurrencesRow.swift
//  "Previous" / "Next" occurrence in task details (AITD-491; web's AWTD-1219).
//
//  Which links exist is `TaskOccurrences.links`, the rule the Mac shares — this file is the iOS
//  styling around it. A task outside a chain draws nothing, so every ordinary list is untouched.

import SwiftUI

struct TaskDetailOccurrencesRow: View {
    let task: Task

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var taskService = TaskService.shared

    private var links: TaskOccurrenceLinks { TaskOccurrences.links(for: task, in: taskService.tasks) }

    var body: some View {
        if !links.isEmpty {
            TwoColumnRow(label: NSLocalizedString("tasks.occurrences.label", comment: ""),
                         icon: "repeat") {
                FlowLayout(spacing: Theme.spacing8, rowSpacing: Theme.spacing8) {
                    if let previousId = links.previousId {
                        chip("tasks.occurrences.previous", icon: "chevron.left", opens: previousId)
                    }
                    if let nextId = links.nextId {
                        chip("tasks.occurrences.next", icon: "chevron.right", opens: nextId)
                    }
                }
            }
        }
    }

    /// Opens that occurrence on top of this one, so Back returns here — the same in-stack
    /// navigation a "Waiting on" chip uses.
    private func chip(_ key: String, icon: String, opens taskId: String) -> some View {
        Button {
            if let url = URL(string: "astrid://tasks/\(taskId)") { openURL(url) }
        } label: {
            Label(NSLocalizedString(key, comment: ""), systemImage: icon)
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .lineLimit(1)
                .chipBackground(colorScheme)
        }
        .buttonStyle(.plain)
    }
}
