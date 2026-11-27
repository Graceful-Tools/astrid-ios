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

    private convenience init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.API.timeout
        configuration.timeoutIntervalForResource = Constants.API.timeout
        // Enable cookie handling (required for session authentication)
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        // UI tests get an ephemeral, cookie-less session so they can never authenticate as the
        // real user through the shared cookie jar (see UITestNetworkIsolation).
        self.init(session: URLSession(configuration: UITestNetworkIsolation.harden(configuration)))
    }

    /// A client sending through `session`. The app uses `shared`; tests pass a session whose
    /// protocol stub answers instead of the server (AITD-535).
    init(session: URLSession) {
        self.session = session

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

    func request<T: Codable>(
        method: String,
        path: String,
        body: Encodable? = nil,
        rawBody: (data: Data, contentType: String)? = nil,
        queryItems: [URLQueryItem]? = nil,
        capturesSession: Bool = false
    ) async throws -> T {
        // Security backstop (audit 2026-07-25): ids reach these paths from deep links, and a
        // percent-encoded separator used to survive into the request — `astrid://tasks/a%2F..%2Fadmin`
        // built `/api/v1/tasks/a/../admin`, which a server normalizes to a different endpoint and
        // executes with the user's session. Refuse to send any path containing traversal segments.
        guard APIPathSafety.isSafeRequestPath(path) else {
            throw AstridAPIError.invalidURL
        }

        // Build URL with query parameters
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AstridAPIError.invalidURL
        }

        PrivacyLogger.request("AstridAPI", method: method, url: url)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Say which app this is (task 119cabc3). The server reads this BEFORE it tries to
        // recognise the user agent, which it could not do reliably.
        request.setValue(AnalyticsPlatformHeader.current,
                         forHTTPHeaderField: AnalyticsPlatformHeader.headerName)

        // Use session cookie authentication (same as existing APIClient)
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            AppLog.debug("🍪 [AstridAPI] Using session cookie authentication")
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            AppLog.debug("⚠️ [AstridAPI] No session cookie available - API calls may fail")
        }

        // Add body if present
        if let body = body {
            request.httpBody = try encoder.encode(body)
        } else if let rawBody {
            request.httpBody = rawBody.data
            request.setValue(rawBody.contentType, forHTTPHeaderField: "Content-Type")
        }

        AppLog.debug("🔄 [AstridAPI] Waiting for response...")
        let (data, response): (Data, URLResponse)
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch let urlError as URLError {
            PrivacyLogger.error("AstridAPI", code: "url_\(urlError.code.rawValue)")
            throw urlError
        } catch {
            PrivacyLogger.error("AstridAPI", code: "transport_error")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AppLog.debug("❌ [AstridAPI] Invalid response (not HTTP)")
            throw AstridAPIError.invalidResponse
        }

        PrivacyLogger.response("AstridAPI", status: httpResponse.statusCode, bytes: data.count)
        // Sign-in hands its session back as Set-Cookie (AITD-504, see SessionCookieCapture).
        if capturesSession { SessionCookieCapture.save(from: httpResponse) }

        // Handle error responses
        if httpResponse.statusCode == 401 {
            AppLog.debug("❌ [AstridAPI] Unauthorized (401)")
            throw AstridAPIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            PrivacyLogger.error("AstridAPI", code: "http_error", status: httpResponse.statusCode)
            throw AstridAPIError.httpError(statusCode: httpResponse.statusCode, message: responseString)
        }

        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }

        // Decode response
        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            PrivacyLogger.error("AstridAPI", code: "decoding_error", status: httpResponse.statusCode)
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
        // Security backstop (audit 2026-07-25): ids reach these paths from deep links, and a
        // percent-encoded separator used to survive into the request — `astrid://tasks/a%2F..%2Fadmin`
        // built `/api/v1/tasks/a/../admin`, which a server normalizes to a different endpoint and
        // executes with the user's session. Refuse to send any path containing traversal segments.
        guard APIPathSafety.isSafeRequestPath(path) else {
            throw AstridAPIError.invalidURL
        }

        // Build URL with query parameters
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw AstridAPIError.invalidURL
        }

        PrivacyLogger.request("AstridAPI", method: method, url: url)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Say which app this is (task 119cabc3). The server reads this BEFORE it tries to
        // recognise the user agent, which it could not do reliably.
        request.setValue(AnalyticsPlatformHeader.current,
                         forHTTPHeaderField: AnalyticsPlatformHeader.headerName)

        // Use session cookie authentication
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            AppLog.debug("🍪 [AstridAPI] Using session cookie authentication")
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            AppLog.debug("⚠️ [AstridAPI] No session cookie available - API calls may fail")
        }

        // Encode body using JSONSerialization (properly handles NSNull as null)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        AppLog.debug("🔄 [AstridAPI] Waiting for response...")
        let (data, response): (Data, URLResponse)
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch let urlError as URLError {
            PrivacyLogger.error("AstridAPI", code: "url_\(urlError.code.rawValue)")
            throw AstridAPIError.httpError(statusCode: urlError.code.rawValue, message: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AstridAPIError.invalidResponse
        }

        PrivacyLogger.response("AstridAPI", status: httpResponse.statusCode, bytes: data.count)

        // Handle non-2xx responses
        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            PrivacyLogger.error("AstridAPI", code: "http_error", status: httpResponse.statusCode)
            throw AstridAPIError.httpError(statusCode: httpResponse.statusCode, message: responseString)
        }

        // Decode response
        do {
            let result = try decoder.decode(T.self, from: data)
            return result
        } catch {
            PrivacyLogger.error("AstridAPI", code: "decoding_error", status: httpResponse.statusCode)
            throw AstridAPIError.decodingError(error)
        }
    }

    // MARK: - App Version (AITD-383)

    /// The latest shipped version for a platform.
    ///
    /// `/api/v1/...` per ASTRID.md rule 5. Callers must treat every failure as "unknown" rather
    /// than as an error worth showing: this endpoint post-dates the clients that call it.
    func getAppVersion(platform: String) async throws -> AppVersionResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/app-version",
            queryItems: [URLQueryItem(name: "platform", value: platform)]
        )
    }

    /// The hi-fi empathy-state art manifest (ADEV-127; served since astrid-web ADEV-142).
    /// Public and cacheable; the frames it names are fetched by `EmpathyArtService`.
    func getEmpathyArtManifest() async throws -> EmpathyArtManifest {
        return try await request(method: "GET", path: "/api/v1/empathy-art")
    }

    // MARK: - Project goals and guardrails (ADEV-183, web ADEV-179)

    /// A project's goals and guardrails, and whether this person may edit them. Called only by
    /// `ProjectGoalsService`.
    func getProjectGoals(projectId: String) async throws -> ProjectGoals {
        try await request(method: "GET", path: "/api/v1/projects/\(projectId)/goals")
    }

    /// Replace a project's goals and guardrails (owner or admin). The server normalises.
    func putProjectGoals(projectId: String, _ update: ProjectGoalsUpdate) async throws -> ProjectGoals {
        try await request(method: "PUT", path: "/api/v1/projects/\(projectId)/goals", body: update)
    }

    /// A list's orchestration policy, for whether a trade-off policy applies (ADEV-321).
    func getListOrchestrationPolicy(listId: String) async throws -> ListOrchestrationPolicy {
        try await request(method: "GET", path: "/api/v1/lists/\(listId)/orchestration-policy")
    }

    // MARK: - Task Operations

    // A public list's tasks were the last read of `/api/v1/tasks`; they come from the core's
    // `featuredRows` now (AITD-634), so `getTasks`/`getAllTasks` went with them.

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

    // MARK: - User Settings

    /// Get current user's settings
    func getUserSettings() async throws -> UserSettingsResponse {
        return try await request(
            method: "GET",
            path: "/api/v1/users/me/settings"
        )
    }

    /// Tell the server which language the user reads, for pushes and reminder emails (AITD-663,
    /// astrid-web AWTD-1592). A top-level `locale` beside `reminderSettings`, which this sends
    /// alone so it changes nothing else. `null` would forget it; the app never sends that.
    func updateUserLocale(_ locale: String) async throws -> UserSettingsResponse {
        try await request(
            method: "PUT",
            path: "/api/v1/users/me/settings",
            body: UpdateUserLocaleRequest(locale: locale)
        )
    }

    // MARK: - Copilot cloud agent token

    /// Mint the user-level MCP token the GitHub.com Copilot coding agent authenticates with.
    /// Not a v1 path: this is the same route the web setup card calls (AITD-297).
    func createCopilotCloudAgentToken() async throws -> MCPUserTokenResponse {
        try await request(method: "POST", path: "/api/mcp/user-tokens", body: MCPUserTokenRequest.copilotCloudAgent)
    }

    // MARK: - AI Agent Settings

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
}

// MARK: - List Member Types

struct ListMembersResponse: Codable {
    let members: [ListMemberData]
    /// The caller's relationship to this list (Task 4a338b53). "viewer" means a non-member looking
    /// at a PUBLIC list: `members` comes back EMPTY rather than 403, because the payload carries
    /// email addresses. Without this an empty array is ambiguous — see `ListMemberVisibility`.
    /// Optional because older servers and other routes do not send it.
    let userRole: String?
    let meta: MetaInfo

    enum CodingKeys: String, CodingKey {
        case members
        case userRole = "user_role"
        case meta
    }
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

// MARK: - Public List Types

/// One row of the public-list catalogue, as astrid-core answers `publicLists`
/// (`services/list.rs` `PublicListSummary`, AITD-620). The core reads no `privacy`, dates or
/// `admins` from the server, and its owner has no photo; they stay optional here so the older,
/// fuller rows still decode.
struct PublicListData: Codable {
    let id: String
    let name: String
    let description: String?
    let color: String?
    /// Absent from the core's row: every row of the catalogue is public.
    let privacy: String?
    let publicListType: String?
    let imageUrl: String?
    let createdAt: Date?
    let updatedAt: Date?
    let owner: UserData?
    let admins: [UserData]?
    let taskCount: Int?
    let memberCount: Int?
}

struct UserData: Codable {
    let id: String
    let name: String?
    let email: String?  // Optional: admins in public lists may not include email
    let image: String?
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

struct TestAPIKeyResponse: Codable, Equatable {
    let success: Bool
    let error: String?

    init(success: Bool, error: String?) {
        self.success = success
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case success, works, error }

    /// astrid-core's `testAgentCredential` answers `{ works, error }`; the route said `success`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .works)
            ?? container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(error, forKey: .error)
    }
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
