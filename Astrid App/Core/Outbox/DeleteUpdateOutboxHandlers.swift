import Foundation

// MARK: - Delete task

/// Self-contained payload for a `deleteTask` Outbox entry.
struct DeleteTaskOutboxPayload: Codable, Equatable {
    var taskId: String
}

/// Deletes the task server-side. 404/410 count as success (already gone —
/// deletes are naturally idempotent). A temp id waits (.blocked) until the
/// offline create resolves it.
enum DeleteTaskOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(DeleteTaskOutboxPayload.self, from: entry.payload) else {
            return .permanent("deleteTask: undecodable payload")
        }
        var taskId = payload.taskId
        if taskId.hasPrefix("temp_") {
            if let real = await TaskService.shared.mappedRealTaskId(for: taskId) {
                taskId = real
            } else {
                return .blocked("deleteTask: task not yet synced")
            }
        }
        do {
            try await AstridAPIClient.shared.deleteTask(id: taskId)
        } catch let apiError as AstridAPIError {
            if case .httpError(let status, _) = apiError, status == 404 || status == 410 {
                // Already deleted server-side — success.
            } else {
                return OutboxResultMapper.classify(apiError)
            }
        } catch {
            return OutboxResultMapper.classify(error)
        }
        await TaskService.shared.finalizeOutboxDeletedTask(id: payload.taskId, resolvedId: taskId)
        return .success([:])
    }
}

// MARK: - Update comment

/// Self-contained payload for an `updateComment` Outbox entry.
struct UpdateCommentOutboxPayload: Codable, Equatable {
    var commentId: String
    var content: String
}

enum UpdateCommentOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(UpdateCommentOutboxPayload.self, from: entry.payload) else {
            return .permanent("updateComment: undecodable payload")
        }
        var commentId = payload.commentId
        if commentId.hasPrefix("temp_") {
            if let real = await CommentService.shared.mappedRealCommentId(for: commentId) {
                commentId = real
            } else {
                return .blocked("updateComment: comment not yet synced")
            }
        }
        do {
            _ = try await AstridAPIClient.shared.updateComment(commentId: commentId, content: payload.content)
            await CommentService.shared.reconcileOutboxUpdatedComment(commentId: commentId, content: payload.content)
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}

// MARK: - Delete comment

/// Self-contained payload for a `deleteComment` Outbox entry.
struct DeleteCommentOutboxPayload: Codable, Equatable {
    var commentId: String
}

enum DeleteCommentOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(DeleteCommentOutboxPayload.self, from: entry.payload) else {
            return .permanent("deleteComment: undecodable payload")
        }
        var commentId = payload.commentId
        if commentId.hasPrefix("temp_") {
            if let real = await CommentService.shared.mappedRealCommentId(for: commentId) {
                commentId = real
            } else {
                return .blocked("deleteComment: comment not yet synced")
            }
        }
        do {
            _ = try await AstridAPIClient.shared.deleteComment(commentId: commentId)
        } catch let apiError as AstridAPIError {
            if case .httpError(let status, _) = apiError, status == 404 || status == 410 {
                // Already deleted — success.
            } else {
                return OutboxResultMapper.classify(apiError)
            }
        } catch {
            return OutboxResultMapper.classify(error)
        }
        await CommentService.shared.finalizeOutboxDeletedComment(commentId: payload.commentId, resolvedId: commentId)
        return .success([:])
    }
}
