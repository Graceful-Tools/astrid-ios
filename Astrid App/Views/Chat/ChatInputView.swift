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

    /// If the message mentions @Astrid and the user has Apple FM selected,
    /// process the message on-device and post the response via the server.
    private func handleOnDeviceAstridMention(content: String) async {
        // Check if on-device model is selected. Routed through ChatService
        // so the call goes through the same control point as message sends
        // and benefits from the short TTL cache (called on every @mention).
        guard let settings = try? await ChatService.shared.getAIAssistantSettings(),
              settings.isOnDeviceModel else { return }

        // Check if message contains an @Astrid mention (format: @[Astrid](userId))
        // Also trigger for any message in a personal channel (listId is nil or "my-tasks")
        let hasAstridMention = content.contains("@[Astrid]") || content.contains("@[astrid]")
        let isPersonalChannel = listId == nil || listId == "my-tasks"
        guard hasAstridMention || isPersonalChannel else { return }

        guard AppleFoundationModelService.shared.isAvailable else {
            logger.warning("On-device model not available on this device")
            return
        }

        logger.notice("Processing @Astrid mention on-device")

        // Strip the mention markup to get the plain message
        let plainMessage = content
            .replacingOccurrences(of: "@\\[[^\\]]+\\]\\([^)]+\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !plainMessage.isEmpty else { return }

        // Process on-device
        guard let response = await AppleFoundationModelService.shared.processChatMessage(plainMessage) else {
            logger.error("On-device processing returned no response")
            return
        }

        // Post the response as Astrid via ChatService (canonical entry point
        // for everything that writes to a chat channel).
        do {
            try await ChatService.shared.postAgentResponse(
                channelId: channelId,
                content: response
            )
            logger.notice("On-device response posted to channel")
        } catch {
            logger.error("Failed to post on-device response: \(error.localizedDescription, privacy: .public)")
        }
    }
}
