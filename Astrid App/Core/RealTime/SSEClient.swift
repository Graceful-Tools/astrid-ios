@preconcurrency import Foundation
import UserNotifications


/// Server-Sent Events client for real-time updates
actor SSEClient {
    static let shared = SSEClient()

    private var streamTask: _Concurrency.Task<Void, Never>?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // Custom URLSession with cookie handling (same config as AstridAPIClient)
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = .infinity // SSE needs infinite timeout
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: UITestNetworkIsolation.harden(configuration))
    }()

    // Event handlers
    private var taskCreatedHandlers: [(@Sendable (Task) -> Void)] = []
    private var taskUpdatedHandlers: [(@Sendable (Task) -> Void)] = []
    private var taskDeletedHandlers: [(@Sendable (String) -> Void)] = []
    private var listCreatedHandlers: [(@Sendable (TaskList) -> Void)] = []
    private var listUpdatedHandlers: [(@Sendable (TaskList) -> Void)] = []
    private var listDeletedHandlers: [(@Sendable (String) -> Void)] = []
    private var commentAddedHandlers: [UUID: (@Sendable (Comment, String) -> Void)] = [:]  // (comment, taskId)
    private var commentUpdatedHandlers: [UUID: (@Sendable (Comment, String) -> Void)] = [:]
    private var commentDeletedHandlers: [UUID: (@Sendable (String, String) -> Void)] = [:]  // (commentId, taskId)
    private var myTasksPreferencesUpdatedHandlers: [(@Sendable (MyTasksPreferences) -> Void)] = []
    private var userSettingsUpdatedHandlers: [(@Sendable (UserSettings) -> Void)] = []
    private var chatMessageCreatedHandlers: [UUID: (@Sendable (ChatMessage, String) -> Void)] = [:]  // (message, channelId)
    private var chatMessageUpdatedHandlers: [UUID: (@Sendable (ChatMessage, String) -> Void)] = [:]
    private var chatMessageDeletedHandlers: [UUID: (@Sendable (String, String) -> Void)] = [:]  // (messageId, channelId)
    private var agentTypingStartHandlers: [UUID: (@Sendable (String, String?, String?) -> Void)] = [:]  // (agentName, channelId?, taskId?)
    private var agentTypingStopHandlers: [UUID: (@Sendable (String?, String?) -> Void)] = [:]  // (channelId?, taskId?)

    private init() {}

    // MARK: - Helpers

    private func buildSSERequest() async throws -> URLRequest {
        // Build URL string safely
        let baseURL = await MainActor.run { Constants.API.baseURL }
        let sseEndpoint = await MainActor.run { Constants.API.sseEndpoint }
        let urlString = baseURL + sseEndpoint

        guard let url = URL(string: urlString) else {
            print("❌ [SSE] Invalid URL")
            throw SSEError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = .infinity

        // Manually set Cookie header from KeychainService (same as AstridAPIClient)
        // URLSession's automatic cookie handling doesn't work reliably for SSE
        let sessionCookie = try? await MainActor.run {
            try KeychainService.shared.getSessionCookie()
        }

        guard let cookie = sessionCookie else {
            print("⚠️ [SSE] No session cookie in Keychain")
            throw SSEError.noSessionCookie
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        return request
    }

    // MARK: - Connection Management

    func connect() async {
        guard !isConnected else {
            return
        }

        // Build request — this also checks for session cookie
        let request: URLRequest
        do {
            request = try await buildSSERequest()
        } catch {
            print("❌ [SSE] Failed to build request: \(error)")
            return
        }

        // Verify the request has a Cookie header (no cookie = no point connecting)
        guard request.value(forHTTPHeaderField: "Cookie") != nil else {
            print("⚠️ [SSE] No session cookie - skipping connection")
            return
        }

        print("📡 [SSE] Connecting...")
        isConnected = true

        // Create streaming task
        streamTask = _Concurrency.Task { [weak self] in
            await self?.startStreaming(request: request)
        }
    }

    func disconnect() {
        print("📡 [SSE] Disconnecting...")
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    private func startStreaming(request: URLRequest) async {
        do {
            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [SSE] Invalid response type")
                await handleConnectionError(NSError(domain: "SSE", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ [SSE] Connection failed - status: \(httpResponse.statusCode)")
                await handleConnectionError(NSError(domain: "SSE", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                return
            }

            print("✅ [SSE] Connected and streaming")
            resetReconnectAttempts()

            // Process bytes as they stream in
            var buffer = ""
            var bytesReceived = 0

            for try await byte in bytes {
                // Check if task was cancelled
                if _Concurrency.Task.isCancelled {
                    print("📡 [SSE] Stream cancelled")
                    break
                }

                bytesReceived += 1

                // Convert byte to character and append to buffer
                if let character = String(bytes: [byte], encoding: .utf8) {
                    buffer.append(character)

                    // Process complete events (SSE events end with double newline)
                    if buffer.hasSuffix("\n\n") {
                        print("📦 [SSE] Received complete event, bytes so far: \(bytesReceived)")
                        await processSSEBuffer(buffer)
                        buffer = ""
                    }
                }
            }

            print("📡 [SSE] Stream ended — will reconnect")
            // Stream ended normally (server closed connection) — reconnect
            isConnected = false
            resetReconnectAttempts()
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)  // 2s delay
            if !_Concurrency.Task.isCancelled {
                await connect()
            }

        } catch {
            print("❌ [SSE] Stream error: \(error.localizedDescription)")
            await handleConnectionError(error)
        }
    }

    private func resetReconnectAttempts() {
        reconnectAttempts = 0
    }

    private func handleConnectionError(_ error: Error) async {
        isConnected = false

        // Don't reconnect if task was cancelled (intentional disconnect)
        guard !_Concurrency.Task.isCancelled else {
            return
        }

        // Don't reconnect on auth errors (401) — no point retrying without valid session
        let nsError = error as NSError
        if nsError.code == 401 {
            print("🔒 [SSE] Auth failed (401) - stopping reconnection")
            return
        }

        // Attempt reconnect with exponential backoff
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)

            print("⏳ [SSE] Reconnecting in \(Int(delay))s... (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

            do {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await connect()
            } catch {
                // Sleep interrupted, likely app backgrounded
            }
        } else {
            print("❌ [SSE] Max reconnect attempts reached")
        }
    }

    private func processSSEBuffer(_ buffer: String) async {
        let lines = buffer.components(separatedBy: "\n")
        var eventType: String?
        var eventData: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("event:") {
                eventType = trimmedLine
                    .replacingOccurrences(of: "event:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.hasPrefix("data:") {
                eventData = trimmedLine
                    .replacingOccurrences(of: "data:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Handle unnamed events (new format: type is in data JSON)
        if eventType == nil, let data = eventData {
            // Try to parse JSON and extract type field
            if let jsonData = data.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let type = json["type"] as? String {
                // For unnamed events, the entire JSON is the event data
                handleEvent(type: type, data: data)
                return
            }
        }

        // Handle named events (old format: type on separate line)
        if let type = eventType, let data = eventData {
            handleEvent(type: type, data: data)
        }
    }

    // MARK: - Event Parsing

    nonisolated private func handleEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8) else { return }

        _Concurrency.Task { @MainActor in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            do {
                // Extract nested data field if present (new unnamed event format)
                let payload: Data
                if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let nestedData = json["data"] {
                    // New format: extract nested data field
                    payload = try JSONSerialization.data(withJSONObject: nestedData)
                } else {
                    // Old format: data is the payload directly
                    payload = jsonData
                }

                switch type {
                case "task_created":
                    let task = try decoder.decode(Task.self, from: payload)
                    await notifyTaskCreated(task)

                case "task_updated":
                    let task = try decoder.decode(Task.self, from: payload)
                    await notifyTaskUpdated(task)

                case "task_deleted":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let taskId = json["id"] as? String {
                        await notifyTaskDeleted(taskId)
                    }

                case "list_created":
                    let list = try decoder.decode(TaskList.self, from: payload)
                    await notifyListCreated(list)

                case "list_updated":
                    let list = try decoder.decode(TaskList.self, from: payload)
                    await notifyListUpdated(list)

                case "list_deleted":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let listId = json["id"] as? String {
                        await notifyListDeleted(listId)
                    }

                case "comment_added", "comment_created":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let taskId = json["taskId"] as? String,
                       let commentData = json["comment"] as? [String: Any],
                       let commentJsonData = try? JSONSerialization.data(withJSONObject: commentData) {
                        let comment = try decoder.decode(Comment.self, from: commentJsonData)
                        await notifyCommentAdded(comment, taskId: taskId)
                    }

                case "comment_updated":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let taskId = json["taskId"] as? String,
                       let commentData = json["comment"] as? [String: Any],
                       let commentJsonData = try? JSONSerialization.data(withJSONObject: commentData) {
                        let comment = try decoder.decode(Comment.self, from: commentJsonData)
                        await notifyCommentUpdated(comment, taskId: taskId)
                    }

                case "comment_deleted":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let taskId = json["taskId"] as? String,
                       let commentId = json["commentId"] as? String {
                        await notifyCommentDeleted(commentId, taskId: taskId)
                    }

                case "my_tasks_preferences_updated":
                    let preferences = try decoder.decode(MyTasksPreferences.self, from: payload)
                    await notifyMyTasksPreferencesUpdated(preferences)

                case "user_settings_updated":
                    let settings = try decoder.decode(UserSettings.self, from: payload)
                    await notifyUserSettingsUpdated(settings)

                case "chat_message_created":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let channelId = json["channelId"] as? String,
                       let messageData = json["message"] as? [String: Any],
                       let messageJsonData = try? JSONSerialization.data(withJSONObject: messageData) {
                        let message = try decoder.decode(ChatMessage.self, from: messageJsonData)
                            await notifyChatMessageCreated(message, channelId: channelId)
                    }

                case "chat_message_updated":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let channelId = json["channelId"] as? String,
                       let messageData = json["message"] as? [String: Any],
                       let messageJsonData = try? JSONSerialization.data(withJSONObject: messageData) {
                        let message = try decoder.decode(ChatMessage.self, from: messageJsonData)
                        await notifyChatMessageUpdated(message, channelId: channelId)
                    }

                case "chat_message_deleted":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                       let channelId = json["channelId"] as? String,
                       let messageId = json["messageId"] as? String {
                        await notifyChatMessageDeleted(messageId, channelId: channelId)
                    }

                case "agent_typing_start":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                        let agentName = json["agentName"] as? String ?? "Agent"
                        let channelId = json["channelId"] as? String
                        let taskId = json["taskId"] as? String
                        await notifyAgentTypingStart(agentName, channelId: channelId, taskId: taskId)
                    }

                case "agent_typing_stop":
                    if let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                        let channelId = json["channelId"] as? String
                        let taskId = json["taskId"] as? String
                        await notifyAgentTypingStop(channelId: channelId, taskId: taskId)
                    }

                case "external_sync_refresh":
                    // Server nudge: an external provider (e.g. a GitHub webhook)
                    // reported changes — wake the client sync workers to pull.
                    await MainActor.run {
                        NotificationCenter.default.post(name: .externalSyncRefresh, object: nil)
                    }

                case "feature_flags_updated":
                    let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
                    let version = json?["version"] as? Int ?? 0
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .featureFlagsUpdated,
                            object: nil,
                            userInfo: ["version": version]
                        )
                    }

                case "connected", "ping":
                    // Standard SSE keepalive events - handle silently
                    break

                default:
                    print("⚠️ Unknown SSE event type: \(type)")
                }
            } catch {
                print("❌ Failed to decode SSE event \(type): \(error)")
            }
        }
    }
    
    // MARK: - Event Handlers Registration

    func onTaskCreated(_ handler: @escaping @Sendable (Task) -> Void) {
        taskCreatedHandlers.append(handler)
    }

    func onTaskUpdated(_ handler: @escaping @Sendable (Task) -> Void) {
        taskUpdatedHandlers.append(handler)
    }

    func onTaskDeleted(_ handler: @escaping @Sendable (String) -> Void) {
        taskDeletedHandlers.append(handler)
    }

    func onListCreated(_ handler: @escaping @Sendable (TaskList) -> Void) {
        listCreatedHandlers.append(handler)
    }

    func onListUpdated(_ handler: @escaping @Sendable (TaskList) -> Void) {
        listUpdatedHandlers.append(handler)
    }

    func onListDeleted(_ handler: @escaping @Sendable (String) -> Void) {
        listDeletedHandlers.append(handler)
    }

    func onCommentAdded(_ handler: @escaping @Sendable (Comment, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        commentAddedHandlers[handlerId] = handler
        print("📝 [SSE] Registered comment_added handler \(handlerId). Total: \(commentAddedHandlers.count)")

        // Return unsubscribe closure
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeCommentAddedHandler(id: handlerId)
            }
        }
    }

    func onCommentUpdated(_ handler: @escaping @Sendable (Comment, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        commentUpdatedHandlers[handlerId] = handler
        print("📝 [SSE] Registered comment_updated handler \(handlerId). Total: \(commentUpdatedHandlers.count)")

        // Return unsubscribe closure
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeCommentUpdatedHandler(id: handlerId)
            }
        }
    }

    func onCommentDeleted(_ handler: @escaping @Sendable (String, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        commentDeletedHandlers[handlerId] = handler
        print("📝 [SSE] Registered comment_deleted handler \(handlerId). Total: \(commentDeletedHandlers.count)")

        // Return unsubscribe closure
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeCommentDeletedHandler(id: handlerId)
            }
        }
    }

    func onMyTasksPreferencesUpdated(_ handler: @escaping @Sendable (MyTasksPreferences) -> Void) {
        print("🔧 [SSE] Registering My Tasks preferences handler (total will be: \(myTasksPreferencesUpdatedHandlers.count + 1))")
        myTasksPreferencesUpdatedHandlers.append(handler)
        print("✅ [SSE] Handler registered. Total handlers: \(myTasksPreferencesUpdatedHandlers.count)")
    }

    func onUserSettingsUpdated(_ handler: @escaping @Sendable (UserSettings) -> Void) {
        print("🔧 [SSE] Registering User Settings handler (total will be: \(userSettingsUpdatedHandlers.count + 1))")
        userSettingsUpdatedHandlers.append(handler)
        print("✅ [SSE] User Settings handler registered. Total handlers: \(userSettingsUpdatedHandlers.count)")
    }

    func onChatMessageCreated(_ handler: @escaping @Sendable (ChatMessage, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        chatMessageCreatedHandlers[handlerId] = handler
        print("💬 [SSE] Registered chat_message_created handler \(handlerId). Total: \(chatMessageCreatedHandlers.count)")
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeChatMessageCreatedHandler(id: handlerId)
            }
        }
    }

    func onChatMessageUpdated(_ handler: @escaping @Sendable (ChatMessage, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        chatMessageUpdatedHandlers[handlerId] = handler
        print("💬 [SSE] Registered chat_message_updated handler \(handlerId). Total: \(chatMessageUpdatedHandlers.count)")
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeChatMessageUpdatedHandler(id: handlerId)
            }
        }
    }

    func onChatMessageDeleted(_ handler: @escaping @Sendable (String, String) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        chatMessageDeletedHandlers[handlerId] = handler
        print("💬 [SSE] Registered chat_message_deleted handler \(handlerId). Total: \(chatMessageDeletedHandlers.count)")
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in
                await self?.removeChatMessageDeletedHandler(id: handlerId)
            }
        }
    }

    func onAgentTypingStart(_ handler: @escaping @Sendable (String, String?, String?) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        agentTypingStartHandlers[handlerId] = handler
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in await self?.removeAgentTypingStartHandler(id: handlerId) }
        }
    }

    func onAgentTypingStop(_ handler: @escaping @Sendable (String?, String?) -> Void) -> @Sendable () -> Void {
        let handlerId = UUID()
        agentTypingStopHandlers[handlerId] = handler
        return { @Sendable [weak self] in
            _Concurrency.Task { [weak self] in await self?.removeAgentTypingStopHandler(id: handlerId) }
        }
    }

    // MARK: - Handler Removal

    private func removeAgentTypingStartHandler(id: UUID) {
        agentTypingStartHandlers.removeValue(forKey: id)
    }

    private func removeAgentTypingStopHandler(id: UUID) {
        agentTypingStopHandlers.removeValue(forKey: id)
    }

    private func removeCommentAddedHandler(id: UUID) {
        commentAddedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed comment_added handler \(id). Remaining: \(commentAddedHandlers.count)")
    }

    private func removeCommentUpdatedHandler(id: UUID) {
        commentUpdatedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed comment_updated handler \(id). Remaining: \(commentUpdatedHandlers.count)")
    }

    private func removeCommentDeletedHandler(id: UUID) {
        commentDeletedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed comment_deleted handler \(id). Remaining: \(commentDeletedHandlers.count)")
    }

    private func removeChatMessageCreatedHandler(id: UUID) {
        chatMessageCreatedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed chat_message_created handler \(id). Remaining: \(chatMessageCreatedHandlers.count)")
    }

    private func removeChatMessageUpdatedHandler(id: UUID) {
        chatMessageUpdatedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed chat_message_updated handler \(id). Remaining: \(chatMessageUpdatedHandlers.count)")
    }

    private func removeChatMessageDeletedHandler(id: UUID) {
        chatMessageDeletedHandlers.removeValue(forKey: id)
        print("🗑️ [SSE] Removed chat_message_deleted handler \(id). Remaining: \(chatMessageDeletedHandlers.count)")
    }

    // MARK: - Notifications
    
    private func notifyTaskCreated(_ task: Task) {
        for handler in taskCreatedHandlers {
            handler(task)
        }
    }
    
    private func notifyTaskUpdated(_ task: Task) {
        for handler in taskUpdatedHandlers {
            handler(task)
        }
    }
    
    private func notifyTaskDeleted(_ taskId: String) {
        for handler in taskDeletedHandlers {
            handler(taskId)
        }
    }
    
    private func notifyListCreated(_ list: TaskList) {
        for handler in listCreatedHandlers {
            handler(list)
        }
    }

    private func notifyListUpdated(_ list: TaskList) {
        for handler in listUpdatedHandlers {
            handler(list)
        }
    }

    private func notifyListDeleted(_ listId: String) {
        for handler in listDeletedHandlers {
            handler(listId)
        }
    }

    private func notifyCommentAdded(_ comment: Comment, taskId: String) {
        print("🔔 [SSE] Notifying \(commentAddedHandlers.count) comment_added handlers for task \(taskId)")
        for (_, handler) in commentAddedHandlers {
            handler(comment, taskId)
        }
        
        // Trigger local notification if mentioned or assigned
        _Concurrency.Task { @MainActor in
            triggerLocalNotificationIfNeeded(comment: comment, taskId: taskId)
        }
    }

    @MainActor
    private func triggerLocalNotificationIfNeeded(comment: Comment, taskId: String) {
        guard let currentUserId = AuthManager.shared.currentUser?.id else { return }
        guard comment.authorId != currentUserId else { return }
        
        let content = comment.content
        let isMentioned = content.contains("(\(currentUserId))")
        
        // Check if user is assignee of the task
        let isAssignee = TaskService.shared.tasks.first(where: { $0.id == taskId })?.assigneeId == currentUserId
        
        if isMentioned || isAssignee {
            let notificationContent = UNMutableNotificationContent()
            notificationContent.title = isMentioned ? "\(comment.author?.displayName ?? "Someone") mentioned you" : "New comment on your task"
            notificationContent.body = comment.content
            notificationContent.userInfo = ["taskId": taskId, "commentId": comment.id]
            notificationContent.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func notifyCommentUpdated(_ comment: Comment, taskId: String) {
        print("🔔 [SSE] Notifying \(commentUpdatedHandlers.count) comment_updated handlers for task \(taskId)")
        for (_, handler) in commentUpdatedHandlers {
            handler(comment, taskId)
        }
    }

    private func notifyCommentDeleted(_ commentId: String, taskId: String) {
        print("🔔 [SSE] Notifying \(commentDeletedHandlers.count) comment_deleted handlers for task \(taskId)")
        for (_, handler) in commentDeletedHandlers {
            handler(commentId, taskId)
        }
    }

    private func notifyMyTasksPreferencesUpdated(_ preferences: MyTasksPreferences) {
        print("🔔 [SSE] notifyMyTasksPreferencesUpdated called with \(myTasksPreferencesUpdatedHandlers.count) handlers")
        for handler in myTasksPreferencesUpdatedHandlers {
            print("🔔 [SSE] Calling My Tasks preferences handler...")
            handler(preferences)
            print("🔔 [SSE] Handler called successfully")
        }
    }

    private func notifyUserSettingsUpdated(_ settings: UserSettings) {
        print("🔔 [SSE] notifyUserSettingsUpdated called with \(userSettingsUpdatedHandlers.count) handlers")
        for handler in userSettingsUpdatedHandlers {
            print("🔔 [SSE] Calling User Settings handler...")
            handler(settings)
            print("🔔 [SSE] User Settings handler called successfully")
        }
    }

    private func notifyChatMessageCreated(_ message: ChatMessage, channelId: String) {
        print("🔔 [SSE] Notifying \(chatMessageCreatedHandlers.count) chat_message_created handlers for channel \(channelId)")
        for (_, handler) in chatMessageCreatedHandlers {
            handler(message, channelId)
        }
    }

    private func notifyChatMessageUpdated(_ message: ChatMessage, channelId: String) {
        print("🔔 [SSE] Notifying \(chatMessageUpdatedHandlers.count) chat_message_updated handlers for channel \(channelId)")
        for (_, handler) in chatMessageUpdatedHandlers {
            handler(message, channelId)
        }
    }

    private func notifyChatMessageDeleted(_ messageId: String, channelId: String) {
        print("🔔 [SSE] Notifying \(chatMessageDeletedHandlers.count) chat_message_deleted handlers for channel \(channelId)")
        for (_, handler) in chatMessageDeletedHandlers {
            handler(messageId, channelId)
        }
    }

    private func notifyAgentTypingStart(_ agentName: String, channelId: String?, taskId: String?) {
        for (_, handler) in agentTypingStartHandlers {
            handler(agentName, channelId, taskId)
        }
    }

    private func notifyAgentTypingStop(channelId: String?, taskId: String?) {
        for (_, handler) in agentTypingStopHandlers {
            handler(channelId, taskId)
        }
    }
}

// MARK: - Errors

enum SSEError: Error {
    case invalidURL
    case noSessionCookie
}
