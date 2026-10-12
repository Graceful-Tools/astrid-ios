//  MacTaskOccurrencesRow.swift
//  Astrid for Mac — "Previous" / "Next" occurrence in task details (AITD-491; web's AWTD-1219).
//
//  Shares the rule with iOS: `MacTaskFields.rows` places the row only when
//  `TaskOccurrences.links` finds one, and the chips here are drawn from the same links.

#if os(macOS)
import SwiftUI

struct MacTaskOccurrencesRow: View {
    let links: TaskOccurrenceLinks

    var body: some View {
        FlowLayout(spacing: 6, rowSpacing: 6) {
            if let previousId = links.previousId {
                chip("tasks.occurrences.previous", icon: "chevron.left", opens: previousId)
            }
            if let nextId = links.nextId {
                chip("tasks.occurrences.next", icon: "chevron.right", opens: nextId)
            }
        }
    }

    private func chip(_ key: String, icon: String, opens taskId: String) -> some View {
        Button { open(taskId) } label: {
            Label(NSLocalizedString(key, comment: ""), systemImage: icon)
                .macFont(MacTypography.label)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// As a "Waiting on" chip opens its task: in its own list when it is loaded.
    @MainActor private func open(_ taskId: String) {
        let cached = TaskService.shared.tasks.first { $0.id == taskId }
        MacAppModel.shared.openTask(listId: cached.flatMap { taskListMembershipIdsInOrder($0).first },
                                    taskId: taskId)
    }
}
#endif
