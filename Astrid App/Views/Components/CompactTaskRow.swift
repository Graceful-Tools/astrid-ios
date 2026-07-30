import SwiftUI

/// Compact task row for use in reminders and dialogs
/// Matches TaskRowView design but without full-width separator
struct CompactTaskRow: View {
    @Environment(\.colorScheme) var colorScheme

    let task: Task
    let onToggle: () -> Void
    var showDismiss: Bool = false
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            // Checkbox
            Button(action: onToggle) {
                checkboxImage
            }
            .buttonStyle(.plain)

            // Task title and lists
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(task.title)
                    .font(.system(size: 19, weight: .medium))
                    .lineSpacing(-1)
                    .strikethrough(task.completed)
                    .foregroundColor(
                        task.completed
                            ? (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            : (colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    )

                // Combined metadata row: date first (left), then lists - matching web
                if (task.lists != nil && !task.lists!.isEmpty) || task.dueDateTime != nil {
                    HStack(spacing: Theme.spacing8) {
                        // Date (left side)
                        if let dueDate = task.dueDateTime {
                            Text(formatDateShort(dueDate))
                                .font(Theme.Typography.subheadline())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }

                        // Lists (after date)
                        if let lists = task.lists, !lists.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(lists.prefix(2)) { list in
                                    HStack(spacing: 4) {
                                        // Icon based on list privacy
                                        if list.privacy == .PUBLIC {
                                            Image(systemName: "globe")
                                                .font(.system(size: 12))
                                                .foregroundColor(.green)
                                        } else if let members = list.listMembers, members.count > 1 {
                                            Image(systemName: "person.2")
                                                .font(.system(size: 12))
                                                .foregroundColor(Theme.accent)
                                        } else {
                                            Image(systemName: "number")
                                                .font(.system(size: 12))
                                                .foregroundColor(Color(hex: list.displayColor) ?? Theme.accent)
                                        }

                                        Text(list.name)
                                            .font(Theme.Typography.subheadline())
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                if lists.count > 2 {
                                    Text("+\(lists.count - 2)")
                                        .font(Theme.Typography.subheadline())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                }
                            }
                        }

                        Spacer()
                    }
                }
            }

            Spacer()

            // Dismiss button (optional)
            if showDismiss, let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(Theme.spacing12)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Checkbox

    private var priorityColor: Color {
        switch task.priority {
        case .none:
            return Theme.priorityNone
        case .low:
            return Theme.priorityLow
        case .medium:
            return Theme.priorityMedium
        case .high:
            return Theme.priorityHigh
        }
    }

    private var checkboxImage: some View {
        ZStack {
            // Outer circle with priority color border
            Circle()
                .stroke(priorityColor, lineWidth: 2)
                .frame(width: 28, height: 28)

            // Filled circle when completed
            if task.completed {
                Circle()
                    .fill(priorityColor)
                    .frame(width: 28, height: 28)

                // Checkmark icon
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 34, height: 34)
    }

    // MARK: - Date Formatting

    private func formatDateShort(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        CompactTaskRow(
            task: Task(
                id: "1",
                title: "Finish the project presentation",
                description: "Final slides",
                assigneeId: nil,
                assignee: nil,
                creatorId: nil,
                creator: nil,
                dueDateTime: Date().addingTimeInterval(3600),
                isAllDay: true,
                reminderTime: nil,
                reminderSent: false,
                reminderType: nil,
                repeating: .never,
                repeatingData: nil,
                priority: .high,
                lists: [
                    TaskList(
                        id: "list1",
                        name: "Work",
                        color: "#3b82f6",
                        privacy: .PRIVATE,
                        ownerId: "user1",
                        createdAt: Date(),
                        updatedAt: Date(),
                        sortBy: "manual"
                    )
                ],
                listIds: ["list1"],
                isPrivate: false,
                completed: false,
                attachments: nil,
                comments: nil,
                createdAt: Date(),
                updatedAt: Date(),
                originalTaskId: nil,
                sourceListId: nil
            ),
            onToggle: {},
            showDismiss: true,
            onDismiss: {}
        )
        .padding()
    }
    .background(Theme.bgPrimary)
}
