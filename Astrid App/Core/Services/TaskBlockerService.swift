import AstridCore
import Foundation

/// The Canonical Control Point for "waiting on" (AITD-429 / AITD-430): views ask this, never an
/// API client (ASTRID.md §0 rule 1). Shared by the iOS row and the Mac's — through astrid-core.
///
/// An add or a removal is sent at once, and a refusal — the server refuses a cycle — is thrown,
/// so the row shows `tasks.waitingOn.addError` rather than a link the server will never accept.
/// Only when the network failed does the core queue it (astrid-core CONTRACTS D32).
///
/// It never writes `statusRole`. The status move the server makes arrives as `task_updated`
/// with the full task, which `TaskService` already applies.
@MainActor
final class TaskBlockerService {
    static let shared = TaskBlockerService()

    private var core: CoreSession { AppCore.shared.session }

    /// What a task waits on and what waits on it — the server's, or the cache's when offline.
    func blockers(taskId: String) async throws -> TaskBlockersResponse {
        try await core.run(CoreCommand(kind: "taskBlockers", taskId: taskId), as: TaskBlockersResponse.self)
    }

    /// The blockers after the add. Throws the refusal so the caller can tell the cycle
    /// (`TaskBlockers.isCycleRefusal`) from every other failure.
    func addBlocker(taskId: String, blockingTaskId: String) async throws -> [TaskBlocker] {
        try await core.run(
            CoreCommand(kind: "addTaskBlocker", ["taskId": .value(taskId), "blockingTaskId": .value(blockingTaskId)]),
            as: TaskBlockersResponse.self
        ).blockedBy
    }

    func removeBlocker(taskId: String, blockingTaskId: String) async throws -> [TaskBlocker] {
        try await core.run(
            CoreCommand(kind: "removeTaskBlocker", ["taskId": .value(taskId), "blockingTaskId": .value(blockingTaskId)]),
            as: TaskBlockersResponse.self
        ).blockedBy
    }

    /// Picker candidates for `query`: the server's permission-filtered search (the cache
    /// offline), already filtered and ranked by the core — never the task itself, nothing already
    /// linked, nothing that waits on this task; the same board first.
    func candidates(query: String, task: Task, excludedIds: [String]) async throws -> [BlockerSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TaskBlockers.shouldSearch(trimmed) else { return [] }
        struct Answer: Decodable { let candidates: [BlockerSearchHit] }
        let answer = try await core.run(
            CoreCommand(kind: "taskBlockerCandidates", ["taskId": .value(task.id), "query": .value(trimmed)]),
            as: Answer.self)
        // What the view already holds and the core has not seen yet (a chip added a moment ago).
        return answer.candidates.filter { !excludedIds.contains($0.id) }
    }
}
