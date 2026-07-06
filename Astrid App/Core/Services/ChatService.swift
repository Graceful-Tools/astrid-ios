import Foundation
import Combine
import CoreData
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "ChatService")

/// Errors that can occur during chat message sync
enum ChatSyncError: Error {
    case attachmentPending  // Attachment upload not complete yet - will retry later
    case channelNotFound    // Channel hasn't been resolved yet
}

@MainActor
class ChatService: ObservableObject {
    static let shared = ChatService()

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var cachedMessages: [String: [ChatMessage]] = [:]  // channelId -> messages
    @Published var channelForList: [String: String] = [:]         // listId -> channelId
    @Published var hasMore: [String: Bool] = [:]                  // channelId -> hasMore pages

    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var lastFetchTime: [String: Date] = [:]  // channelId -> last fetch time
    private var inFlightFetches: [String: _Concurrency.Task<[ChatMessage], Error>] = [:]
    private var networkObserver: NSObjectProtocol?

    init() {
        _Concurrency.Task { @MainActor in
            await self.loadCachedMessages()
            await self.loadCachedChannels()
            await self.updatePendingOperationsCount()
        }
        setupNetworkObserver()
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                try? await self?.syncPendingMessages()
            }
        }

        // Re-sync when an attachment upload completes (resolves pending messages waiting for fileId)
        NotificationCenter.default.addObserver(
            forName: .attachmentUploadCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                try? await self?.syncPendingMessages()
            }
        }
    }

    // MARK: - Channel Resolution

    /// Resolve the chat channel for a list (cached → API fallback)
    func resolveChannel(forListId listId: String) async throws -> String {
        // Check memory cache
        if let channelId = channelForList[listId] {
            return channelId
        }

        // Check CoreData cache
        await coreDataManager.waitForStoreLoad()
        let cachedChannel: ChatChannel? = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let cdChannel = try CDChatChannel.fetchByListId(listId, context: context)
                    continuation.resume(returning: cdChannel?.toDomainModel())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if let channel = cachedChannel {
            channelForList[listId] = channel.id
            return channel.id
        }

        // Fetch from API
        let channel = try await apiClient.getOrCreateChatChannel(listId: listId)

        // Cache in CoreData
        try await coreDataManager.saveInBackground { context in
            let cdChannel = try CDChatChannel.fetchById(channel.id, context: context) ?? CDChatChannel(context: context)
            cdChannel.id = channel.id
            cdChannel.update(from: channel)
        }

        channelForList[listId] = channel.id
        return channel.id
    }

    /// Resolve a virtual chat channel (e.g. for My Tasks)
    func resolveVirtualChannel(virtualKey: String) async throws -> String {
        // Check memory cache
        if let channelId = channelForList[virtualKey] {
            return channelId
        }

        // Fetch from API
        let channel = try await apiClient.getOrCreateVirtualChannel(virtualKey: virtualKey)

        // Cache in CoreData
        try await coreDataManager.saveInBackground { context in
            let cdChannel = try CDChatChannel.fetchById(channel.id, context: context) ?? CDChatChannel(context: context)
            cdChannel.id = channel.id
            cdChannel.update(from: channel)
        }

        channelForList[virtualKey] = channel.id
        return channel.id
    }

    // MARK: - Cache Management

    /// Load cached messages from CoreData on startup
    private func loadCachedMessages() async {
        await coreDataManager.waitForStoreLoad()

        do {
            let messagesByChannel: [String: [ChatMessage]] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let cdMessages = try CDChatMessage.fetchAll(context: context)
                        var result: [String: [ChatMessage]] = [:]
                        for cdMessage in cdMessages {
                            let message = cdMessage.toDomainModel()
                            if result[message.channelId] == nil {
                                result[message.channelId] = []
                            }
                            result[message.channelId]?.append(message)
                        }
                        // Sort by createdAt ascending within each channel
                        for (channelId, messages) in result {
                            result[channelId] = messages.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                        }
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.cachedMessages = messagesByChannel
            let total = messagesByChannel.values.reduce(0) { $0 + $1.count }
            if total > 0 {
                logger.notice("Chat messages loaded: \(total, privacy: .public) messages for \(messagesByChannel.count, privacy: .public) channels")
            }
        } catch {
            logger.error("Failed to load cached chat messages: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load cached channel mappings from CoreData
    private func loadCachedChannels() async {
        await coreDataManager.waitForStoreLoad()

        do {
            let mappings: [String: String] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let channels = try CDChatChannel.fetchAll(context: context)
                        var result: [String: String] = [:]
                        for channel in channels {
                            if let listId = channel.listId {
                                result[listId] = channel.id
                            }
                        }
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.channelForList = mappings
        } catch {
            logger.error("Failed to load cached channels: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatePendingOperationsCount() async {
        do {
            let count: Int = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let pending = try CDChatMessage.fetchPending(context: context)
                        continuation.resume(returning: pending.count)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            pendingOperationsCount = count
        } catch {
            logger.error("Failed to count pending chat operations: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Fetching

    /// Fetch messages with cache hierarchy: Memory → CoreData → Network
    func fetchMessages(channelId: String, useCache: Bool = true) async throws -> [ChatMessage] {
        logger.notice("===== fetchMessages: \(channelId.prefix(8), privacy: .public) =====")

        // STEP 1: Memory cache
        if useCache, let cached = cachedMessages[channelId] {
            logger.notice("✓ MEMORY: \(cached.count, privacy: .public) messages")
            backgroundRefreshFromNetwork(channelId: channelId)
            return cached
        }

        // STEP 2: CoreData
        if useCache {
            await coreDataManager.waitForStoreLoad()
            let coreDataMessages = try await loadMessagesFromCoreData(channelId: channelId)
            if !coreDataMessages.isEmpty {
                logger.notice("✓ COREDATA: \(coreDataMessages.count, privacy: .public) messages")
                cachedMessages[channelId] = coreDataMessages
                backgroundRefreshFromNetwork(channelId: channelId)
                return coreDataMessages
            }
        }

        // STEP 3: Network
        if let existingTask = inFlightFetches[channelId] {
            return try await existingTask.value
        }

        logger.notice("→ NETWORK: Fetching...")
        isLoading = true
        errorMessage = nil

        let fetchTask = _Concurrency.Task<[ChatMessage], Error> { [weak self] in
            guard let self = self else { return [] }
            do {
                let response = try await self.apiClient.getChatMessages(channelId: channelId)
                logger.notice("✓ NETWORK: \(response.messages.count, privacy: .public) messages")

                await MainActor.run {
                    self.lastFetchTime[channelId] = Date()
                    self.hasMore[channelId] = response.hasMore
                }

                try await self.saveMessagesToCoreData(response.messages, channelId: channelId)

                await MainActor.run {
                    let pendingMessages = self.cachedMessages[channelId]?.filter { $0.id.hasPrefix("temp_") } ?? []
                    var merged = response.messages
                    merged.append(contentsOf: pendingMessages)
                    merged.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                    self.cachedMessages[channelId] = merged

                    NotificationCenter.default.post(name: .chatMessageDidSync, object: nil, userInfo: ["channelId": channelId])
                }

                return response.messages
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return []
                }
                logger.error("✗ NETWORK: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.errorMessage = error.localizedDescription }
                throw error
            }
        }

        inFlightFetches[channelId] = fetchTask

        do {
            let result = try await fetchTask.value
            inFlightFetches.removeValue(forKey: channelId)
            isLoading = false
            return result
        } catch {
            inFlightFetches.removeValue(forKey: channelId)
            isLoading = false
            throw error
        }
    }

    /// Load more messages (pagination — older messages)
    func loadMoreMessages(channelId: String) async throws {
        guard hasMore[channelId] == true else { return }

        // Find the oldest message's createdAt as cursor
        guard let oldest = cachedMessages[channelId]?.first(where: { !$0.id.hasPrefix("temp_") }),
              let oldestDate = oldest.createdAt else { return }

        let response = try await apiClient.getChatMessages(channelId: channelId, before: oldestDate, limit: 50)
        hasMore[channelId] = response.hasMore

        // Save to CoreData
        try await saveMessagesToCoreData(response.messages, channelId: channelId)

        // Prepend to cache
        var current = cachedMessages[channelId] ?? []
        let existingIds = Set(current.map { $0.id })
        let newMessages = response.messages.filter { !existingIds.contains($0.id) }
        current.insert(contentsOf: newMessages, at: 0)
        current.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        cachedMessages[channelId] = current
    }

    /// Fetch available agents through ChatService so views do not couple
    /// directly to the API client. The raw agent models are useful in settings
    /// screens, while chat input can map them to mentionable users.
    func fetchAvailableAgents(useCacheOnFailure: Bool = true) async throws -> [AvailableAgent] {
        do {
            let agents = try await apiClient.getAvailableAgents()
            AIAgentCache.shared.save(agents.map(Self.agentUser))
            return agents
        } catch {
            if useCacheOnFailure, let cachedUsers = AIAgentCache.shared.load() {
                return cachedUsers.map {
                    AvailableAgent(
                        id: $0.id,
                        name: $0.displayName,
                        email: $0.email ?? "",
                        image: $0.image,
                        service: $0.aiAgentType ?? ""
                    )
                }
            }
            throw error
        }
    }

    func fetchAvailableAgentUsers(useCacheOnFailure: Bool = true) async throws -> [User] {
        let agents = try await fetchAvailableAgents(useCacheOnFailure: useCacheOnFailure)
        return agents.map(Self.agentUser)
    }

    /// Refresh one channel from the v1 chat messages endpoint and preserve
    /// locally pending optimistic messages. Used by polling fallbacks and
    /// explicit refreshes so the merge behavior has one owner.
    @discardableResult
    func refreshMessagesFromServer(channelId: String) async throws -> [ChatMessage] {
        let response = try await apiClient.getChatMessages(channelId: channelId)
        hasMore[channelId] = response.hasMore

        let serverMessages = response.messages
        let serverIds = Set(serverMessages.map { $0.id })
        let serverClientRequestIds = Set(serverMessages.compactMap { $0.clientRequestId })
        let pendingMessages = cachedMessages[channelId]?.filter { message in
            guard message.id.hasPrefix("temp_") else { return false }
            guard !serverIds.contains(message.id) else { return false }
            if let clientRequestId = message.clientRequestId {
                return !serverClientRequestIds.contains(clientRequestId)
            }
            return true
        } ?? []

        var merged = serverMessages
        merged.append(contentsOf: pendingMessages)
        merged.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        cachedMessages[channelId] = merged
        lastFetchTime[channelId] = Date()

        try await saveMessagesToCoreData(serverMessages, channelId: channelId)
        NotificationCenter.default.post(name: .chatMessageDidSync, object: nil, userInfo: ["channelId": channelId])
        return merged
    }

    private static func agentUser(_ agent: AvailableAgent) -> User {
        User(
            id: agent.id,
            email: agent.email,
            name: agent.name,
            image: agent.image,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: true,
            aiAgentType: agent.service
        )
    }

    private func loadMessagesFromCoreData(channelId: String) async throws -> [ChatMessage] {
        let messages: [ChatMessage] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let cdMessages = try CDChatMessage.fetchByChannelId(channelId, context: context)
                    let domainMessages = cdMessages.map { $0.toDomainModel() }
                    continuation.resume(returning: domainMessages)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return messages
    }

    private func backgroundRefreshFromNetwork(channelId: String) {
        if let lastFetch = lastFetchTime[channelId], Date().timeIntervalSince(lastFetch) < 30 {
            return
        }
        lastFetchTime[channelId] = Date()

        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.apiClient.getChatMessages(channelId: channelId)
                try await self.saveMessagesToCoreData(response.messages, channelId: channelId)
                await MainActor.run {
                    self.hasMore[channelId] = response.hasMore
                    let pendingMessages = self.cachedMessages[channelId]?.filter { $0.id.hasPrefix("temp_") } ?? []
                    var merged = response.messages
                    merged.append(contentsOf: pendingMessages)
                    merged.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                    self.cachedMessages[channelId] = merged
                    NotificationCenter.default.post(name: .chatMessageDidSync, object: nil, userInfo: ["channelId": channelId])
                }
            } catch {
                // Silent fail - already returned cached data
            }
        }
    }

    // MARK: - Sending Messages

    /// Send a chat message (local-first with optimistic update)
    func sendMessage(
        channelId: String,
        content: String,
        type: Comment.CommentType = .TEXT,
        fileId: String? = nil,
        replyToId: String? = nil,
        authorId: String? = nil
    ) async throws -> ChatMessage {
        let tempId = "temp_\(UUID().uuidString)"
        let clientRequestId = UUID().uuidString

        // Look up attachment info for temp fileIds
        var secureFiles: [SecureFile]? = nil
        if let tempFileId = fileId, tempFileId.hasPrefix("temp_") {
            if let pending = AttachmentService.shared.pendingUploads[tempFileId] {
                let secureFile = SecureFile(
                    id: tempFileId,
                    name: pending.fileName,
                    size: pending.fileSize,
                    mimeType: pending.mimeType
                )
                secureFiles = [secureFile]
            }
        }

        let optimisticMessage = ChatMessage(
            id: tempId,
            channelId: channelId,
            authorId: authorId,
            author: nil,
            content: content,
            type: type,
            replyToId: replyToId,
            clientRequestId: clientRequestId,
            secureFiles: secureFiles,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to CoreData with pending status
        let savedFileId = fileId
        let savedContent = content
        let savedType = type.rawValue
        let savedReplyToId = replyToId

        var secureFilesJson: String? = nil
        if let files = secureFiles, !files.isEmpty {
            if let jsonData = try? JSONEncoder().encode(files),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                secureFilesJson = jsonString
            }
        }

        do {
            try await coreDataManager.saveInBackground { context in
                let cdMessage = CDChatMessage(context: context)
                cdMessage.id = tempId
                cdMessage.channelId = channelId
                cdMessage.content = savedContent
                cdMessage.type = savedType
                cdMessage.authorId = authorId
                cdMessage.replyToId = savedReplyToId
                cdMessage.clientRequestId = clientRequestId
                cdMessage.createdAt = Date()
                cdMessage.updatedAt = Date()
                cdMessage.syncStatus = "pending"
                cdMessage.pendingOperation = "create"
                cdMessage.syncAttempts = 0
                cdMessage.pendingFileId = savedFileId
                cdMessage.secureFilesData = secureFilesJson
            }
            await updatePendingOperationsCount()
        } catch {
            logger.error("Failed to save pending chat message: \(error.localizedDescription, privacy: .public)")
        }

        // Update in-memory cache
        if cachedMessages[channelId] == nil {
            cachedMessages[channelId] = []
        }
        cachedMessages[channelId]?.append(optimisticMessage)

        // Hand the send to the Outbox (authoritative). The clientRequestId
        // dedupes server-side (ChatMessage.clientRequestId is unique).
        let chatPayload = SendChatMessageOutboxPayload(
            channelId: channelId,
            content: content,
            type: type.rawValue,
            fileId: fileId,
            replyToId: replyToId
        )
        // A message with a staged attachment becomes an upload→send dependency
        // chain so the Outbox owns the upload and the send waits for the real
        // fileId from its dependency's result.
        if let temp = fileId, temp.hasPrefix("temp_"),
           let pending = AttachmentService.shared.pendingUploads[temp] {
            await OutboxManager.shared.enqueueChatMessage(
                chatPayload,
                clientRequestId: clientRequestId,
                attachment: UploadAttachmentOutboxPayload(
                    localPath: pending.localPath,
                    fileName: pending.fileName,
                    mimeType: pending.mimeType,
                    context: pending.uploadContext
                ),
                attachmentClientRequestId: temp
            )
        } else {
            await OutboxManager.shared.enqueueChatMessage(chatPayload, clientRequestId: clientRequestId)
        }

        return optimisticMessage
    }

    /// Delete a chat message (local-first with optimistic update)
    func deleteMessage(id: String, channelId: String) async throws {
        // Remove from memory cache
        if let index = cachedMessages[channelId]?.firstIndex(where: { $0.id == id }) {
            cachedMessages[channelId]?.remove(at: index)
        }

        // Mark as pending delete in CoreData
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    guard let cdMessage = try CDChatMessage.fetchById(id, context: context) else { return }
                    cdMessage.syncStatus = "pending_delete"
                    cdMessage.pendingOperation = "delete"
                    cdMessage.syncAttempts = 0
                }
                await self.updatePendingOperationsCount()
            } catch {
                // Silent fail
            }
        }

        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingMessages()
            }
        }
    }

    // MARK: - AI Assistant (on-device / agent response)
    //
    // These wrap AstridAPIClient so views and on-device-AI callers have a
    // single chat entry point — matches the ChatService contract for regular
    // messages. `getAIAssistantSettings` is called on every @Astrid send, so
    // it's cached briefly to avoid a round-trip per message.

    private var cachedAIAssistantSettings: (value: AIAssistantSettings, fetchedAt: Date)?
    private let aiAssistantSettingsTTL: TimeInterval = 60

    /// Returns the user's AI assistant settings, using a short in-memory
    /// cache so the on-device-model gate doesn't re-fetch on every keystroke.
    func getAIAssistantSettings() async throws -> AIAssistantSettings {
        if let cached = cachedAIAssistantSettings,
           Date().timeIntervalSince(cached.fetchedAt) < aiAssistantSettingsTTL {
            return cached.value
        }
        let settings = try await AstridAPIClient.shared.getAIAssistantSettings()
        cachedAIAssistantSettings = (settings, Date())
        return settings
    }

    /// Invalidate the AI-assistant-settings cache (e.g., after the user
    /// changes the model in settings).
    func invalidateAIAssistantSettingsCache() {
        cachedAIAssistantSettings = nil
    }

    /// Update the user's AI-assistant settings through the chat service
    /// boundary, then refresh the short-lived settings cache.
    @discardableResult
    func updateAIAssistantSettings(
        defaultAgentId: String? = nil,
        preferredService: String? = nil
    ) async throws -> AIAssistantSettings {
        let settings = try await apiClient.updateAIAssistantSettings(
            defaultAgentId: defaultAgentId,
            preferredService: preferredService
        )
        cachedAIAssistantSettings = (settings, Date())
        return settings
    }

    /// Post an on-device AI agent's response to a chat channel.
    func postAgentResponse(channelId: String, content: String) async throws {
        try await AstridAPIClient.shared.postAgentResponse(channelId: channelId, content: content)
    }

    // MARK: - SSE Event Handling

    /// Handle a new message from SSE
    func handleMessageCreated(_ message: ChatMessage, channelId: String) {
        // Deduplicate: if this message matches a pending message's clientRequestId, replace the temp
        if let clientRequestId = message.clientRequestId,
           let messages = cachedMessages[channelId],
           let index = messages.firstIndex(where: { $0.clientRequestId == clientRequestId && $0.id.hasPrefix("temp_") }) {
            // Replace optimistic message with server version
            cachedMessages[channelId]?[index] = message
            logger.notice("💬 SSE: Replaced temp message with server version (clientRequestId: \(clientRequestId.prefix(8), privacy: .public))")

            // Update CoreData: remove temp, save real
            let tempId = messages[index].id
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                try? await self.coreDataManager.saveInBackground { context in
                    // Delete the temp entry
                    if let temp = try CDChatMessage.fetchById(tempId, context: context) {
                        context.delete(temp)
                    }
                    // Save the real entry
                    let cdMessage = CDChatMessage(context: context)
                    cdMessage.id = message.id
                    cdMessage.update(from: message)
                    cdMessage.channelId = channelId
                    cdMessage.syncStatus = "synced"
                    cdMessage.lastSyncedAt = Date()
                }
                await self.updatePendingOperationsCount()
            }
            return
        }

        // Check if message already exists (avoid duplicates)
        if let messages = cachedMessages[channelId],
           messages.contains(where: { $0.id == message.id }) {
            return
        }

        // Add new message
        if cachedMessages[channelId] == nil {
            cachedMessages[channelId] = []
        }
        cachedMessages[channelId]?.append(message)
        cachedMessages[channelId]?.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }

        // Save to CoreData
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            try? await self.coreDataManager.saveInBackground { context in
                let cdMessage = CDChatMessage(context: context)
                cdMessage.id = message.id
                cdMessage.update(from: message)
                cdMessage.channelId = channelId
                cdMessage.syncStatus = "synced"
                cdMessage.lastSyncedAt = Date()
            }
        }
    }

    /// Handle a message update from SSE
    func handleMessageUpdated(_ message: ChatMessage, channelId: String) {
        if let messages = cachedMessages[channelId],
           let index = messages.firstIndex(where: { $0.id == message.id }) {
            cachedMessages[channelId]?[index] = message
        }

        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            try? await self.coreDataManager.saveInBackground { context in
                if let cdMessage = try CDChatMessage.fetchById(message.id, context: context) {
                    cdMessage.update(from: message)
                }
            }
        }
    }

    /// Handle a message deletion from SSE
    func handleMessageDeleted(_ messageId: String, channelId: String) {
        if let index = cachedMessages[channelId]?.firstIndex(where: { $0.id == messageId }) {
            cachedMessages[channelId]?.remove(at: index)
        }

        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            try? await self.coreDataManager.saveInBackground { context in
                if let cdMessage = try CDChatMessage.fetchById(messageId, context: context) {
                    context.delete(cdMessage)
                }
            }
        }
    }

    // MARK: - Background Sync

    private struct PendingMessageData {
        let id: String
        let channelId: String
        let content: String
        let type: String
        let operation: String
        let pendingFileId: String?
        let replyToId: String?
        let clientRequestId: String?
        let createdAt: Date?
    }

    func syncPendingMessages() async throws {
        guard networkMonitor.isConnected else { return }

        let pendingData: [PendingMessageData] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let messages = try CDChatMessage.fetchPending(context: context)
                    let extracted = messages.map { cdMessage in
                        PendingMessageData(
                            id: cdMessage.id,
                            channelId: cdMessage.channelId,
                            content: cdMessage.content,
                            type: cdMessage.type,
                            operation: cdMessage.pendingOperation ?? "unknown",
                            pendingFileId: cdMessage.pendingFileId,
                            replyToId: cdMessage.replyToId,
                            clientRequestId: cdMessage.clientRequestId,
                            createdAt: cdMessage.createdAt
                        )
                    }
                    continuation.resume(returning: extracted)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard !pendingData.isEmpty else { return }

        for data in pendingData {
            do {
                switch data.operation {
                case "create":
                    // Creates are Outbox-owned; deletes stay legacy until they
                    // get an Outbox kind.
                    continue
                case "delete":
                    try await syncPendingDelete(data)
                default:
                    try await markAsFailed(id: data.id, error: "Unknown operation type")
                }
            } catch ChatSyncError.attachmentPending {
                // Will retry automatically
            } catch {
                logger.error("Failed to sync chat \(data.operation, privacy: .public): \(error.localizedDescription, privacy: .public)")

                let isPermanent: Bool
                if case AstridAPIError.httpError(let code, _) = error, [403, 404, 410].contains(code) {
                    isPermanent = true
                } else {
                    isPermanent = false
                }

                if isPermanent {
                    try await markAsFailed(id: data.id, error: error.localizedDescription)
                } else {
                    try await markAsRetryable(id: data.id, error: error.localizedDescription)
                }
            }
        }

        await updatePendingOperationsCount()
        NotificationCenter.default.post(name: .chatMessageDidSync, object: nil)
    }

    /// Reconcile a pending chat message once the Outbox `sendChatMessage` handler
    /// succeeds. Looked up by clientRequestId (the temp message id and the
    /// idempotency key differ for chat). Idempotent (resetSyncState leaves
    /// clientRequestId intact, so a second call no-ops).
    func reconcileOutboxSentMessage(clientRequestId: String, serverMessage: ChatMessage, channelId: String) async {
        try? await coreDataManager.saveInBackground { context in
            guard let cdMessage = try CDChatMessage.fetchByClientRequestId(clientRequestId, context: context) else { return }
            cdMessage.id = serverMessage.id
            cdMessage.resetSyncState()
        }
        if var channelMessages = cachedMessages[channelId],
           let index = channelMessages.firstIndex(where: { $0.clientRequestId == clientRequestId }) {
            channelMessages[index] = serverMessage
            cachedMessages[channelId] = channelMessages
        }
    }

    private func syncPendingDelete(_ data: PendingMessageData) async throws {
        // Chat message deletion would go through a DELETE API endpoint
        // For now, just remove from CoreData
        let messageId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let cdMessage = try CDChatMessage.fetchById(messageId, context: context) else { return }
            context.delete(cdMessage)
        }
    }

    private func markAsFailed(id: String, error: String) async throws {
        try await coreDataManager.saveInBackground { context in
            guard let cdMessage = try CDChatMessage.fetchById(id, context: context) else { return }
            cdMessage.syncStatus = "failed"
            cdMessage.syncAttempts = CDChatMessage.maxSyncAttempts
            cdMessage.syncError = error
        }
    }

    private func markAsRetryable(id: String, error: String) async throws {
        try await coreDataManager.saveInBackground { context in
            guard let cdMessage = try CDChatMessage.fetchById(id, context: context) else { return }
            cdMessage.recordSyncFailure(error: error)
        }
    }
}

// MARK: - CoreData Persistence

extension ChatService {
    private func saveMessagesToCoreData(_ messages: [ChatMessage], channelId: String) async throws {
        await coreDataManager.waitForStoreLoad()

        try await coreDataManager.saveInBackground { context in
            let messageIds = messages.map { $0.id }
            let fetchRequest = CDChatMessage.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", messageIds)
            let existing = try context.fetch(fetchRequest)

            var existingDict = [String: CDChatMessage]()
            for cdMessage in existing {
                existingDict[cdMessage.id] = cdMessage
            }

            for message in messages {
                if let existingMessage = existingDict[message.id] {
                    if let existingUpdatedAt = existingMessage.updatedAt,
                       let messageUpdatedAt = message.updatedAt,
                       existingUpdatedAt == messageUpdatedAt {
                        continue  // Skip unchanged
                    }
                    existingMessage.update(from: message)
                    existingMessage.channelId = channelId
                    existingMessage.syncStatus = "synced"
                    existingMessage.lastSyncedAt = Date()
                } else {
                    let cdMessage = CDChatMessage(context: context)
                    cdMessage.id = message.id
                    cdMessage.update(from: message)
                    cdMessage.channelId = channelId
                    cdMessage.syncStatus = "synced"
                    cdMessage.lastSyncedAt = Date()
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let chatMessageDidSync = Notification.Name("chatMessageDidSync")
}
