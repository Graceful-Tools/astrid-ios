import SwiftUI
import Combine

/// Manages presenting the ReminderView when notifications are tapped
@MainActor
class ReminderPresenter: ObservableObject {
    static let shared = ReminderPresenter()

    @Published var taskToShow: Task?
    @Published var isShowingReminder = false

    /// The triage deck a reminder opens (AITD-441). Empty means the single-task card instead.
    @Published var triageDeck: [Task] = []
    /// The assistant's display name, nil when no assistant is known (disables the up swipe).
    @Published var triageAssistantName: String?
    private var triageAssistantId: String?

    private let taskService = TaskService.shared
    private let notificationManager = NotificationManager.shared

    private init() {
        AppLog.debug("🎯 [ReminderPresenter] Initializing...")
        // Listen for notification taps
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenTask),
            name: NSNotification.Name("OpenTask"),
            object: nil
        )
        AppLog.debug("✅ [ReminderPresenter] Registered observer for OpenTask notifications")
    }

    @objc private func handleOpenTask(_ notification: Notification) {
        AppLog.debug("🎯 [ReminderPresenter] handleOpenTask called!")
        AppLog.debug("🎯 [ReminderPresenter] Notification userInfo: \(notification.userInfo ?? [:])")

        guard let taskId = notification.userInfo?["taskId"] as? String else {
            AppLog.debug("⚠️ [ReminderPresenter] No taskId in notification")
            return
        }

        // Check if this is a test notification
        let isTestNotification = notification.userInfo?["isTestNotification"] as? Bool ?? false

        if isTestNotification {
            AppLog.debug("🧪 [ReminderPresenter] Test notification detected - showing mock task")
            showTestReminder()
        } else {
            AppLog.debug("📱 [ReminderPresenter] Opening reminder for task: \(taskId)")
            showReminder(for: taskId)
        }
    }

    /// Show reminder view for a task
    func showReminder(for taskId: String) {
        AppLog.debug("🔄 [ReminderPresenter] Fetching task \(taskId)...")
        _Concurrency.Task {
            do {
                let task = try await taskService.fetchTask(id: taskId)
                AppLog.debug("✅ [ReminderPresenter] Task fetched: \(task.title)")
                // The fetched copy is the freshest; the rest of the deck comes from the cache.
                let known = [task] + taskService.tasks.filter { $0.id != task.id }
                let deck = ReminderTriage.deck(from: known,
                                               currentUserId: AuthManager.shared.userId,
                                               remindedTaskId: task.id)
                if !deck.isEmpty {
                    await loadTriageAssistant()
                }
                await MainActor.run {
                    self.triageDeck = deck
                    self.taskToShow = task
                    self.isShowingReminder = true
                    AppLog.debug("🎉 [ReminderPresenter] isShowingReminder set to true - popup should show!")
                }
            } catch {
                AppLog.debug("❌ [ReminderPresenter] Failed to fetch task for reminder: \(error)")
            }
        }
    }

    /// Show test reminder with mock task data
    func showTestReminder() {
        AppLog.debug("🧪 [ReminderPresenter] Creating test task...")

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

        AppLog.debug("✅ [ReminderPresenter] Test task created: \(testTask.title)")
        self.triageDeck = []
        self.taskToShow = testTask
        self.isShowingReminder = true
        AppLog.debug("🎉 [ReminderPresenter] isShowingReminder set to true - test popup should show!")
    }

    /// Find the assistant for the up swipe — from the agent cache, or the server if it is empty.
    private func loadTriageAssistant() async {
        var assistant = ReminderTriage.assistant(in: AIAgentCache.shared.load() ?? [])
        if assistant == nil {
            _ = try? await ChatService.shared.fetchAvailableAgents()
            assistant = ReminderTriage.assistant(in: AIAgentCache.shared.load() ?? [])
        }
        triageAssistantId = assistant?.id
        triageAssistantName = assistant.map { $0.name ?? Brand.appName }
    }

    /// Carry out one triage decision (AITD-441). Every write goes through `TaskService`.
    func triage(_ task: Task, _ action: ReminderTriage.Action) {
        _Concurrency.Task {
            do {
                switch action {
                case .keep:
                    return
                case .complete:
                    _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
                case .postpone:
                    _ = try await taskService.updateTask(
                        taskId: task.id,
                        dueDateTime: ReminderTriage.postponedDueDate(for: task),
                        isAllDay: ReminderTriage.postponedIsAllDay(for: task),
                        task: task)
                case .assignToAssistant:
                    guard let assistantId = triageAssistantId else { return }
                    _ = try await taskService.updateTask(taskId: task.id, assigneeId: assistantId, task: task)
                }
            } catch {
                AppLog.debug("❌ [ReminderPresenter] Triage \(action) failed: \(error)")
            }
        }
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
                AppLog.debug("❌ Failed to complete task: \(error)")
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

                AppLog.debug("✅ Updated task '\(task.title)' when to \(snoozeDate)")

                // Reschedule notification
                try await notificationManager.snoozeNotification(for: task, minutes: minutes)

                await MainActor.run {
                    self.isShowingReminder = false
                    self.taskToShow = nil
                }
            } catch {
                AppLog.debug("❌ Failed to snooze task: \(error)")
            }
        }
    }

    /// Dismiss the reminder
    func dismiss() {
        isShowingReminder = false
        taskToShow = nil
        triageDeck = []
    }
}

/// View modifier to add reminder presentation capability to any view
struct ReminderPresentationModifier: ViewModifier {
    @StateObject private var presenter = ReminderPresenter.shared

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $presenter.isShowingReminder) {
                if !presenter.triageDeck.isEmpty {
                    ReminderTriageView(
                        deck: presenter.triageDeck,
                        assistantName: presenter.triageAssistantName,
                        onDecide: { task, action in
                            presenter.triage(task, action)
                        }
                    )
                } else if let task = presenter.taskToShow {
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
