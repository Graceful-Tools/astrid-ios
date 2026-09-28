import Foundation

/// Lifecycle state of an Outbox journal entry.
nonisolated enum OutboxStatus: String, Codable, Equatable, Sendable {
    case pending          // waiting to run (or to retry after backoff)
    case running          // a handler is currently executing it
    case completed        // succeeded; kept briefly so dependents can resolve
    case failedPermanent  // dead-lettered: auth/validation error or out of attempts
}

/// One entry of the Swift Outbox's journal (`outbox.json`), as a pre-core build left it.
///
/// Read once, by `CoreUpgrade`, which moves every still-queued write into astrid-core's journal;
/// nothing writes these now. Kept in the shape the old runner persisted so any file still on a
/// device decodes.
nonisolated struct OutboxEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String                 // UUID
    let kind: String               // handler key, e.g. "createComment"
    var payload: Data              // JSON, fully self-contained for the handler
    let clientRequestId: String    // idempotency key sent to the server
    var dependsOn: [String]        // ids of entries that must complete first
    var status: OutboxStatus
    var attempts: Int              // number of failed attempts so far
    var nextAttemptAt: Date        // earliest time this may run (backoff)
    var lastError: String?
    let createdAt: Date
    var updatedAt: Date
    /// Output produced on success, consumed by dependents (e.g. the real
    /// fileId from an attachment upload). nil until completed / when empty.
    var result: [String: String]?
    /// The optimistic TASK temp id this entry produces (createTask) or consumes
    /// (updateTask/deleteTask on a not-yet-synced task). Lets the scheduler
    /// dead-letter a consumer whose producing create has permanently failed,
    /// instead of leaving it .blocked forever. Optional so old journals decode.
    var tempId: String?
}
