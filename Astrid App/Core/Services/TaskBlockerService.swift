import Foundation

/// The Canonical Control Point for "waiting on" (AITD-429 / AITD-430): views ask this, never
/// `AstridAPIClient` (ASTRID.md §0 rule 1). Shared by the iOS row and the Mac's.
///
/// Online-only, and deliberately so: a blocker's write can be refused as a cycle, and the
/// server moves the task between Ready and Waiting as a side effect. Queuing it in the Outbox
/// would show a link the server may refuse and a status the server has not decided. So a
/// failed write is shown as `tasks.waitingOn.addError` rather than retried later.
///
/// It never writes `statusRole`. The status move the server makes arrives as `task_updated`
/// with the full task, which `TaskService` already applies.
final class TaskBlockerService {
    static let shared = TaskBlockerService()

    private let apiClient = AstridAPIClient.shared

    func blockers(taskId: String) async throws -> TaskBlockersResponse {
        try await apiClient.getTaskBlockers(taskId: taskId)
    }

    /// The blockers after the add. Throws the API error so the caller can tell the cycle
    /// refusal (`TaskBlockers.isCycleRefusal`) from every other failure.
    func addBlocker(taskId: String, blockingTaskId: String) async throws -> [TaskBlocker] {
        try await apiClient.addTaskBlocker(taskId: taskId, blockingTaskId: blockingTaskId).blockedBy
    }

    func removeBlocker(taskId: String, blockingTaskId: String) async throws -> [TaskBlocker] {
        try await apiClient.removeTaskBlocker(taskId: taskId, blockingTaskId: blockingTaskId).blockedBy
    }

    /// Picker candidates for `query`, already ranked and filtered by `TaskBlockers`.
    /// Empty below `TaskBlockers.minimumQueryLength` without a request.
    func candidates(query: String, task: Task, excludedIds: [String]) async throws -> [BlockerSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TaskBlockers.shouldSearch(trimmed) else { return [] }
        let hits = try await apiClient.searchTasksForBlockerPicker(query: trimmed)
        return TaskBlockers.rankCandidates(hits: hits,
                                           taskId: task.id,
                                           taskListIds: taskListMembershipIdsInOrder(task),
                                           excludedIds: excludedIds)
    }
}
