import Foundation

/// Handler keys for Outbox entries.
enum OutboxKind {
    static let createTask = "createTask"
    static let uploadAttachment = "uploadAttachment"
    static let createComment = "createComment"
    static let sendChatMessage = "sendChatMessage"
    static let updateTask = "updateTask"
}

/// Feature flags for the Outbox rollout. Dual-write is OFF by default: the
/// Outbox runs alongside the legacy per-service sync only when explicitly
/// enabled, so we can verify it in production before cutting over (per the
/// task's dual-write mitigation). Both paths use the same `clientRequestId`, so
/// the server dedupes — enabling dual-write can't create duplicates.
enum OutboxConfig {
    private static let dualWriteKey = "outboxDualWriteEnabled"

    static var dualWriteEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: dualWriteKey) }
        set { UserDefaults.standard.set(newValue, forKey: dualWriteKey) }
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
        guard OutboxConfig.dualWriteEnabled else { return }
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
        guard OutboxConfig.dualWriteEnabled else { return }
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

        let runner = self.runner
        _Concurrency.Task {
            for entry in toEnqueue { await runner.enqueue(entry) }
        }
    }
}
