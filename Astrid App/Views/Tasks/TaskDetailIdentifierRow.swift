//  TaskDetailIdentifierRow.swift
//  "Task ID" in task details, next to the lists (AITD-437; spec astrid-web
//  docs/specs/TASK_IDENTIFIERS.md §7). Its own file for the reason TaskDetailBlockersRow is:
//  TaskDetailViewNew sits on its SourceFileSizeGuardTests ceiling.
//
//  Whether it shows is `TaskIdentifiers.shows(_:lists:on: .details)` — on a board, with an id.
//  Long-press copies it, the same "Copy task id" the row's context menu offers.

import SwiftUI

struct TaskDetailIdentifierRow: View {
    let task: Task

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var listService = ListService.shared

    var body: some View {
        if TaskIdentifiers.shows(task, lists: listService.lists, on: .details),
           let identifier = task.identifier {
            TwoColumnRow(label: NSLocalizedString("tasks.taskId.label", comment: ""), icon: TaskIdentifiers.symbolName) {
                Text(identifier)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = identifier
                        } label: {
                            Label(NSLocalizedString("tasks.taskId.copy", comment: ""), systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }
}
