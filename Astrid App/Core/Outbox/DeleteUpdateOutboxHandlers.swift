import Foundation

// MARK: - Update comment

/// Self-contained payload for an `updateComment` Outbox entry.
nonisolated struct UpdateCommentOutboxPayload: Codable, Equatable {
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
            if let real = CommentService.shared.mappedRealCommentId(for: commentId) {
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
nonisolated struct DeleteCommentOutboxPayload: Codable, Equatable {
    var commentId: String
}

enum DeleteCommentOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(DeleteCommentOutboxPayload.self, from: entry.payload) else {
            return .permanent("deleteComment: undecodable payload")
        }
        var commentId = payload.commentId
        if commentId.hasPrefix("temp_") {
            if let real = CommentService.shared.mappedRealCommentId(for: commentId) {
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
