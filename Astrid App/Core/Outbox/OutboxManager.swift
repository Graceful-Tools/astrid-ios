import Foundation

/// Handler keys for Outbox entries.
enum OutboxKind {
    static let createTask = "createTask"
    static let uploadAttachment = "uploadAttachment"
    static let createComment = "createComment"
    static let sendChatMessage = "sendChatMessage"
    static let updateTask = "updateTask"
    static let deleteTask = "deleteTask"
    static let updateComment = "updateComment"
    static let deleteComment = "deleteComment"
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
                OutboxKind.updateTask: { entry, _ in await UpdateTaskOutboxHandler.handle(entry) },
                OutboxKind.deleteTask: { entry, _ in await DeleteTaskOutboxHandler.handle(entry) },
                OutboxKind.updateComment: { entry, _ in await UpdateCommentOutboxHandler.handle(entry) },
                OutboxKind.deleteComment: { entry, _ in await DeleteCommentOutboxHandler.handle(entry) }
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
    /// the journal is empty.
    func start() {
        _Concurrency.Task { await runner.drain() }
    }

    /// Current journal stats for the debug soak readout.
    func stats() async -> OutboxStats {
        await runner.stats()
    }

    /// Full journal snapshot — Settings → Outbox debugging and tests.
    func journalSnapshot() async -> [OutboxEntry] {
        await runner.snapshot()
    }

    /// User-initiated recovery of dead-lettered writes (Settings → Outbox).
    @discardableResult
    func retryDeadLetters() async -> Int {
        await runner.retryDeadLetters()
    }

    /// Drain the journal now (manual "sync now" / pull-to-refresh entry point).
    func drain() async {
        await runner.drain()
    }

    /// Sign-out: wipe the journal (queued writes belong to the departing user).
    func clearAllForSignOut() async {
        await runner.clearAll()
    }

    /// Local mutations nudge the external sync providers (debounced there) so
    /// edits push without waiting for foreground/pull-to-refresh.
    static let didEnqueueMutation = Notification.Name("outboxDidEnqueueMutation")

    private func noteMutation() {
        NotificationCenter.default.post(name: Self.didEnqueueMutation, object: nil)
    }

    /// Enqueue a single dependency-free entry of `kind` carrying `payload`.
    /// `tempId` links a task temp-id producer (createTask) or consumer
    /// (updateTask/deleteTask on a temp task) so the scheduler can dead-letter
    /// a consumer whose create permanently failed.
    private func enqueue<P: Encodable>(kind: String, payload: P, clientRequestId: String, tempId: String? = nil) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let now = Date()
        let entry = OutboxEntry(
            id: UUID().uuidString, kind: kind, payload: data,
            clientRequestId: clientRequestId, dependsOn: [], status: .pending,
            attempts: 0, nextAttemptAt: now, lastError: nil, createdAt: now, updatedAt: now,
            tempId: tempId
        )
        let runner = self.runner
        _Concurrency.Task { await runner.enqueue(entry) }
        noteMutation()
    }

    /// Enqueue a task creation.
    func enqueueCreateTask(_ payload: CreateTaskOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.createTask, payload: payload, clientRequestId: clientRequestId,
                tempId: payload.tempId)
    }

    /// Enqueue a chat message send.
    func enqueueChatMessage(_ payload: SendChatMessageOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.sendChatMessage, payload: payload, clientRequestId: clientRequestId)
    }

    /// Enqueue a chat message, optionally with an attachment that must upload
    /// first — builds the dependency chain (upload → sendChatMessage) atomically so
    /// the message sends with the real fileId by construction. Mirrors
    /// `enqueueComment`.
    func enqueueChatMessage(
        _ message: SendChatMessageOutboxPayload,
        clientRequestId: String,
        attachment: UploadAttachmentOutboxPayload?,
        attachmentClientRequestId: String?
    ) {
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
        noteMutation()
    }

    /// Enqueue a task update.
    func enqueueUpdateTask(_ payload: UpdateTaskOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.updateTask, payload: payload, clientRequestId: clientRequestId,
                tempId: payload.taskId.hasPrefix("temp_") ? payload.taskId : nil)
    }

    func enqueueDeleteTask(_ payload: DeleteTaskOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.deleteTask, payload: payload, clientRequestId: clientRequestId,
                tempId: payload.taskId.hasPrefix("temp_") ? payload.taskId : nil)
    }

    func enqueueUpdateComment(_ payload: UpdateCommentOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.updateComment, payload: payload, clientRequestId: clientRequestId)
    }

    func enqueueDeleteComment(_ payload: DeleteCommentOutboxPayload, clientRequestId: String) {
        enqueue(kind: OutboxKind.deleteComment, payload: payload, clientRequestId: clientRequestId)
    }

    /// Enqueue a comment, optionally with an attachment that must upload first.
    /// Builds the dependency chain (upload → comment) so the comment is created
    /// with the real fileId by construction.
    func enqueueComment(
        _ comment: CreateCommentOutboxPayload,
        clientRequestId: String,
        attachment: UploadAttachmentOutboxPayload? = nil,
        attachmentClientRequestId: String? = nil
    ) {
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
        noteMutation()
    }
}
