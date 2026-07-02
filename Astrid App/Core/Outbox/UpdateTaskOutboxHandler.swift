import Foundation

/// Self-contained payload for an `updateTask` Outbox entry. `UpdateTaskRequest`
/// round-trips through JSON (its encoder emits only the non-nil fields), so the
/// replayed PUT body matches the legacy one exactly.
struct UpdateTaskOutboxPayload: Codable, Equatable {
    var taskId: String
    var updates: UpdateTaskRequest
}

/// Outbox handler for a task update. PUT is value-idempotent and iOS doesn't send
/// `If-Unmodified-Since`, so replaying (or dual-writing) the same body is safe —
/// no concurrency 412s, no duplicates. Resolves a temp task id (offline-created
/// task) before sending.
enum UpdateTaskOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(UpdateTaskOutboxPayload.self, from: entry.payload) else {
            return .permanent("updateTask: undecodable payload")
        }

        var taskId = payload.taskId
        if taskId.hasPrefix("temp_") {
            if let real = await TaskService.shared.mappedRealTaskId(for: taskId) {
                taskId = real
            } else {
                return .retryable("updateTask: task not yet synced")
            }
        }

        do {
            _ = try await AstridAPIClient.shared.updateTask(id: taskId, updates: payload.updates)
            // Mark the row synced. Idempotent with the legacy path / safety-net
            // sync; required once legacy is removed.
            await TaskService.shared.reconcileOutboxUpdatedTask(taskId: taskId)
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}

// `UpdateTaskRequest` is `Codable`; its synthesized `Equatable` isn't available
// (custom encode), so give the payload value-equality via JSON for tests.
extension UpdateTaskRequest: Equatable {
    static func == (lhs: UpdateTaskRequest, rhs: UpdateTaskRequest) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }
}
