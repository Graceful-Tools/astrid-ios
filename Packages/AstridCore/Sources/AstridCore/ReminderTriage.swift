import Foundation

/// The reminder triage deck — astrid-core's `reminderTriage` rule (`rows::triage::deck`,
/// AITD-655): mine, open, and due today or overdue, soonest first, with the task the reminder
/// fired for floated to the front unless it is done or somebody else's.
///
/// Synchronous and pure. The answer is **ids** into the tasks sent, in the order they are dealt.
extension CoreRules {
    /// `tasks` are in the API wire shape (an app `Task` encodes as one). `userId` is the
    /// signed-in user; `nil` is an empty deck, not everybody's.
    public static func reminderTriage(
        tasks: [some Encodable], userId: String?, remindedTaskId: String?,
        now: Date = Date(), timeZone: TimeZone = .current
    ) throws -> [String] {
        try ask(ReminderTriageRequest(tasks: tasks.map(AnyEncodable.init), userId: userId,
                                      remindedTaskId: remindedTaskId, now: now,
                                      utcOffsetMinutes: timeZone.secondsFromGMT(for: now) / 60),
                as: ReminderTriageAnswer.self).taskIds
    }
}

private struct ReminderTriageRequest: Encodable {
    let kind = "reminderTriage"
    let tasks: [AnyEncodable]
    let userId: String?
    let remindedTaskId: String?
    let now: Date
    let utcOffsetMinutes: Int
}

private struct ReminderTriageAnswer: Decodable {
    let taskIds: [String]
}
