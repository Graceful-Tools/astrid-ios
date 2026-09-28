import AstridCore
import Combine
import Foundation

/// A list's chat — through astrid-core.
///
/// The core holds the channels and each channel's messages in its cache, journals every send (a
/// picture's upload first, the message waiting for it), and keeps the transcript current from the
/// live stream (docs/CORE_MIGRATION.md). This service keeps the per-channel buckets the chat
/// panels bind to and reads them back when the core says a channel moved.
@MainActor
class ChatService: ObservableObject {
    static let shared = ChatService()

    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Chat sends waiting to reach the server.
    @Published var pendingOperationsCount: Int = 0
    /// channelId → its messages, oldest first.
    @Published var cachedMessages: [String: [ChatMessage]] = [:]
    /// listId (or virtual key) → channelId.
    @Published var channelForList: [String: String] = [:]
    /// channelId → whether there is older history on the server.
    @Published var hasMore: [String: Bool] = [:]
    /// channelId → the agent writing a reply there right now.
    @Published var typingAgent: [String: String] = [:]

    private var core: CoreSession { AppCore.shared.session }
    /// When each channel was last asked of the server, so reopening a panel does not fetch twice.
    private var lastFetchTime: [String: Date] = [:]

    init() {}

    // MARK: - Channels

    /// The chat channel for a list — the cache's, else the server's, which creates it on first use.
    func resolveChannel(forListId listId: String) async throws -> String {
        try await resolve(key: listId, CoreCommand(kind: "resolveChatChannel", ["listId": .value(listId)]))
    }

    /// The chat channel of a virtual list, such as My Tasks.
    func resolveVirtualChannel(virtualKey: String) async throws -> String {
        try await resolve(key: virtualKey,
                          CoreCommand(kind: "resolveChatChannel", ["virtualKey": .value(virtualKey)]))
    }

    private func resolve(key: String, _ command: CoreCommand) async throws -> String {
        if let channelId = channelForList[key] { return channelId }
        let channel = try await core.run(command, as: ChatChannel.self)
        channelForList[key] = channel.id
        return channel.id
    }

    // MARK: - Reading

    /// A channel's messages: the cache at once, then the server's newest page — refreshed in the
    /// background when the cache has some, awaited when it has none.
    func fetchMessages(channelId: String, useCache: Bool = true) async throws -> [ChatMessage] {
        let cached = await read(channelId: channelId)
        if useCache, !cached.isEmpty {
            backgroundRefresh(channelId: channelId)
            return cached
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            return try await refreshMessagesFromServer(channelId: channelId)
        } catch {
            // Offline: the cache is the answer.
            errorMessage = error.localizedDescription
            return cached
        }
    }

    /// Fetch the newest page now and answer with the channel as the cache then holds it — the
    /// fallback poll and explicit refreshes.
    @discardableResult
    func refreshMessagesFromServer(channelId: String) async throws -> [ChatMessage] {
        lastFetchTime[channelId] = Date()
        let page = try await core.run(
            CoreCommand(kind: "loadChatMessages", ["channelId": .value(channelId)]), as: Page.self)
        hasMore[channelId] = page.hasMore
        publish(page.messages, in: channelId)
        return page.messages
    }

    /// The page before the oldest message this device holds.
    func loadMoreMessages(channelId: String) async throws {
        guard hasMore[channelId] == true,
              let oldest = cachedMessages[channelId]?.first(where: { !$0.isPending })?.createdAt
        else { return }
        let page = try await core.run(
            CoreCommand(kind: "loadChatMessages", [
                "channelId": .value(channelId),
                "before": .value(WireDate.string(from: oldest)),
            ]),
            as: Page.self)
        hasMore[channelId] = page.hasMore
        publish(page.messages, in: channelId)
    }

    private struct Page: Decodable {
        let messages: [ChatMessage]
        let hasMore: Bool
    }

    /// What the core holds for `channelId`, published into its bucket.
    @discardableResult
    private func read(channelId: String) async -> [ChatMessage] {
        guard let messages = try? await core.run(
            CoreCommand(kind: "chatMessages", ["channelId": .value(channelId)]), as: [ChatMessage].self)
        else { return cachedMessages[channelId] ?? [] }
        publish(messages, in: channelId)
        return messages
    }

    private func publish(_ messages: [ChatMessage], in channelId: String) {
        guard cachedMessages[channelId] != messages else { return }
        cachedMessages[channelId] = messages
        // A reply from an agent is the end of its typing, whatever the stream said.
        if messages.last?.isFromAgent == true { typingAgent[channelId] = nil }
        NotificationCenter.default.post(name: .chatMessageDidSync, object: nil, userInfo: ["channelId": channelId])
    }

    /// Ask the server again, at most every 30 seconds per channel.
    private func backgroundRefresh(channelId: String) {
        if let last = lastFetchTime[channelId], Date().timeIntervalSince(last) < 30 { return }
        lastFetchTime[channelId] = Date()
        _Concurrency.Task { try? await self.refreshMessagesFromServer(channelId: channelId) }
    }

    /// The core says a channel moved — the live stream, a delivery, a pass: read back the ones a
    /// panel is showing.
    func coreDidChange(_ change: CoreChange) {
        switch change {
        case .chat(let channelId) where cachedMessages[channelId] != nil:
            _Concurrency.Task { await self.read(channelId: channelId) }
        case .agentTyping(let channelId?, _, let agentName, let active):
            typingAgent[channelId] = active ? (agentName ?? "Agent") : nil
        case .synced, .unknown:
            for channelId in cachedMessages.keys {
                _Concurrency.Task { await self.read(channelId: channelId) }
            }
            refreshOutboxCounts()
        default:
            break
        }
    }

    // MARK: - Writing

    /// Send a message — at once in the transcript, to the server when it can.
    ///
    /// - Parameter fileId: a file to carry. A temporary one is a file the person just picked,
    ///   staged by `AttachmentService`: the core copies it, uploads it, and sends the message once
    ///   the upload answers, all through its journal.
    func sendMessage(
        channelId: String,
        content: String,
        type: Comment.CommentType = .TEXT,
        fileId: String? = nil,
        replyToId: String? = nil,
        authorId: String? = nil
    ) async throws -> ChatMessage {
        var command = CoreCommand(kind: "sendChatMessage", [
            "channelId": .value(channelId), "content": .value(content), "type": .value(type.rawValue),
        ])
        command.set("replyToId", replyToId)
        command.set("fileId", fileId)
        if let fileId, fileId.hasPrefix("temp_"),
           let staged = AttachmentService.shared.pendingUploads[fileId] {
            command.set("path", staged.localPath)
            command.set("name", staged.fileName)
            command.set("mimeType", staged.mimeType)
        }
        let message = try await core.run(command, as: ChatMessage.self)
        var bucket = cachedMessages[channelId] ?? []
        bucket.removeAll { $0.id == message.id }
        bucket.append(message)
        cachedMessages[channelId] = bucket
        refreshOutboxCounts()
        return message
    }

    /// Take a message out of this device's transcript. Chat has no delete on the server; a
    /// message not yet sent is not sent.
    func deleteMessage(id: String, channelId: String) async throws {
        cachedMessages[channelId]?.removeAll { $0.id == id }
        try await core.run(CoreCommand(kind: "forgetChatMessage", ["messageId": .value(id)]))
        refreshOutboxCounts()
    }

    /// Send what is waiting now rather than at the delivery loop's next turn.
    func syncPendingMessages() async throws {
        try await core.run(CoreCommand(kind: "drain"))
        refreshOutboxCounts()
    }

    private func refreshOutboxCounts() {
        struct Stats: Decodable { let pending: Int; let running: Int }
        _Concurrency.Task {
            guard let stats = try? await core.run(CoreCommand(kind: "outboxStats"), as: Stats.self) else { return }
            pendingOperationsCount = stats.pending + stats.running
        }
    }

    /// Clear what the panels read (sign-out; the core wipes its own cache there too).
    func clearCache() {
        cachedMessages = [:]
        channelForList = [:]
        hasMore = [:]
        typingAgent = [:]
        lastFetchTime = [:]
    }

    // MARK: - Agents

    /// Fetch available agents through ChatService so views do not couple directly to the API
    /// client. The raw agent models are useful in settings screens, while chat input can map them
    /// to mentionable users.
    func fetchAvailableAgents(useCacheOnFailure: Bool = true) async throws -> [AvailableAgent] {
        do {
            let agents = try await AstridAPIClient.shared.getAvailableAgents()
            AIAgentCache.shared.save(agents.map(Self.agentUser))
            return agents
        } catch {
            if useCacheOnFailure, let cachedUsers = AIAgentCache.shared.load() {
                return cachedUsers.map {
                    AvailableAgent(id: $0.id, name: $0.displayName, email: $0.email ?? "",
                                   image: $0.image, service: $0.aiAgentType ?? "")
                }
            }
            throw error
        }
    }

    /// The models that can power the default assistant: only what the server can run itself
    /// (`?serverRun=true`). NOT cached — the mention cache must keep the unfiltered list, which
    /// includes polling agents that cannot power the assistant but can be assigned (AITD-297).
    func fetchServerRunAgents() async throws -> [AvailableAgent] {
        try await AstridAPIClient.shared.getAvailableAgents(serverRunOnly: true)
    }

    func fetchAvailableAgentUsers(useCacheOnFailure: Bool = true) async throws -> [User] {
        try await fetchAvailableAgents(useCacheOnFailure: useCacheOnFailure).map(Self.agentUser)
    }

    private static func agentUser(_ agent: AvailableAgent) -> User {
        User(id: agent.id, email: agent.email, name: agent.name, image: agent.image, createdAt: nil,
             defaultDueTime: nil, isPending: nil, isAIAgent: true, aiAgentType: agent.service)
    }

    // MARK: - AI Assistant (on-device / agent response)
    //
    // `getAIAssistantSettings` is called on every @Astrid send, so it is cached briefly to avoid a
    // round-trip per message.

    private var cachedAIAssistantSettings: (value: AIAssistantSettings, fetchedAt: Date)?
    private let aiAssistantSettingsTTL: TimeInterval = 60

    /// The user's AI assistant settings, from a short in-memory cache so the on-device-model gate
    /// does not re-fetch on every keystroke.
    func getAIAssistantSettings() async throws -> AIAssistantSettings {
        if let cached = cachedAIAssistantSettings,
           Date().timeIntervalSince(cached.fetchedAt) < aiAssistantSettingsTTL {
            return cached.value
        }
        let settings = try await AstridAPIClient.shared.getAIAssistantSettings()
        cachedAIAssistantSettings = (settings, Date())
        return settings
    }

    /// Invalidate the AI-assistant-settings cache (e.g., after the user changes the model).
    func invalidateAIAssistantSettingsCache() {
        cachedAIAssistantSettings = nil
    }

    /// Update the user's AI-assistant settings, then refresh the short-lived cache.
    @discardableResult
    func updateAIAssistantSettings(
        defaultAgentId: String? = nil,
        preferredService: String? = nil
    ) async throws -> AIAssistantSettings {
        let settings = try await AstridAPIClient.shared.updateAIAssistantSettings(
            defaultAgentId: defaultAgentId, preferredService: preferredService)
        cachedAIAssistantSettings = (settings, Date())
        return settings
    }

    /// Post an on-device AI agent's response to a chat channel.
    func postAgentResponse(channelId: String, content: String) async throws {
        try await core.run(CoreCommand(kind: "postAgentResponse", [
            "channelId": .value(channelId), "content": .value(content),
        ]))
    }

    /// Ask the server to answer as Astrid when this device cannot (task 9dce4c73).
    func requestServerAstridResponse(channelId: String, messageId: String?, content: String) async throws {
        var command = CoreCommand(kind: "requestAstridResponse", [
            "channelId": .value(channelId), "content": .value(content),
        ])
        command.set("messageId", messageId)
        try await core.run(command)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let chatMessageDidSync = Notification.Name("chatMessageDidSync")
}
