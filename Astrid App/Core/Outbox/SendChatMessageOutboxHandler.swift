import Foundation

/// Self-contained payload for a `sendChatMessage` Outbox entry. `fileId` may be a
/// temp id resolved at run time from the (legacy) attachment upload.
struct SendChatMessageOutboxPayload: Codable, Equatable {
    var channelId: String
    var content: String
    var type: String
    var fileId: String?
    var replyToId: String?
}

/// Outbox handler for sending a chat message. Mirrors the comment handler:
/// resolves a temp attachment fileId against the legacy upload at run time
/// (does NOT re-upload), then sends with the entry's idempotency key so the
/// server dedupes (ChatMessage.clientRequestId is unique).
enum SendChatMessageOutboxHandler {
    static func handle(_ entry: OutboxEntry) async -> OutboxResult {
        guard let payload = try? JSONDecoder().decode(SendChatMessageOutboxPayload.self, from: entry.payload) else {
            return .permanent("sendChatMessage: undecodable payload")
        }

        var fileId = payload.fileId
        if let temp = fileId, temp.hasPrefix("temp_") {
            if let real = await AttachmentService.shared.getRealFileId(for: temp) {
                fileId = real
            } else if await AttachmentService.shared.isPendingUpload(temp) {
                return .blocked("sendChatMessage: attachment still uploading")
            } else {
                fileId = nil
            }
        }

        do {
            let serverMessage = try await AstridAPIClient.shared.sendChatMessage(
                channelId: payload.channelId,
                content: payload.content,
                type: Comment.CommentType(rawValue: payload.type) ?? .TEXT,
                fileId: fileId,
                replyToId: payload.replyToId,
                clientRequestId: entry.clientRequestId
            )
            // Reconcile the pending message (swap temp→real id, mark synced) by
            // clientRequestId. Idempotent with the legacy safety-net sync; required
            // once legacy is removed.
            await ChatService.shared.reconcileOutboxSentMessage(
                clientRequestId: entry.clientRequestId,
                serverMessage: serverMessage,
                channelId: payload.channelId
            )
            return .success([:])
        } catch {
            return OutboxResultMapper.classify(error)
        }
    }
}
