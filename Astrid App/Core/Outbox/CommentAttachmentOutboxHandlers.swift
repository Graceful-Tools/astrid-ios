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
            let fileId = try await AttachmentService.shared.uploadToSecureEndpoint(
                fileData: data,
                fileName: payload.fileName,
                mimeType: payload.mimeType,
                context: payload.context
            )
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

    static func resolve(payloadTaskId: String, context: OutboxContext) -> Resolved {
        Resolved(
            taskId: context.value("taskId") ?? payloadTaskId,
            fileId: context.value("fileId")
        )
    }
}

enum CreateCommentOutboxHandler {
    static func handle(_ entry: OutboxEntry, _ context: OutboxContext) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(CreateCommentOutboxPayload.self, from: entry.payload) else {
            return .permanent("createComment: undecodable payload")
        }
        let resolved = CommentOutboxResolver.resolve(payloadTaskId: payload.taskId, context: context)
        if resolved.taskUnresolved {
            // Parent task (created offline) hasn't produced a real id yet.
            return .retryable("createComment: task not yet synced")
        }
        do {
            _ = try await AstridAPIClient.shared.createComment(
                taskId: resolved.taskId,
                content: payload.content,
                type: Comment.CommentType(rawValue: payload.type) ?? .TEXT,
                fileId: resolved.fileId,
                parentCommentId: payload.parentCommentId,
                createdAt: payload.createdAt,
                clientRequestId: entry.clientRequestId
            )
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}
