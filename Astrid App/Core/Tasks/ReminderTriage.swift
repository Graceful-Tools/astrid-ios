import Foundation

/// The rules behind the reminder triage deck (AITD-441).
///
/// Tapping a reminder opens a deck, one task per screen, and a swipe decides each task:
/// up hands it to the assistant, down keeps it, left completes it, right moves it to tomorrow.
/// Every one of those is a rule someone will want to change later, so they live here as
/// pure logic — no service, no UI — and the view only asks.
///
/// **The deck is the badge.** It holds the same tasks `BadgeManager` counts (mine, incomplete,
/// due today or overdue), so working through the deck is what clears the badge, and the two
/// cannot quietly disagree about what "needs attention" means.
enum ReminderTriage {

    enum Action: Equatable, CaseIterable {
        /// Swipe up — hand the task to the assistant.
        case assignToAssistant
        /// Swipe down — no change, next card.
        case keep
        /// Swipe left — complete (through `TaskService.completeTask`, so repeats roll over).
        case complete
        /// Swipe right — due tomorrow.
        case postpone
    }

    // MARK: - Deck

    /// The tasks to triage, in order: the reminded task first, then everything else the badge
    /// counts, oldest due date first.
    ///
    /// Someone else's task is never dealt, even as the reminded one: completing another
    /// person's task asks for confirmation first (AITD-375), and a swipe is not a confirmation.
    static func deck(from tasks: [Task], currentUserId: String?, remindedTaskId: String?) -> [Task] {
        guard let currentUserId else { return [] }

        let due = tasks
            .filter { $0.assigneeId == currentUserId && !$0.completed && ($0.isDueToday || $0.isOverdue) }
            .sorted { ($0.dueDateTime ?? .distantFuture) < ($1.dueDateTime ?? .distantFuture) }

        guard let remindedTaskId,
              let reminded = tasks.first(where: { $0.id == remindedTaskId }),
              !reminded.completed,
              !TaskLeadingControl.isSomeoneElsesTask(assigneeId: reminded.assigneeId, currentUserId: currentUserId)
        else { return due }

        return [reminded] + due.filter { $0.id != remindedTaskId }
    }

    // MARK: - Swipes

    /// How far a card has to travel before letting go commits it.
    static let commitDistance: Double = 100

    /// The decision a drag makes, or nil when it makes none.
    ///
    /// A drag must pass `commitDistance` along one axis and be clearly more along that axis
    /// than the other — a diagonal is ambiguous, and an ambiguous swipe that completes a task
    /// is worse than one that springs back.
    static func action(forDragX x: Double, y: Double) -> Action? {
        let ax = abs(x), ay = abs(y)
        if ax >= commitDistance, ax > ay * 1.5 { return x < 0 ? .complete : .postpone }
        if ay >= commitDistance, ay > ax * 1.5 { return y < 0 ? .assignToAssistant : .keep }
        return nil
    }

    // MARK: - Tomorrow

    /// Where "Tomorrow" puts a task: tomorrow counted from TODAY, not from the old due date —
    /// a task a week overdue is not helped by moving it to six days ago.
    ///
    /// All-day tasks stay all-day, stored at UTC midnight of the local date like every other
    /// all-day date (`AllDayTimezoneTests`). Timed tasks keep their time of day. A task with no
    /// due date becomes all-day tomorrow: there is no time to keep.
    static func postponedDueDate(for task: Task, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = DueDateQuickPicks.date(daysFromToday: 1, from: now, calendar: calendar)

        guard let due = task.dueDateTime, !task.isAllDay else {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.date(from: calendar.dateComponents([.year, .month, .day], from: tomorrow)) ?? tomorrow
        }

        let time = calendar.dateComponents([.hour, .minute, .second], from: due)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: tomorrow) ?? tomorrow
    }

    /// Whether the postponed task is all-day — see `postponedDueDate`.
    static func postponedIsAllDay(for task: Task) -> Bool {
        task.dueDateTime == nil || task.isAllDay
    }

    // MARK: - The assistant

    /// The default assistant among the known agents — "Astrid" on this brand.
    ///
    /// Identified by its service, never by its address: the address is brand-derived on the
    /// server (task 97208a72). `ChatService` stores each agent's service as `aiAgentType`.
    static func assistant(in agents: [User]) -> User? {
        agents.first { $0.aiAgentType == AvailableAgent.defaultAssistantService }
    }
}
