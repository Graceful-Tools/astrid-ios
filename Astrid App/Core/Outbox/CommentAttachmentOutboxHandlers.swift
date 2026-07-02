import Foundation

// MARK: - Upload attachment

/// Self-contained payload for an `uploadAttachment` Outbox entry. The bytes stay
/// on disk at `localPath` (the journal references them, never embeds them).
struct UploadAttachmentOutboxPayload: Codable, Equatable {
    var localPath: String
    var fileName: String
    var mimeType: String
    var context: [String: String]   // e.g. {"taskId": "..."} or {"channelId": "..."}
}

/// Uploads the file and yields the real `fileId` as its output, which the
/// dependent comment reads via `OutboxContext`.
enum UploadAttachmentOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(UploadAttachmentOutboxPayload.self, from: entry.payload) else {
            return .permanent("uploadAttachment: undecodable payload")
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: payload.localPath)) else {
            // The local file is gone — nothing to upload, and a retry won't help.
            return .permanent("uploadAttachment: local file missing at \(payload.localPath)")
        }
        do {
            // Pass the idempotency key in the upload context so a retry returns
            // the same file instead of creating a duplicate (web dedups on it).
            var context = payload.context
            context["clientRequestId"] = entry.clientRequestId
            let fileId = try await AttachmentService.shared.uploadToSecureEndpoint(
                fileData: data,
                fileName: payload.fileName,
                mimeType: payload.mimeType,
                context: context
            )
            // Record temp→real so thumbnail display (getRealFileId) resolves. The
            // temp id is the local file's name (cacheDirectory/<tempFileId>).
            let tempFileId = URL(fileURLWithPath: payload.localPath).lastPathComponent
            await AttachmentService.shared.recordOutboxUpload(tempFileId: tempFileId, realFileId: fileId)
            return .success(["fileId": fileId])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}

// MARK: - Create comment

/// Self-contained payload for a `createComment` Outbox entry. `taskId` may be a
/// temporary id; a task-create dependency's output overrides it. The attachment
/// fileId is NOT stored here — it's read from the upload dependency's output.
struct CreateCommentOutboxPayload: Codable, Equatable {
    var taskId: String
    var content: String
    var type: String
    var parentCommentId: String?
    var createdAt: Date?
    /// Attachment file id at enqueue time — may be a temp id resolved at run time
    /// from the (legacy) upload, or nil for a plain comment.
    var fileId: String?
}

/// Pure resolution of a comment's effective ids from its payload + dependency
/// outputs. A task-create dependency's real id wins over a temp payload id; the
/// fileId comes from an attachment-upload dependency.
enum CommentOutboxResolver {
    struct Resolved: Equatable {
        let taskId: String
        let fileId: String?
        /// True when the task id is still temporary and no dependency supplied a
        /// real one — the comment must wait rather than POST to a temp id.
        var taskUnresolved: Bool { taskId.hasPrefix("temp_") }
    }

    static func resolve(payloadTaskId: String, payloadFileId: String?, context: OutboxContext) -> Resolved {
        Resolved(
            taskId: context.value("taskId") ?? payloadTaskId,
            fileId: context.value("fileId") ?? payloadFileId
        )
    }
}

enum CreateCommentOutboxHandler {
    static func handle(_ entry: OutboxEntry, _ context: OutboxContext) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(CreateCommentOutboxPayload.self, from: entry.payload) else {
            return .permanent("createComment: undecodable payload")
        }
        let resolved = CommentOutboxResolver.resolve(
            payloadTaskId: payload.taskId, payloadFileId: payload.fileId, context: context)

        // Resolve a temp task id (offline-created task) against the live temp→real
        // map; if it isn't synced yet, wait rather than POST to a temp id.
        var taskId = resolved.taskId
        if taskId.hasPrefix("temp_") {
            if let real = await TaskService.shared.mappedRealTaskId(for: taskId) {
                taskId = real
            } else {
                return .retryable("createComment: task not yet synced")
            }
        }

        // Resolve a temp attachment file id against the (legacy) upload result.
        var fileId = resolved.fileId
        if let temp = fileId, temp.hasPrefix("temp_") {
            if let real = await AttachmentService.shared.getRealFileId(for: temp) {
                fileId = real
            } else if await AttachmentService.shared.isPendingUpload(temp) {
                return .retryable("createComment: attachment still uploading")
            } else {
                fileId = nil  // upload gone — post the comment without it (matches legacy)
            }
        }

        do {
            let response = try await AstridAPIClient.shared.createComment(
                taskId: taskId,
                content: payload.content,
                type: Comment.CommentType(rawValue: payload.type) ?? .TEXT,
                fileId: fileId,
                parentCommentId: payload.parentCommentId,
                createdAt: payload.createdAt,
                clientRequestId: entry.clientRequestId
            )
            // Reconcile the pending comment (swap temp→real id, migrate task id,
            // mark synced). Idempotent with the legacy safety-net sync; required
            // once legacy is removed. entry.clientRequestId is the temp comment id.
            await CommentService.shared.reconcileOutboxCreatedComment(
                tempCommentId: entry.clientRequestId,
                tempTaskId: payload.taskId,
                serverComment: response.comment,
                resolvedTaskId: taskId
            )
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}
