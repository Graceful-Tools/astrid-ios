import SwiftUI
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "ChatInput")

/// Chat message input — wraps RichTextInput with chat-specific send logic
struct ChatInputView: View {
    @Environment(\.colorScheme) var colorScheme

    let channelId: String
    let listId: String?
    var availableAgents: [User] = []
    var replyingTo: ChatMessage?
    var onCancelReply: (() -> Void)?

    private var uploadContext: [String: String] {
        if let listId = listId, listId != "my-tasks" {
            return ["listId": listId]
        }
        return ["channelId": channelId]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Reply-to banner
            if let replyingTo = replyingTo {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.accent)
                    Text("Replying to \(replyingTo.author?.displayName ?? "Unknown")")
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    Spacer()
                    Button { onCancelReply?() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.spacing20)
                .padding(.bottom, Theme.spacing4)
            }

            // Shared rich text input with autocomplete + attachments + colored references
            RichTextInput(
                placeholder: NSLocalizedString("chat.message_placeholder", comment: "Message..."),
                listId: listId,
                availableAgents: availableAgents,
                uploadContext: uploadContext,
                onSend: { content, type, fileIds in
                    sendChatMessage(content: content, type: type, fileIds: fileIds)
                }
            )
        }
    }

    private func sendChatMessage(content: String, type: Comment.CommentType, fileIds: [String]) {
        let currentUserId = AuthManager.shared.userId

        // A chat message carries one file, so several attachments become several messages —
        // the same rule comments use, via the same tested split. Text rides the first.
        let drafts = CommentAttachmentBatch.drafts(text: content,
                                                   fileIds: fileIds,
                                                   useMarkdown: type != .TEXT)
        guard !drafts.isEmpty else { return }

        _Concurrency.Task {
            // Sent one at a time so they land in the order they were picked. Each is caught
            // on its own: one failure must not abandon the attachments behind it.
            for draft in drafts {
                do {
                    _ = try await ChatService.shared.sendMessage(
                        channelId: channelId,
                        content: draft.content,
                        type: draft.type,
                        fileId: draft.fileId,
                        replyToId: replyingTo?.id,
                        authorId: currentUserId
                    )
                } catch {
                    logger.error("Failed to send chat message: \(error.localizedDescription, privacy: .public)")
                }
            }
            await MainActor.run { onCancelReply?() }

            // Check if @Astrid was mentioned and we have on-device model selected
            await handleOnDeviceAstridMention(content: content)
        }
    }

    /// If the message is addressed to Astrid and the user has Apple FM selected, answer on device.
    ///
    /// The rule and the mention-stripping now live in the SHARED `OnDeviceAstrid` — they used to
    /// be inline here, which is why the Mac chat never answered at all (task 8dded037). Keeping
    /// one copy is what stops the two platforms drifting apart.
    private func handleOnDeviceAstridMention(content: String) async {
        await OnDeviceAstrid.respondIfNeeded(channelId: channelId, content: content, listId: listId)
    }
}
