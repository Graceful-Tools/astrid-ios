import Foundation

/// What completing a task does to it — astrid-core's `repeating::completion`, the one place that
/// decides whether a completion rolls a repeating series forward, ends it, or just sets the flag.
///
/// The app applies the answer through its own write path; it never decides the case itself.
public enum CompletionOutcome: Equatable, Sendable {
    /// No rollover: the flag is the whole change. `clearClosedReason` is set when a task is
    /// reopened — a task that is open again is not "won't do" either.
    case toggle(completed: Bool, clearClosedReason: Bool)
    /// The task stays open, due next time round, one occurrence on.
    case rollForward(dueDateTime: Date, isAllDay: Bool, occurrenceCount: Int)
    /// The series has reached its end: completed, and no longer repeating.
    case seriesEnded
}

extension CoreRules {
    /// Decide what marking `task` completed (or not) at `now` does.
    ///
    /// - Parameters:
    ///   - task: the task as the person sees it, in the API wire shape. A view that let them edit
    ///     the due date or the repeat first must pass its edited copy: the rollover anchors on
    ///     those fields.
    ///   - timeZone: the person's zone: a timed task steps on its wall clock ("monthly at 2pm"
    ///     stays 2pm across daylight saving), and an all-day completion anchors on its calendar day.
    public static func completion(
        of task: some Encodable, completed: Bool, at now: Date = Date(), in timeZone: TimeZone = .current
    ) throws -> CompletionOutcome {
        try ask(
            CompletionRequest(
                task: AnyEncodable(task), completed: completed, now: now,
                timeZone: timeZone.identifier),
            as: CompletionAnswer.self
        ).outcome
    }
}

private struct CompletionRequest: Encodable {
    let kind = "completion"
    let task: AnyEncodable
    let completed: Bool
    let now: Date
    let timeZone: String
}

private struct CompletionAnswer: Decodable {
    let outcome: CompletionOutcome

    private enum Keys: String, CodingKey {
        case outcome, completed, clearClosedReason, dueDateTime, isAllDay, occurrenceCount
    }

    init(from decoder: Decoder) throws {
        let answer = try decoder.container(keyedBy: Keys.self)
        switch try answer.decode(String.self, forKey: .outcome) {
        case "toggle":
            outcome = .toggle(
                completed: try answer.decode(Bool.self, forKey: .completed),
                clearClosedReason: try answer.decode(Bool.self, forKey: .clearClosedReason))
        case "rollForward":
            outcome = .rollForward(
                dueDateTime: try answer.decode(Date.self, forKey: .dueDateTime),
                isAllDay: try answer.decode(Bool.self, forKey: .isAllDay),
                occurrenceCount: try answer.decode(Int.self, forKey: .occurrenceCount))
        case "seriesEnded":
            outcome = .seriesEnded
        case let other:
            throw CoreFailure(
                kind: .badRequest, message: "an outcome this build does not know: \(other)",
                status: nil, id: nil)
        }
    }
}

/// Type erasure for the `task` a request carries, so callers pass their own model.
struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: some Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
