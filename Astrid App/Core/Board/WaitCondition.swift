import AstridCore
import Combine
import Foundation

/// What a task in Waiting waits for: a day, or another task (AITD-631).
///
/// Jon, 2026-11-12: Waiting means waiting on a task or on a date, nothing else. astrid-core holds
/// the rule (`astrid_rules::waiting`, R1/R2): a move into Waiting that names no condition, on a
/// task that has none already, is refused with `WAITING_NEEDS_CONDITION` and writes nothing, and
/// entering Waiting clears the assignee unless the mover keeps it. Waiting on a PERSON is not
/// Waiting: that task goes to Inbox, assigned to them.
///
/// This is the answer the prompt collects, in the four keys every move command takes
/// (`app::command::WaitOptions`). Shared by iOS and the Mac, like the move itself.
struct WaitCondition: Equatable {
    enum Kind: Equatable {
        /// Wait until this calendar day — an all-day due date, as web's prompt sends it.
        case until(Date)
        /// Wait on this task: attached as a blocker by the same move.
        case on(taskId: String, title: String)
    }

    var kind: Kind
    /// Entering Waiting unassigns the task unless this is set — the prompt's toggle, off by default.
    var keepAssignee: Bool

    /// The core's refusal code: the cue to ask.
    static let refusalCode = "WAITING_NEEDS_CONDITION"

    /// Fold the answer into a move command (`moveTaskToColumn`, `setTaskStatus`, `dropBoardCard`…).
    func apply(to command: inout CoreCommand, calendar: Calendar = .current) {
        switch kind {
        case .until(let day):
            command.set("dueDateTime", WireDate.dueDateString(from: Self.utcMidnight(of: day, in: calendar)))
            command.set("isAllDay", true)
        case .on(let taskId, _):
            command.set("waitOnTaskId", taskId)
        }
        command.set("keepAssignee", keepAssignee)
    }

    /// Was this failure the core (or the server, through it) asking for a condition?
    static func needsCondition(_ error: Error) -> Bool {
        (error as? CoreFailure)?.code == refusalCode
    }

    /// Only a day after today can be waited until: today would wake the task at once (web's rule,
    /// `waiting.prompt.dateInPast`).
    static func isAfterToday(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
    }

    /// The toggle's words: "Keep assigned to me" for the mover's own task, "…to Sam" for someone
    /// else's, and no toggle at all when nobody is assigned.
    static func keepLabel(assigneeId: String?, assigneeName: String?, currentUserId: String?) -> String? {
        guard let assigneeId, !assigneeId.isEmpty else { return nil }
        if assigneeId == currentUserId { return NSLocalizedString("waiting.prompt.keepAssignedToMe", comment: "") }
        let name = assigneeName?.isEmpty == false
            ? assigneeName! : NSLocalizedString("waiting.prompt.theAssignee", comment: "")
        return String(format: NSLocalizedString("waiting.prompt.keepAssignedTo", comment: ""), name)
    }

    /// An all-day date is stored at midnight UTC of the day it names — the picked LOCAL day, so a
    /// late-evening pick in California does not become tomorrow.
    static func utcMidnight(of day: Date, in calendar: Calendar) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return utc.date(from: parts) ?? day
    }
}

/// Asks "until when, or on what?" when the core refuses a move into Waiting, and sends the same
/// move again with the answer (AITD-631).
///
/// Every place that can put a task in Waiting — a board drop, the state chips, the Mac's state
/// menu — runs its move through `move(_:_:)`. The first attempt carries no condition, so a task
/// that already waits on something (a future date, an open blocker), and every move to any other
/// column, simply happens. Only the core's `WAITING_NEEDS_CONDITION` opens the prompt; the root
/// view draws it from `pending`. Cancel sends nothing, so the task stays where it was.
@MainActor
final class WaitingPromptPresenter: ObservableObject {
    static let shared = WaitingPromptPresenter()

    struct Request: Identifiable {
        let id = UUID()
        let task: Task
        let send: (WaitCondition?) async throws -> Void
    }

    @Published private(set) var pending: Request?

    /// Run a move; if the core asks for a condition, hold it for the prompt. Any other failure is
    /// rethrown for the caller to report exactly as it did before.
    func move(_ task: Task, _ send: @escaping (WaitCondition?) async throws -> Void) async throws {
        do {
            try await send(nil)
        } catch where WaitCondition.needsCondition(error) {
            pending = Request(task: task, send: send)
        }
    }

    /// The prompt's answer: the same move again, carrying it.
    func confirm(_ condition: WaitCondition) async throws {
        guard let request = pending else { return }
        try await request.send(condition)
        if pending?.id == request.id { pending = nil }
    }

    func cancel() {
        pending = nil
    }
}
