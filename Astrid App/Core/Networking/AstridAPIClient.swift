import Foundation

/**
 * Astrid API Client
 *
 * Modern RESTful client for Astrid API v1
 * Uses OAuth 2.0 for authentication (via OAuthManager)
 * Replaces legacy MCPClient with standard REST endpoints
 */
class AstridAPIClient {
    static let shared = AstridAPIClient()

    /// Dynamic baseURL that reads current server preference
    private var baseURL: URL {
        URL(string: Constants.API.baseURL)!
    }
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.API.timeout
        configuration.timeoutIntervalForResource = Constants.API.timeout
        // Enable cookie handling (required for session authentication)
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        self.session = URLSession(configuration: configuration)

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        // Use custom date formatter that handles ISO8601 with fractional seconds
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try with fractional seconds first
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }

            // Fallback to standard ISO8601 without fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
    }

    // MARK: - Generic Request Method

    private func request<T: Codable>(
        method: String,
        path: String,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        // Build URL with query parameters
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AstridAPIError.invalidURL
        }

        print("📡 [AstridAPI] \(method) \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Use session cookie authentication (same as existing APIClient)
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            print("🍪 [AstridAPI] Using session cookie authentication")
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AstridAPI] No session cookie available - API calls may fail")
        }

        // Add body if present
        if let body = body {
            request.httpBody = try encoder.encode(body)
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                print("📤 [AstridAPI] Request body: \(bodyString)")
            }
        }

        print("🔄 [AstridAPI] Waiting for response...")
        let (data, response): (Data, URLResponse)
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
            print("✅ [AstridAPI] Response received, data size: \(data.count) bytes")
        } catch let urlError as URLError {
            print("❌ [AstridAPI] URL Error: \(urlError.localizedDescription)")
            print("❌ [AstridAPI] Error code: \(urlError.code.rawValue)")
            throw urlError
        } catch {
            print("❌ [AstridAPI] Unknown error during request: \(error)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AstridAPI] Invalid response (not HTTP)")
            throw AstridAPIError.invalidResponse
        }

        print("📡 [AstridAPI] Response status: \(httpResponse.statusCode)")

        // Log response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("📥 [AstridAPI] Response body preview: \(String(responseString.prefix(500)))...")
        }

        // Handle error responses
        if httpResponse.statusCode == 401 {
            print("❌ [AstridAPI] Unauthorized (401)")
            throw AstridAPIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ [AstridAPI] HTTP error \(httpResponse.statusCode): \(responseString)")
            throw AstridAPIError.httpError(statusCode: httpResponse.statusCode, message: responseString)
        }

        // Decode response
        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ [AstridAPI] Decoding error: \(error)")
            print("📄 [AstridAPI] Response: \(responseString)")
            throw AstridAPIError.decodingError(error)
        }
    }

    /// Generic request method that accepts a raw dictionary body
    /// Uses JSONSerialization to properly encode NSNull() as JSON null
    /// This is needed for fields that need to be explicitly set to null (e.g., clearing defaultAssigneeId)
    private func requestWithDictionary<T: Codable>(
        method: String,
        path: String,
        body: [String: Any],
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        // Build URL with query parameters
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AstridAPIError.invalidURL
        }

        print("📡 [AstridAPI] \(method) \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Use session cookie authentication
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            print("🍪 [AstridAPI] Using session cookie authentication")
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AstridAPI] No session cookie available - API calls may fail")
        }

        // Encode body using JSONSerialization (properly handles NSNull as null)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
            print("📤 [AstridAPI] Request body (with nulls): \(bodyString)")
        }

        print("🔄 [AstridAPI] Waiting for response...")
        let (data, response): (Data, URLResponse)
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
            print("✅ [AstridAPI] Response received, data size: \(data.count) bytes")
        } catch let urlError as URLError {
            print("❌ [AstridAPI] URL Error: \(urlError.localizedDescription)")
            throw AstridAPIError.httpError(statusCode: urlError.code.rawValue, message: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AstridAPIError.invalidResponse
        }

        print("📥 [AstridAPI] HTTP Status: \(httpResponse.statusCode)")

        // Handle non-2xx responses
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ [AstridAPI] Error response: \(responseString)")
            throw AstridAPIError.httpError(statusCode: httpResponse.statusCode, message: responseString)
        }

        // Decode response
        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ [AstridAPI] Decoding error: \(error)")
            print("📄 [AstridAPI] Response: \(responseString)")
            throw AstridAPIError.decodingError(error)
        }
    }

    // MARK: - Shortcode Operations

    struct ShortcodeResolution: Codable {
        let targetType: String
        let targetId: String
    }

    /// Resolve a shortcode to its target task or list
    /// - Parameter code: The shortcode to resolve
    /// - Returns: Resolution object containing targetType and targetId
    func resolveShortcode(_ code: String) async throws -> ShortcodeResolution {
        return try await request(
            method: "GET",
            path: "api/shortcodes/\(code)"
        )
    }

    // MARK: - Task Operations

    /// Get tasks with pagination support
    /// - Parameters:
    ///   - listId: Optional list ID to filter by
    ///   - completed: Optional completion status filter
    ///   - limit: Max results per page (default: 1000, API max is 1000)
    ///   - offset: Pagination offset (default: 0)
    /// - Returns: Tuple of (tasks, total count)
    func getTasks(listId: String? = nil, completed: Bool? = nil, limit: Int = 1000, offset: Int = 0) async throws -> (tasks: [Task], total: Int) {
        var queryItems: [URLQueryItem] = []
        if let listId = listId {
            queryItems.append(URLQueryItem(name: "listId", value: listId))
        }
        if let completed = completed {
            queryItems.append(URLQueryItem(name: "completed", value: String(completed)))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))

        let response: TasksResponse = try await request(
            method: "GET",
            path: "/api/v1/tasks",
            queryItems: queryItems
        )
        return (response.tasks, response.meta?.total ?? response.tasks.count)
    }

    /// Get all tasks with automatic pagination (for full sync)
    /// Fetches all pages until all tasks are retrieved
    func getAllTasks(listId: String? = nil, completed: Bool? = nil) async throws -> [Task] {
        var allTasks: [Task] = []
        var offset = 0
        let limit = 1000

        while true {
            let (tasks, total) = try await getTasks(listId: listId, completed: completed, limit: limit, offset: offset)
            allTasks.append(contentsOf: tasks)

            print("📥 [AstridAPI] Fetched \(tasks.count) tasks (offset: \(offset), total: \(total))")

            // Check if we've fetched all tasks
            if allTasks.count >= total || tasks.isEmpty {
                break
            }

            offset += limit
        }

        print("📥 [AstridAPI] Total tasks fetched: \(allTasks.count)")
        return allTasks
    }

    /// Get a single task by ID
    func getTask(id: String) async throws -> Task {
        let response: TaskResponse = try await request(
            method: "GET",
            path: "/api/v1/tasks/\(id)"
        )
        return response.task
    }

    /// Create a new task
    func createTask(
        title: String,
        listIds: [String]? = nil,
        description: String? = nil,
        priority: Int? = nil,
        assigneeId: String? = nil,
        dueDateTime: Date? = nil,  // The due date/time (UTC midnight for all-day tasks)
        isAllDay: Bool? = nil,  // Whether this is an all-day task
        isPrivate: Bool? = nil,
        repeating: String? = nil,
        clientRequestId: String? = nil  // Idempotency key for dedup
    ) async throws -> Task {
        // Convert Date to ISO8601 string for API
        // Backend expects:
        // - 'dueDateTime' = datetime (UTC midnight for all-day tasks, specific time for timed tasks)
        // - 'isAllDay' = boolean flag

        // CRITICAL: For all-day tasks, normalize to UTC midnight
        let dueDateTimeString: String?
        if let dueDateTime = dueDateTime {
            if isAllDay == true {
                // All-day task - normalize to midnight UTC
                var utcCalendar = Calendar.current
                utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                let startOfDay = utcCalendar.startOfDay(for: dueDateTime)
                dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
            } else {
                // Timed task - use exact datetime
                dueDateTimeString = ISO8601DateFormatter().string(from: dueDateTime)
            }
        } else {
            dueDateTimeString = nil
        }

        let body = CreateTaskRequest(
            title: title,
            description: description,
            priority: priority,
            repeating: repeating,
            repeatingData: nil,
            isPrivate: isPrivate,
            dueDateTime: dueDateTimeString,
            isAllDay: isAllDay,
            reminderTime: nil,
            reminderType: nil,
            listIds: listIds,
            assigneeId: assigneeId,
            assigneeEmail: nil,
            clientRequestId: clientRequestId
        )

        let response: TaskResponse = try await request(
            method: "POST",
            path: "/api/v1/tasks",
            body: body
        )
        return response.task
    }

    /// Update a task
    func updateTask(id: String, updates: UpdateTaskRequest) async throws -> Task {
        let response: TaskResponse = try await request(
            method: "PUT",
            path: "/api/v1/tasks/\(id)",
            body: updates
        )
        return response.task
    }

    /// Delete a task
    func deleteTask(id: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/api/v1/tasks/\(id)"
        )
    }

    // MARK: - Shortcode Operations

    /// Create a shortcode for sharing a task or list
    func createShortcode(targetType: String, targetId: String) async throws -> ShortcodeResponse {
        let body = CreateShortcodeRequest(
            targetType: targetType,
            targetId: targetId
        )

        let response: ShortcodeResponse = try await request(
            method: "POST",
            path: "/api/v1/shortcodes",
            body: body
        )
        return response
    }

    // MARK: - List Operations

    /// Get all lists
    func getLists() async throws -> [TaskList] {
        let response: ListsResponse = try await request(
            method: "GET",
            path: "/api/v1/lists"
        )
        return response.lists
    }

    /// Create a new list
    func createList(name: String, description: String? = nil, color: String? = nil, privacy: String = "PRIVATE") async throws -> TaskList {
        let body = CreateListRequest(
            name: name,
            description: description,
            color: color,
            imageUrl: nil,
            privacy: privacy,
            adminIds: nil,
            memberIds: nil,
            memberEmails: nil,
            defaultAssigneeId: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil
        )

        let response: ListResponse = try await request(
            method: "POST",
            path: "/api/v1/lists",
            body: body
        )
        return response.list
    }

    /// Get a single list by ID
    func getList(id: String) async throws -> TaskList {
        let response: ListResponse = try await request(
            method: "GET",
            path: "/api/v1/lists/\(id)"
        )
        return response.list
    }

    /// Update a list
    func updateList(id: String, updates: UpdateListRequest) async throws -> TaskList {
        let response: ListResponse = try await request(
            method: "PUT",
            path: "/api/v1/lists/\(id)",
            body: updates
        )
        return response.list
    }

    /// Update a list with raw dictionary (supports NSNull for explicit null values)
    /// Use this when you need to clear fields by sending null (e.g., defaultAssigneeId = null for "Task Creator")
    func updateListWithDictionary(id: String, updates: [String: Any]) async throws -> TaskList {
        let response: ListResponse = try await requestWithDictionary(
            method: "PUT",
            path: "/api/v1/lists/\(id)",
            body: updates
        )
        return response.list
    }

    /// Delete a list
    func deleteList(id: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/api/v1/lists/\(id)"
        )
    }

    /// Leave a shared list
    func leaveList(id: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            method: "POST",
            path: "/api/v1/lists/\(id)/leave"
        )
    }

    // MARK: - GitHub Integration

    /// Get GitHub connection and AI provider status
    /// - Returns: Status indicating if user has GitHub connected and AI providers configured
    func getGitHubStatus() async throws -> GitHubStatusResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/github/status"
        )
    }

    /// Get GitHub repositories available to user
    /// - Parameter refresh: If true, fetches fresh data from GitHub API. If false, returns cached data.
    /// - Returns: Response containing list of repositories
    func getGitHubRepositories(refresh: Bool = false) async throws -> GitHubRepositoriesResponse {
        var queryItems: [URLQueryItem] = []
        if refresh {
            queryItems.append(URLQueryItem(name: "refresh", value: "true"))
        }

        return try await request(
            method: "GET",
            path: "/api/v1/github/repositories",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
    }

    // MARK: - Comment Operations

    /// Get all comments for a task
    func getTaskComments(taskId: String) async throws -> CommentsListResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/tasks/\(taskId)/comments"
        )
    }

    /// Create a new comment on a task.
    /// - Parameter clientRequestId: Idempotency key — when iOS replays a queued
    ///   create after a network reconnect, the server returns the same row
    ///   instead of inserting a duplicate. Pass the optimistic temp ID so the
    ///   key is stable across all retry attempts (it's already persisted in
    ///   CDComment.id).
    func createComment(
        taskId: String,
        content: String,
        type: Comment.CommentType = .TEXT,
        fileId: String? = nil,
        parentCommentId: String? = nil,
        createdAt: Date? = nil,
        clientRequestId: String? = nil
    ) async throws -> CommentResponse {
        let body = CreateCommentRequest(
            content: content,
            type: type.rawValue,
            fileId: fileId,
            parentCommentId: parentCommentId,
            createdAt: createdAt,
            clientRequestId: clientRequestId
        )

        return try await request(
            method: "POST",
            path: "/api/v1/tasks/\(taskId)/comments",
            body: body
        )
    }

    /// Update a comment
    func updateComment(commentId: String, content: String) async throws -> CommentResponse {
        let body = UpdateCommentRequest(content: content)

        return try await request(
            method: "PUT",
            path: "/api/v1/comments/\(commentId)",
            body: body
        )
    }

    /// Delete a comment
    func deleteComment(commentId: String) async throws -> DeleteResponse {
        return try await request(
            method: "DELETE",
            path: "/api/v1/comments/\(commentId)"
        )
    }

    // MARK: - User Settings

    /// Get current user's settings
    func getUserSettings() async throws -> UserSettingsResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/users/me/settings"
        )
    }

    /// Update current user's settings
    func updateUserSettings(reminderSettings: ReminderSettingsUpdate) async throws -> UserSettingsResponse {
        struct UpdateSettingsRequest: Codable {
            let reminderSettings: ReminderSettingsUpdate
        }

        let body = UpdateSettingsRequest(reminderSettings: reminderSettings)

        return try await request(
            method: "PUT",
            path: "/api/v1/users/me/settings",
            body: body
        )
    }

    // MARK: - User Preferences (app-level settings)
    //
    // These target `/api/v1/users/me/smart-tasks` and
    // `/api/v1/users/me/my-tasks-preferences`, distinct from
    // `/api/v1/users/me/settings` above (used for reminder settings). Do not
    // merge them — they hold different fields. Keep iOS and web aligned by
    // using the same Codable shape the web returns.

    /// Fetch the user's "smart task" settings (smart creation, email-to-task,
    /// default due offset, default due time).
    func getSmartTaskSettings() async throws -> UserSettings {
        return try await request(
            method: "GET",
            path: "/api/v1/users/me/smart-tasks"
        )
    }

    /// Patch the user's smart-task settings. Accepts the merged struct; only
    /// non-nil fields are sent by virtue of Codable optional encoding rules.
    func updateSmartTaskSettings(_ settings: UserSettings) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            method: "PATCH",
            path: "/api/v1/users/me/smart-tasks",
            body: settings
        )
    }

    /// Fetch the user's My Tasks filter/sort preferences.
    func getMyTasksPreferences() async throws -> MyTasksPreferences {
        return try await request(
            method: "GET",
            path: "/api/v1/users/me/my-tasks-preferences"
        )
    }

    /// Patch the user's My Tasks preferences.
    func updateMyTasksPreferences(_ preferences: MyTasksPreferences) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            method: "PATCH",
            path: "/api/v1/users/me/my-tasks-preferences",
            body: preferences
        )
    }

    // MARK: - User Search

    /// Search for users with AI agents included (based on user's configured API keys)
    /// - Parameters:
    ///   - query: Search query string (can be empty to get all AI agents)
    ///   - taskId: Optional task ID to filter by task's lists
    ///   - listIds: Optional list IDs to filter members
    /// - Returns: Array of User objects including AI agents with profile photos
    func searchUsersWithAIAgents(query: String, taskId: String?, listIds: [String]?) async throws -> [User] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "includeAIAgents", value: "true")
        ]

        if let taskId = taskId {
            queryItems.append(URLQueryItem(name: "taskId", value: taskId))
        }

        if let listIds = listIds, !listIds.isEmpty {
            queryItems.append(URLQueryItem(name: "listIds", value: listIds.joined(separator: ",")))
        }

        let response: UserSearchResponse = try await request(
            method: "GET",
            path: "/api/v1/users/search",
            queryItems: queryItems
        )

        return response.users
    }

    // MARK: - List Members

    /// Get all members of a list
    func getListMembers(listId: String) async throws -> ListMembersResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/lists/\(listId)/members"
        )
    }

    /// Add a member to a list
    func addListMember(listId: String, email: String, role: String = "member") async throws -> AddMemberResponse {
        struct AddMemberRequest: Codable {
            let email: String
            let role: String
        }

        let body = AddMemberRequest(email: email, role: role)

        return try await request(
            method: "POST",
            path: "/api/v1/lists/\(listId)/members",
            body: body
        )
    }

    /// Update a member's role
    func updateListMember(listId: String, userId: String, role: String) async throws -> UpdateMemberResponse {
        struct UpdateMemberRoleRequest: Codable {
            let role: String
        }

        let body = UpdateMemberRoleRequest(role: role)

        return try await request(
            method: "PUT",
            path: "/api/v1/lists/\(listId)/members/\(userId)",
            body: body
        )
    }

    /// Remove a member from a list
    func removeListMember(listId: String, userId: String) async throws -> DeleteResponse {
        return try await request(
            method: "DELETE",
            path: "/api/v1/lists/\(listId)/members/\(userId)"
        )
    }

    /// Cancel a pending invitation
    func cancelInvitation(listId: String, email: String) async throws -> DeleteResponse {
        struct CancelInvitationRequest: Codable {
            let email: String
        }
        return try await request(
            method: "DELETE",
            path: "/api/v1/lists/\(listId)/invitations",
            body: CancelInvitationRequest(email: email)
        )
    }

    // MARK: - Public Lists

    /// Get public lists
    func getPublicLists(limit: Int = 50, sortBy: String = "popular") async throws -> PublicListsResponse {
        let queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sortBy", value: sortBy)
        ]

        return try await request(
            method: "GET",
            path: "/api/v1/public/lists",
            queryItems: queryItems
        )
    }

    /// Copy a public list to your account
    func copyList(listId: String, includeTasks: Bool = true) async throws -> CopyListResponse {
        struct CopyListRequest: Codable {
            let includeTasks: Bool
        }

        let body = CopyListRequest(includeTasks: includeTasks)

        return try await request(
            method: "POST",
            path: "/api/v1/lists/\(listId)/copy",
            body: body
        )
    }

    // MARK: - Contacts (Address Book)

    /// Upload/sync contacts from device address book
    func uploadContacts(contacts: [DeviceContact], replaceAll: Bool = true) async throws -> ContactSyncResult {
        struct UploadContactsRequest: Codable {
            let contacts: [DeviceContact]
            let replaceAll: Bool
        }

        let body = UploadContactsRequest(contacts: contacts, replaceAll: replaceAll)

        return try await request(
            method: "POST",
            path: "/api/v1/contacts",
            body: body
        )
    }

    /// Get current contact sync status (count of synced contacts)
    func getContactStatus() async throws -> ContactStatusResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/contacts",
            queryItems: [URLQueryItem(name: "limit", value: "1")] // Only need the count, not all contacts
        )
    }

    /// Search contacts for autocomplete when adding list members
    func searchContacts(query: String, excludeListId: String? = nil, limit: Int = 10) async throws -> [ContactSearchResult] {
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        if let excludeListId = excludeListId {
            queryItems.append(URLQueryItem(name: "excludeListId", value: excludeListId))
        }

        let response: ContactSearchResponse = try await request(
            method: "GET",
            path: "/api/v1/contacts/search",
            queryItems: queryItems
        )
        return response.results
    }

    /// Get recommended collaborators based on mutual address book presence
    func getRecommendedCollaborators(excludeListId: String? = nil, limit: Int = 20) async throws -> [RecommendedCollaborator] {
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        if let excludeListId = excludeListId {
            queryItems.append(URLQueryItem(name: "excludeListId", value: excludeListId))
        }

        let response: RecommendedCollaboratorsResponse = try await request(
            method: "GET",
            path: "/api/v1/contacts/recommended",
            queryItems: queryItems
        )
        return response.recommended
    }

    // MARK: - AI API Key Management

    /// Get user's AI API keys status (without revealing actual keys)
    func getAIAPIKeys() async throws -> AIAPIKeysResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/users/me/ai-credentials"
        )
    }

    /// Save an AI API key for a service
    func saveAIAPIKey(serviceId: String, apiKey: String) async throws -> SaveAPIKeyResponse {
        struct SaveAPIKeyRequest: Codable {
            let serviceId: String
            let apiKey: String
        }

        let body = SaveAPIKeyRequest(serviceId: serviceId, apiKey: apiKey)

        return try await request(
            method: "PUT",
            path: "/api/v1/users/me/ai-credentials",
            body: body
        )
    }

    /// Test an AI API key
    func testAIAPIKey(serviceId: String) async throws -> TestAPIKeyResponse {
        struct TestAPIKeyRequest: Codable {
            let serviceId: String
        }

        let body = TestAPIKeyRequest(serviceId: serviceId)

        return try await request(
            method: "POST",
            path: "/api/v1/users/me/ai-credentials/test",
            body: body
        )
    }

    /// Delete an AI API key
    func deleteAIAPIKey(serviceId: String) async throws -> DeleteAPIKeyResponse {
        struct DeleteAPIKeyRequest: Codable {
            let serviceId: String
        }

        let body = DeleteAPIKeyRequest(serviceId: serviceId)

        return try await request(
            method: "DELETE",
            path: "/api/v1/users/me/ai-credentials",
            body: body
        )
    }

    // MARK: - OpenClaw Agents

    /// Get user's OpenClaw agents
    func getOpenClawAgents() async throws -> [OpenClawAgent] {
        let response: OpenClawAgentsResponse = try await request(
            method: "GET",
            path: "/api/v1/openclaw/agents"
        )
        return response.agents
    }

    /// Register a new OpenClaw agent
    func registerOpenClawAgent(name: String) async throws -> OpenClawRegistrationResult {
        struct RegisterRequest: Codable { let agentName: String }
        let body = RegisterRequest(agentName: name)
        return try await request(
            method: "POST",
            path: "/api/v1/openclaw/register",
            body: body
        )
    }

    /// Delete an OpenClaw agent
    func deleteOpenClawAgent(id: String) async throws {
        struct DeleteResponse: Codable { let success: Bool? }
        let _: DeleteResponse = try await request(
            method: "DELETE",
            path: "/api/v1/openclaw/agents/\(id)"
        )
    }

    // MARK: - Chat Channels

    /// Get or create a chat channel for a list
    func getOrCreateChatChannel(listId: String) async throws -> ChatChannel {
        let body = CreateChatChannelRequest(listId: listId)
        let response: ChatChannelResponse = try await request(
            method: "POST",
            path: "/api/v1/chat/channels",
            body: body
        )
        return response.channel
    }

    /// Get or create a virtual chat channel
    func getOrCreateVirtualChannel(virtualKey: String) async throws -> ChatChannel {
        let body = CreateChatChannelRequest(virtualKey: virtualKey)
        let response: ChatChannelResponse = try await request(
            method: "POST",
            path: "/api/v1/chat/channels",
            body: body
        )
        return response.channel
    }

    // MARK: - Chat Messages

    /// Get paginated messages for a channel (cursor-based, newest first)
    func getChatMessages(channelId: String, before: Date? = nil, limit: Int = 50) async throws -> ChatMessagesResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let before = before {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "before", value: formatter.string(from: before)))
        }
        return try await request(
            method: "GET",
            path: "/api/v1/chat/channels/\(channelId)/messages",
            queryItems: queryItems
        )
    }

    /// Send a message to a channel
    func sendChatMessage(
        channelId: String,
        content: String,
        type: Comment.CommentType = .TEXT,
        fileId: String? = nil,
        attachmentUrl: String? = nil,
        attachmentName: String? = nil,
        attachmentType: String? = nil,
        attachmentSize: Int? = nil,
        replyToId: String? = nil,
        clientRequestId: String? = nil
    ) async throws -> ChatMessage {
        let body = CreateChatMessageRequest(
            content: content,
            type: type.rawValue,
            fileId: fileId,
            attachmentUrl: attachmentUrl,
            attachmentName: attachmentName,
            attachmentType: attachmentType,
            attachmentSize: attachmentSize,
            replyToId: replyToId,
            clientRequestId: clientRequestId
        )
        let response: ChatMessageResponse = try await request(
            method: "POST",
            path: "/api/v1/chat/channels/\(channelId)/messages",
            body: body
        )
        return response.message
    }

    // MARK: - On-Device Agent Response

    /// Post a response from the on-device AI model as Astrid
    func postAgentResponse(channelId: String, content: String) async throws {
        struct AgentResponseBody: Encodable {
            let content: String
        }
        let _: ChatMessageResponse = try await request(
            method: "POST",
            path: "/api/v1/chat/channels/\(channelId)/agent-response",
            body: AgentResponseBody(content: content)
        )
    }

    // MARK: - AI Agent Settings

    /// Get available AI agents for the current user
    func getAvailableAgents() async throws -> [AvailableAgent] {
        let response: AvailableAgentsResponse = try await request(
            method: "GET",
            path: "/api/v1/users/me/available-agents"
        )
        return response.agents
    }

    /// Get current user's AI assistant settings
    func getAIAssistantSettings() async throws -> AIAssistantSettings {
        let response: AIAssistantSettingsResponse = try await request(
            method: "GET",
            path: "/api/v1/users/me/ai-preferences"
        )
        return AIAssistantSettings(
            defaultAgentId: response.defaultAgentId,
            preferredService: response.preferredService
        )
    }

    /// Update AI assistant settings (default agent, preferred service)
    func updateAIAssistantSettings(
        defaultAgentId: String? = nil,
        preferredService: String? = nil
    ) async throws -> AIAssistantSettings {
        let body = UpdateAIAssistantSettingsRequest(
            defaultAgentId: defaultAgentId,
            preferredService: preferredService
        )
        let response: AIAssistantSettingsResponse = try await request(
            method: "PATCH",
            path: "/api/v1/users/me/ai-preferences",
            body: body
        )
        return AIAssistantSettings(
            defaultAgentId: response.defaultAgentId,
            preferredService: response.preferredService
        )
    }

    /// Get available models for a service (claude, openai, gemini)
    func getAvailableModels(service: String) async throws -> [String] {
        let response: AvailableModelsResponse = try await request(
            method: "GET",
            path: "/api/v1/users/me/available-models",
            queryItems: [URLQueryItem(name: "service", value: service)]
        )
        return response.models
    }

    // MARK: - Account Management

    /// Get current user's account data
    func getAccount() async throws -> AccountData {
        let response: AccountResponse = try await request(
            method: "GET",
            path: "/api/v1/users/me"
        )
        return response.user
    }

    /// Update account (name, email, image)
    func updateAccount(name: String? = nil, email: String? = nil, image: String? = nil) async throws -> UpdateAccountResponse {
        struct UpdateRequest: Codable {
            var name: String?
            var email: String?
            var image: String?
        }

        let body = UpdateRequest(name: name, email: email, image: image)

        return try await request(
            method: "PUT",
            path: "/api/v1/users/me",
            body: body
        )
    }

    /// Send, resend, or cancel email verification
    /// - Parameter action: "send", "resend", or "cancel"
    func verifyEmail(action: String) async throws -> VerifyEmailResponse {
        return try await request(
            method: "POST",
            path: "/api/v1/users/me/verify-email",
            queryItems: [URLQueryItem(name: "action", value: action)]
        )
    }

    /// Delete account permanently
    /// - Parameter confirmationText: Must be "DELETE MY ACCOUNT"
    func deleteAccount(confirmationText: String) async throws -> DeleteAccountResponse {
        struct DeleteAccountBody: Codable {
            let confirmationText: String
        }

        let body = DeleteAccountBody(confirmationText: confirmationText)

        return try await request(
            method: "POST",
            path: "/api/v1/users/me/delete",
            body: body
        )
    }

    /// Export account data
    /// - Parameter format: "json" or "csv"
    /// - Returns: Raw data of the export file
    func exportAccountData(format: String) async throws -> Data {
        // Build URL with query parameters
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent("/api/v1/users/me/export"), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "format", value: format)]

        guard let url = urlComponents?.url else {
            throw AstridAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use session cookie authentication
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AstridAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AstridAPIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let responseString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AstridAPIError.httpError(statusCode: httpResponse.statusCode, message: responseString)
        }

        return data
    }
}

// MARK: - Contacts Response Types

struct ContactSearchResponse: Codable {
    let results: [ContactSearchResult]
    let meta: MetaInfo
}

struct RecommendedCollaboratorsResponse: Codable {
    let recommended: [RecommendedCollaborator]
    let stats: RecommendedCollaboratorsStats?
    let message: String?
    let meta: MetaInfo
}

struct RecommendedCollaboratorsStats: Codable {
    let mutual: Int
    let nonMutual: Int
    let total: Int
}

/// Response from GET /api/v1/contacts
struct ContactStatusResponse: Codable {
    let pagination: ContactPagination
}

struct ContactPagination: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

// MARK: - Response DTOs (Non-duplicates only - others in APIModels.swift)

struct TaskResponse: Codable {
    let task: Task
}

struct ListResponse: Codable {
    let list: TaskList
}

struct UpdateCommentRequest: Codable {
    let content: String
}

// MARK: - User Settings Types

struct UserSettingsResponse: Codable {
    let settings: UserSettingsData
    let meta: MetaInfo
}

struct UserSettingsData: Codable {
    let reminderSettings: ReminderSettingsData
}

struct ReminderSettingsData: Codable {
    let enablePushReminders: Bool
    let enableEmailReminders: Bool
    let defaultReminderTime: Int
    let enableDailyDigest: Bool
    let dailyDigestTime: String
    let dailyDigestTimezone: String
    let quietHoursStart: String?
    let quietHoursEnd: String?
}

struct ReminderSettingsUpdate: Codable {
    let enablePushReminders: Bool
    let enableEmailReminders: Bool
    let defaultReminderTime: Int
    let enableDailyDigest: Bool
    let dailyDigestTime: String
    let dailyDigestTimezone: String
    let quietHoursStart: String?
    let quietHoursEnd: String?
}

// MARK: - List Member Types

struct ListMembersResponse: Codable {
    let members: [ListMemberData]
    let meta: MetaInfo
}

struct ListMemberData: Codable {
    let id: String
    let name: String?
    let email: String
    let image: String?
    let role: String
    let isOwner: Bool
    let isAdmin: Bool
    var type: String? = nil  // "member" or "invite" — invite entries have id prefixed with "invite_"
}

struct AddMemberResponse: Codable {
    let message: String
    let member: ListMemberData?  // nil when invitation is sent to non-existing user
    let invitation: InvitationData?  // Present when user doesn't exist yet
    let meta: MetaInfo
}

struct InvitationData: Codable {
    let email: String
    let role: String
    let status: String
}

struct UpdateMemberResponse: Codable {
    let message: String
    let member: ListMemberData
    let meta: MetaInfo
}

// MARK: - Public List Types

struct PublicListsResponse: Codable {
    let lists: [PublicListData]
    let meta: PublicListMeta
}

struct PublicListData: Codable {
    let id: String
    let name: String
    let description: String?
    let color: String?
    let privacy: String
    let publicListType: String?
    let imageUrl: String?
    let createdAt: Date
    let updatedAt: Date
    let owner: UserData
    let admins: [UserData]?
    let taskCount: Int
    let memberCount: Int
}

struct UserData: Codable {
    let id: String
    let name: String?
    let email: String?  // Optional: admins in public lists may not include email
    let image: String?
}

struct PublicListMeta: Codable {
    let apiVersion: String?
    let authSource: String?
    let count: Int
    let sortBy: String
}

struct CopyListResponse: Codable {
    let message: String
    let list: TaskList
    let copiedTasksCount: Int
    let meta: MetaInfo
}

// MARK: - Shortcode Types

struct CreateShortcodeRequest: Codable {
    let targetType: String  // "task" or "list"
    let targetId: String
}

struct ShortcodeData: Codable {
    let id: String
    let code: String
    let targetType: String
    let targetId: String
    let userId: String
    let createdAt: Date
    let expiresAt: Date?
}

struct ShortcodeResponse: Codable {
    let shortcode: ShortcodeData
    let url: String
}

// Note: MetaInfo is defined in CommentService.swift

// MARK: - AI API Keys Types

struct AIAPIKeysResponse: Codable {
    let keys: [String: AIAPIKeyStatus]
}

struct AIAPIKeyStatus: Codable {
    let hasKey: Bool
    let keyPreview: String?
    let isValid: Bool?
    let lastTested: String?
    let error: String?
}

struct SaveAPIKeyResponse: Codable {
    let success: Bool
}

struct TestAPIKeyResponse: Codable {
    let success: Bool
    let error: String?
}

struct DeleteAPIKeyResponse: Codable {
    let success: Bool
}

// MARK: - OpenClaw Agent Types

struct OpenClawAgent: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let image: String?
    let agentName: String
    let status: String          // "active" or "idle"
    let registeredAt: String
    let lastActiveAt: String?
    let oauthClientId: String?
}

struct OpenClawAgentsResponse: Codable {
    let agents: [OpenClawAgent]
}

struct OpenClawRegistrationAgent: Codable {
    let id: String
    let email: String
    let name: String
    let aiAgentType: String
}

struct OpenClawRegistrationOAuth: Codable {
    let clientId: String
    let clientSecret: String
    let scopes: [String]
}

struct OpenClawRegistrationConfig: Codable {
    let sseEndpoint: String
    let apiBase: String
    let tokenEndpoint: String
}

struct OpenClawRegistrationResult: Codable {
    let agent: OpenClawRegistrationAgent
    let oauth: OpenClawRegistrationOAuth
    let config: OpenClawRegistrationConfig
}

// MARK: - Client Error Type

enum AstridAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
