import Foundation

/// Self-contained payload for a `createTask` Outbox entry. Mirrors the
/// `AstridAPIClient.createTask` parameters (the idempotency key travels on the
/// entry, not here).
struct CreateTaskOutboxPayload: Codable, Equatable {
    var title: String
    var listIds: [String]?
    var description: String?
    var priority: Int?
    var assigneeId: String?
    var dueDateTime: Date?
    var isAllDay: Bool?
    var isPrivate: Bool?
    var repeating: String?
    var repeatingData: CustomRepeatingPattern?
}

/// Outbox handler for `createTask`. Performs the server create with the entry's
/// idempotency key, so a retry (or the legacy path during dual-write) is deduped
/// server-side. Translates failures via `OutboxResultMapper`.
enum CreateTaskOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(CreateTaskOutboxPayload.self, from: entry.payload) else {
            return .permanent("createTask: undecodable payload")
        }
        do {
            _ = try await AstridAPIClient.shared.createTask(
                title: payload.title,
                listIds: payload.listIds,
                description: payload.description,
                priority: payload.priority,
                assigneeId: payload.assigneeId,
                dueDateTime: payload.dueDateTime,
                isAllDay: payload.isAllDay,
                isPrivate: payload.isPrivate,
                repeating: payload.repeating,
                repeatingData: payload.repeatingData,
                clientRequestId: entry.clientRequestId
            )
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}
