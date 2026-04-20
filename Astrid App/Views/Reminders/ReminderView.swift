import SwiftUI

/// Full-screen reminder view shown when user taps notification
/// Matches the web app's AstridReminderPopover design
struct ReminderView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager

    let task: Task
    let onComplete: () -> Void
    let onSnooze: (Int) -> Void

    @State private var astridPhrase: String = ""
    @State private var navigateToDetails = false

    // Get shared list members for social accountability
    private var sharedListMembers: [User] {
        guard let lists = task.lists else { return [] }

        var members: [User] = []
        for list in lists where list.privacy == .SHARED {
            // Pull from canonical `listMembers`, excluding current user.
            if let listMembers = list.listMembers {
                members.append(contentsOf: listMembers.compactMap { lm in
                    guard let user = lm.user, user.id != authManager.userId else { return nil }
                    return user
                })
            }
        }

        // Remove duplicates and limit to 4 faces
        let uniqueMembers = members.reduce(into: [User]()) { result, member in
            if !result.contains(where: { $0.id == member.id }) {
                result.append(member)
            }
        }
        return Array(uniqueMembers.prefix(4))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark overlay
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss()
                    }

                // Main content card
                VStack(spacing: 0) {
                    // Dismiss button above everything
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                        .padding(Theme.spacing16)
                    }

                    // Content
                    VStack(spacing: Theme.spacing24) {
                        // Task Row (using real TaskRowView - same as task list)
                        TaskRowView(
                            task: task,
                            onToggle: {
                                onComplete()
                                dismiss()
                            }
                        )
                        .environmentObject(authManager)

                        // Astrid with Speech Bubble (using shared component)
                        AstridSpeechBubble(message: astridPhrase)
                            .padding(.horizontal, Theme.spacing16)

                        // Collaborators section (if task is on a shared list)
                        if !sharedListMembers.isEmpty {
                            collaboratorsSection
                                .padding(.horizontal, Theme.spacing16)
                        }

                        // Action Buttons
                        actionButtons
                            .padding(.horizontal, Theme.spacing16)
                    }
                    .padding(.bottom, Theme.spacing24)
                }
                .frame(maxWidth: 500)
                .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding(.horizontal, Theme.spacing16)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateToDetails = true
                }
            }
            // navigationDestination must be attached to NavigationStack content, not inside overlays
            .navigationDestination(isPresented: $navigateToDetails) {
                TaskDetailViewNew(task: task)
            }
        }
        .onAppear {
            // Generate random Astrid phrase
            let isDue = isTaskDue()
            astridPhrase = ReminderConstants.getReminderPhrase(isDue: isDue)
        }
    }

    // MARK: - Collaborators Section

    private var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack(spacing: Theme.spacing8) {
                // Collaborator avatars (overlapping circles)
                HStack(spacing: -8) {
                    ForEach(sharedListMembers) { member in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(getInitials(from: member))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }

                // Social accountability message
                Text(NSLocalizedString("reminders.counting_on_you", comment: ""))
                    .font(Theme.Typography.subheadline())
                    .fontWeight(.medium)
                    .foregroundColor(Color.orange)
            }
        }
        .padding(Theme.spacing12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Theme.spacing12) {
            // Complete button (green, full width)
            Button {
                // Success haptic feedback on task completion
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)

                onComplete()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text(NSLocalizedString("reminders.complete", comment: ""))
                        .font(Theme.Typography.headline())
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.spacing16)
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Snooze buttons (15 min full width, then 1 day + 1 week side by side)
            VStack(spacing: 8) {
                // Snooze 15 minutes (full width)
                Button {
                    // Light haptic feedback on snooze
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()

                    onSnooze(15) // 15 minutes
                    dismiss()
                } label: {
                    Text(NSLocalizedString("reminders.snooze_15_minutes", comment: ""))
                        .font(Theme.Typography.headline())
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing16)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                        )
                }

                // 1 day and 1 week side by side
                HStack(spacing: 8) {
                    // Snooze 1 day
                    Button {
                        // Light haptic feedback on snooze
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        onSnooze(1440) // 24 hours in minutes
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("reminders.snooze_1_day", comment: ""))
                            .font(Theme.Typography.headline())
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing16)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                            )
                    }
                    .frame(maxWidth: .infinity)

                    // Snooze 1 week
                    Button {
                        // Light haptic feedback on snooze
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        onSnooze(10080) // 7 days in minutes
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("reminders.snooze_1_week", comment: ""))
                            .font(Theme.Typography.headline())
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacing16)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func isTaskDue() -> Bool {
        guard let dueDate = task.dueDateTime else {
            return false
        }
        return dueDate <= Date()
    }

    private func getInitials(from user: User) -> String {
        if let name = user.name, !name.isEmpty {
            return name.prefix(1).uppercased()
        } else if let email = user.email, !email.isEmpty {
            return email.prefix(1).uppercased()
        }
        return "?"
    }
}

#Preview {
    ReminderView(
        task: Task(
            id: "preview",
            title: "Finish the project presentation",
            description: "Final slides and demo",
            assigneeId: "user1",
            assignee: nil,
            creatorId: "user1",
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
        onComplete: {},
        onSnooze: { _ in }
    )
    .environmentObject(AuthManager.shared)
}
