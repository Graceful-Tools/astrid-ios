import Foundation

/// Handler keys for Outbox entries.
enum OutboxKind {
    static let createTask = "createTask"
    static let uploadAttachment = "uploadAttachment"
    static let createComment = "createComment"
    static let sendChatMessage = "sendChatMessage"
    static let updateTask = "updateTask"
}

/// Feature flags for the Outbox rollout. Dual-write is now ON by default for the
/// production soak: the Outbox runs alongside the legacy per-service sync so we
/// can verify it catches every write before cutting over (per the task's
/// dual-write mitigation). Legacy remains the source of truth, and both paths use
/// the same `clientRequestId`, so the server dedupes — dual-write can't create
/// duplicates, and an Outbox bug can at worst dead-letter a shadow entry
/// (surfaced in the soak stats) without affecting the user.
enum OutboxConfig {
    private static let dualWriteKey = "outboxDualWriteEnabled"
    private static let sourceOfTruthKey = "outboxSourceOfTruth"

    static var dualWriteEnabled: Bool {
        // Default ON when the user hasn't explicitly set the toggle.
        get {
            if UserDefaults.standard.object(forKey: dualWriteKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: dualWriteKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dualWriteKey) }
    }

    /// Cutover flag (default OFF). When ON, the enqueued ops are AUTHORITATIVE:
    /// the calling service skips its legacy inline server call and the Outbox
    /// handler owns the full reconciliation (temp→real mapping, cache/CoreData
    /// swap, mark-synced). Rolled out op-by-op as a canary. While OFF we stay in
    /// dual-write soak mode (legacy authoritative, Outbox shadows).
    static var sourceOfTruthEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: sourceOfTruthKey) }
        set { UserDefaults.standard.set(newValue, forKey: sourceOfTruthKey) }
    }
}

/// App-facing entry point to the Outbox: owns the single `OutboxRunner`, wires
/// it to launch + network-restore drains, and exposes typed enqueue helpers.
@MainActor
final class OutboxManager {
    static let shared = OutboxManager()

    private let runner: OutboxRunner
    private var networkObserver: NSObjectProtocol?

    private init() {
        let runner = OutboxRunner(
            store: OutboxStore(fileURL: OutboxStore.defaultFileURL()),
            handlers: [
                OutboxKind.createTask: { entry, _ in await CreateTaskOutboxHandler.handle(entry) },
                OutboxKind.uploadAttachment: { entry, _ in await UploadAttachmentOutboxHandler.handle(entry) },
                OutboxKind.createComment: { entry, context in await CreateCommentOutboxHandler.handle(entry, context) },
                OutboxKind.sendChatMessage: { entry, _ in await SendChatMessageOutboxHandler.handle(entry) },
                OutboxKind.updateTask: { entry, _ in await UpdateTaskOutboxHandler.handle(entry) }
            ]
        )
        self.runner = runner

        // Drain whenever the network comes back. Capturing the actor (Sendable)
        // rather than self keeps this free of main-actor isolation hazards.
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable, object: nil, queue: .main
        ) { _ in
            _Concurrency.Task { await runner.drain() }
        }
    }

    /// Drain any journal persisted from a previous session. Safe to call when
    /// the journal is empty (the common case while dual-write is off).
    func start() {
        _Concurrency.Task { await runner.drain() }
    }

    /// Current journal stats for the debug soak readout.
    func stats() async -> OutboxStats {
        await runner.stats()
    }

    /// Enqueue a single dependency-free entry of `kind` carrying `payload`.
    /// No-op unless dual-write is enabled.
    private func enqueue<P: Encodable>(kind: String, payload: P, clientRequestId: String) {
        guard OutboxConfig.dualWriteEnabled || OutboxConfig.sourceOfTruthEnabled else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let now = Date()
        let entry = OutboxEntry(
            id: UUID().uuidString, kind: kind, payload: data,
            clientRequestId: clientRequestId, dependsOn: [], status: .pending,
            attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now
        )
        let runner = self.runner
        _Concurrency.Task { await runner.enqueue(entry) }
    }

    /// Enqueue a task creation. No-op unless dual-write is enabled.
    func enqueueCreateTask(_ payload: CreateTaskOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.createTask, payload: payload, clientRequestId: clientRequestId)
    }

    /// Enqueue a chat message send. No-op unless dual-write is enabled.
    func enqueueChatMessage(_ payload: SendChatMessageOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.sendChatMessage, payload: payload, clientRequestId: clientRequestId)
    }

    /// Enqueue a chat message, optionally with an attachment that must upload
    /// first — builds the dependency chain (upload → sendChatMessage) atomically so
    /// the message sends with the real fileId by construction. Mirrors
    /// `enqueueComment`. No-op unless dual-write or authoritative mode is on.
    func enqueueChatMessage(
        _ message: SendChatMessageOutboxPayload,
        clientRequestId: String,
        attachment: UploadAttachmentOutboxPayload?,
        attachmentClientRequestId: String?
    ) {
        guard OutboxConfig.dualWriteEnabled || OutboxConfig.sourceOfTruthEnabled else { return }
        let now = Date()
        var toEnqueue: [OutboxEntry] = []
        var dependsOn: [String] = []

        if let attachment,
           let attachmentClientRequestId,
           let attachmentData = try? JSONEncoder().encode(attachment) {
            let uploadId = UUID().uuidString
            toEnqueue.append(OutboxEntry(
                id: uploadId, kind: OutboxKind.uploadAttachment, payload: attachmentData,
                clientRequestId: attachmentClientRequestId, dependsOn: [], status: .pending,
                attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now, result: nil
            ))
            dependsOn.append(uploadId)
        }

        guard let messageData = try? JSONEncoder().encode(message) else { return }
        toEnqueue.append(OutboxEntry(
            id: UUID().uuidString, kind: OutboxKind.sendChatMessage, payload: messageData,
            clientRequestId: clientRequestId, dependsOn: dependsOn, status: .pending,
            attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now, result: nil
        ))

        let runner = self.runner
        let batch = toEnqueue
        _Concurrency.Task { await runner.enqueueBatch(batch) }
    }

    /// Enqueue a task update. No-op unless dual-write is enabled.
    func enqueueUpdateTask(_ payload: UpdateTaskOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.updateTask, payload: payload, clientRequestId: clientRequestId)
    }

    /// Enqueue a comment, optionally with an attachment that must upload first.
    /// Builds the dependency chain (upload → comment) so the comment is created
    /// with the real fileId by construction. No-op unless dual-write is enabled.
    func enqueueComment(
        _ comment: CreateCommentOutboxPayload,
        clientRequestId: String,
        attachment: UploadAttachmentOutboxPayload? = nil,
        attachmentClientRequestId: String? = nil
    ) {
        guard OutboxConfig.dualWriteEnabled || OutboxConfig.sourceOfTruthEnabled else { return }
        let now = Date()
        var toEnqueue: [OutboxEntry] = []
        var dependsOn: [String] = []

        if let attachment,
           let attachmentClientRequestId,
           let attachmentData = try? JSONEncoder().encode(attachment) {
            let uploadId = UUID().uuidString
            toEnqueue.append(OutboxEntry(
                id: uploadId, kind: OutboxKind.uploadAttachment, payload: attachmentData,
                clientRequestId: attachmentClientRequestId, dependsOn: [], status: .pending,
                attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now, result: nil
            ))
            dependsOn.append(uploadId)
        }

        guard let commentData = try? JSONEncoder().encode(comment) else { return }
        toEnqueue.append(OutboxEntry(
            id: UUID().uuidString, kind: OutboxKind.createComment, payload: commentData,
            clientRequestId: clientRequestId, dependsOn: dependsOn, status: .pending,
            attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now, result: nil
        ))

        // Enqueue the upload→comment chain atomically so an interruption can't
        // persist the upload but lose the comment.
        let runner = self.runner
        let batch = toEnqueue
        _Concurrency.Task { await runner.enqueueBatch(batch) }
    }
}
