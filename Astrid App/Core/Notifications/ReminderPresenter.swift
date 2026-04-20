import SwiftUI
import Combine

/// Manages presenting the ReminderView when notifications are tapped
@MainActor
class ReminderPresenter: ObservableObject {
    static let shared = ReminderPresenter()

    @Published var taskToShow: Task?
    @Published var isShowingReminder = false

    private let taskService = TaskService.shared
    private let notificationManager = NotificationManager.shared

    private init() {
        print("🎯 [ReminderPresenter] Initializing...")
        // Listen for notification taps
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenTask),
            name: NSNotification.Name("OpenTask"),
            object: nil
        )
        print("✅ [ReminderPresenter] Registered observer for OpenTask notifications")
    }

    @objc private func handleOpenTask(_ notification: Notification) {
        print("🎯 [ReminderPresenter] handleOpenTask called!")
        print("🎯 [ReminderPresenter] Notification userInfo: \(notification.userInfo ?? [:])")

        guard let taskId = notification.userInfo?["taskId"] as? String else {
            print("⚠️ [ReminderPresenter] No taskId in notification")
            return
        }

        // Check if this is a test notification
        let isTestNotification = notification.userInfo?["isTestNotification"] as? Bool ?? false

        if isTestNotification {
            print("🧪 [ReminderPresenter] Test notification detected - showing mock task")
            showTestReminder()
        } else {
            print("📱 [ReminderPresenter] Opening reminder for task: \(taskId)")
            showReminder(for: taskId)
        }
    }

    /// Show reminder view for a task
    func showReminder(for taskId: String) {
        print("🔄 [ReminderPresenter] Fetching task \(taskId)...")
        _Concurrency.Task {
            do {
                let task = try await taskService.fetchTask(id: taskId)
                print("✅ [ReminderPresenter] Task fetched: \(task.title)")
                await MainActor.run {
                    self.taskToShow = task
                    self.isShowingReminder = true
                    print("🎉 [ReminderPresenter] isShowingReminder set to true - popup should show!")
                }
            } catch {
                print("❌ [ReminderPresenter] Failed to fetch task for reminder: \(error)")
            }
        }
    }

    /// Show test reminder with mock task data
    func showTestReminder() {
        print("🧪 [ReminderPresenter] Creating test task...")

        // Create a mock test task
        let testTask = Task(
            id: "test-reminder-\(UUID().uuidString)",
            title: NSLocalizedString("notification.test_reminder", comment: "Test Reminder Notification"),
            description: "This is a test notification to demonstrate the reminder popup! Tap the green button to complete, or snooze for later.",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: Date().addingTimeInterval(3600), // Due in 1 hour (timed task)
            isAllDay: false,
            reminderTime: Date(),
            reminderSent: true,
            reminderType: .push,
            repeating: .never,
            repeatingData: nil,
            priority: .high,
            lists: [
                TaskList(
                    id: "test-list",
                    name: "🧪 Test Notifications",
                    color: "#3b82f6",
                    privacy: .PRIVATE,
                    ownerId: "test",
                    createdAt: Date(),
                    updatedAt: Date(),
                    sortBy: "manual"
                )
            ],
            listIds: ["test-list"],
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalTaskId: nil,
            sourceListId: nil
        )

        print("✅ [ReminderPresenter] Test task created: \(testTask.title)")
        self.taskToShow = testTask
        self.isShowingReminder = true
        print("🎉 [ReminderPresenter] isShowingReminder set to true - test popup should show!")
    }

    /// Complete the task
    func completeTask() {
        guard let task = taskToShow else { return }

        _Concurrency.Task {
            do {
                // Pass `task` so the rollover uses the latest known state
                // instead of relying on whatever happens to be in the
                // in-memory cache at notification time (which may be empty
                // if the app was just launched from the banner).
                _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
                await MainActor.run {
                    self.isShowingReminder = false
                    self.taskToShow = nil
                }
            } catch {
                print("❌ Failed to complete task: \(error)")
            }
        }
    }

    /// Snooze the task notification
    func snoozeTask(minutes: Int) {
        guard let task = taskToShow else { return }

        _Concurrency.Task {
            do {
                // Calculate new when/due time (current time + snooze duration)
                let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

                // Update task's when date
                _ = try await taskService.updateTask(
                    taskId: task.id,
                    when: snoozeDate,
                    whenTime: snoozeDate
                )

                print("✅ Updated task '\(task.title)' when to \(snoozeDate)")

                // Reschedule notification
                try await notificationManager.snoozeNotification(for: task, minutes: minutes)

                await MainActor.run {
                    self.isShowingReminder = false
                    self.taskToShow = nil
                }
            } catch {
                print("❌ Failed to snooze task: \(error)")
            }
        }
    }

    /// Dismiss the reminder
    func dismiss() {
        isShowingReminder = false
        taskToShow = nil
    }
}

/// View modifier to add reminder presentation capability to any view
struct ReminderPresentationModifier: ViewModifier {
    @StateObject private var presenter = ReminderPresenter.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $presenter.isShowingReminder) {
                if let task = presenter.taskToShow {
                    ReminderView(
                        task: task,
                        onComplete: {
                            presenter.completeTask()
                        },
                        onSnooze: { minutes in
                            presenter.snoozeTask(minutes: minutes)
                        }
                    )
                }
            }
    }
}

extension View {
    /// Enable reminder presentation for this view
    func withReminderPresentation() -> some View {
        modifier(ReminderPresentationModifier())
    }
}
