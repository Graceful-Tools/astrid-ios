import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "ChatInput")

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
                onSend: { content, type, fileId in
                    sendChatMessage(content: content, type: type, fileId: fileId)
                }
            )
        }
    }

    private func sendChatMessage(content: String, type: Comment.CommentType, fileId: String?) {
        let currentUserId = AuthManager.shared.userId

        _Concurrency.Task {
            do {
                _ = try await ChatService.shared.sendMessage(
                    channelId: channelId,
                    content: content,
                    type: type,
                    fileId: fileId,
                    replyToId: replyingTo?.id,
                    authorId: currentUserId
                )
                await MainActor.run { onCancelReply?() }

                // Check if @Astrid was mentioned and we have on-device model selected
                await handleOnDeviceAstridMention(content: content)
            } catch {
                logger.error("Failed to send chat message: \(error.localizedDescription, privacy: .public)")
            }
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
