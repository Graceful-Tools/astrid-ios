import Foundation

/// Lifecycle state of an Outbox journal entry.
enum OutboxStatus: String, Codable, Equatable, Sendable {
    case pending          // waiting to run (or to retry after backoff)
    case running          // a handler is currently executing it
    case completed        // succeeded; kept briefly so dependents can resolve
    case failedPermanent  // dead-lettered: auth/validation error or out of attempts
}

/// A single self-contained unit of offline-first work in the Outbox journal.
///
/// The Outbox replaces the per-service pending queues (TaskService /
/// CommentService / ChatService / AttachmentService) with one journal + one
/// runner. Each entry carries everything needed to perform the write, an
/// idempotency key so retries never duplicate server-side, and explicit
/// `dependsOn` edges so e.g. a comment waits for its attachment upload by
/// construction (instead of the old throw/observe/retry dance).
struct OutboxEntry: Identifiable, Codable, Equatable, Sendable {
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
