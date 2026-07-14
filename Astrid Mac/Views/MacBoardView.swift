//  MacBoardView.swift
//  Astrid for Mac — kanban board grouped by priority (E2). Complete via TaskService.

#if os(macOS)
import SwiftUI

struct MacBoardView: View {
    let tasks: [Task]
    @StateObject private var taskService = TaskService.shared

    private let columns: [(title: String, pri: Task.Priority, color: Color)] = [
        ("High", .high, Theme.priorityHigh),
        ("Medium", .medium, Theme.priorityMedium),
        ("Low", .low, Theme.priorityLow),
        ("None", .none, Theme.priorityNone),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns, id: \.title) { col in
                    let items = tasks.filter { $0.priority == col.pri && !$0.completed }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(col.color).frame(width: 8, height: 8)
                            Text(col.title).font(.headline).foregroundStyle(Theme.textSecondary)
                            Text("\(items.count)").font(.caption).foregroundStyle(Theme.textMuted)
                        }
                        ForEach(items) { t in card(t) }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 240, alignment: .leading)
                    .background(Theme.bgTertiary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
    }

    private func card(_ t: Task) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { complete(t) } label: {
                Image(systemName: "circle").foregroundStyle(Theme.textMuted)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).foregroundStyle(Theme.textPrimary)
                if let due = t.dueDateTime {
                    Text(due, style: .date).font(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }

    private func complete(_ t: Task) {
        _Concurrency.Task { _ = try? await taskService.completeTask(id: t.id, completed: true, task: t) }
    }
}
#endif
