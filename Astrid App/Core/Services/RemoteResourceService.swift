import Foundation

/// Canonical service facade for the remaining backend-backed resources that the
/// settings / list-admin / picker screens consume: user reminder settings, AI
/// API keys, Custom Agents, webhook settings, shortcodes, public-list discovery/copy, user &
/// agent search, and Google/GitHub integration discovery.
///
/// Per the canonical control points in CLAUDE.md, UI must not call
/// `AstridAPIClient` / `APIClient` directly. Routing these calls through a
/// single facade keeps the service boundary enforceable by
/// `UIServiceBoundaryGuardTests` and gives us one place to add caching or
/// offline handling later.
///
/// Method names and signatures mirror the underlying client exactly so this is
/// a behavior-preserving passthrough.
final class RemoteResourceService {
    static let shared = RemoteResourceService()

    private let apiClient = AstridAPIClient.shared
    private let legacyClient = APIClient.shared

    private init() {}

    // MARK: - User settings

    func getUserSettings() async throws -> UserSettingsResponse {
        try await apiClient.getUserSettings()
    }

    func updateUserSettings(reminderSettings: ReminderSettingsUpdate) async throws -> UserSettingsResponse {
        try await apiClient.updateUserSettings(reminderSettings: reminderSettings)
    }

    // MARK: - AI agents and API keys

    func getAgentModes() async throws -> AgentModesResponse {
        try await apiClient.getAgentModes()
    }

    func updateAgentMode(agent: String, mode: AgentExecutionMode) async throws -> AgentModesResponse {
        try await apiClient.updateAgentMode(agent: agent, mode: mode)
    }

    func getCopilotIntegrationStatus() async throws -> CopilotIntegrationStatus {
        try await apiClient.getCopilotIntegrationStatus()
    }

    func getCopilotAuthorization() async throws -> CopilotAuthorizationResponse {
        try await apiClient.getCopilotAuthorization()
    }

    func disconnectCopilot() async throws -> CopilotIntegrationStatus {
        try await apiClient.disconnectCopilot()
    }

    func getAIAPIKeys() async throws -> AIAPIKeysResponse {
        try await apiClient.getAIAPIKeys()
    }

    func saveAIAPIKey(serviceId: String, apiKey: String) async throws -> SaveAPIKeyResponse {
        try await apiClient.saveAIAPIKey(serviceId: serviceId, apiKey: apiKey)
    }

    func testAIAPIKey(serviceId: String) async throws -> TestAPIKeyResponse {
        try await apiClient.testAIAPIKey(serviceId: serviceId)
    }

    func deleteAIAPIKey(serviceId: String) async throws -> DeleteAPIKeyResponse {
        try await apiClient.deleteAIAPIKey(serviceId: serviceId)
    }

    // MARK: - Custom Agents

    func getCustomAgents() async throws -> [CustomAgent] {
        try await apiClient.getCustomAgents()
    }

    func registerCustomAgent(name: String, listIds: [String]? = nil) async throws -> CustomAgentRegistrationResult {
        try await apiClient.registerCustomAgent(name: name, listIds: listIds)
    }

    func updateCustomAgent(id: String, image: String?) async throws -> CustomAgentUpdateResponse {
        try await apiClient.updateCustomAgent(id: id, image: image)
    }

    func deleteCustomAgent(id: String) async throws {
        try await apiClient.deleteCustomAgent(id: id)
    }

    func createCopilotCloudAgentToken() async throws -> MCPUserTokenResponse {
        try await apiClient.createCopilotCloudAgentToken()
    }

    // MARK: - Webhook transport

    func getWebhookSettings() async throws -> WebhookSettings {
        try await apiClient.getWebhookSettings()
    }

    func updateWebhookSettings(_ request: UpdateWebhookSettingsRequest) async throws -> WebhookSettingsSaveResponse {
        try await apiClient.updateWebhookSettings(request)
    }

    func deleteWebhookSettings() async throws -> WebhookDeleteResponse {
        try await apiClient.deleteWebhookSettings()
    }

    func testWebhook() async throws -> WebhookTestResult {
        try await apiClient.testWebhook()
    }

    // MARK: - Shortcodes

    func createShortcode(targetType: String, targetId: String) async throws -> ShortcodeResponse {
        try await apiClient.createShortcode(targetType: targetType, targetId: targetId)
    }

    // MARK: - Public lists

    func getPublicLists(limit: Int = 50, sortBy: String = "popular") async throws -> PublicListsResponse {
        try await apiClient.getPublicLists(limit: limit, sortBy: sortBy)
    }

    func copyList(listId: String, includeTasks: Bool = true) async throws -> CopyListResponse {
        try await apiClient.copyList(listId: listId, includeTasks: includeTasks)
    }

    // MARK: - User & agent search

    func searchUsersWithAIAgents(query: String, taskId: String?, listIds: [String]?) async throws -> [User] {
        try await legacyClient.searchUsersWithAIAgents(query: query, taskId: taskId, listIds: listIds)
    }

    // MARK: - Integration discovery (Google Tasks / GitHub)

    func getGoogleTasklists() async throws -> GoogleTasklistsResponse {
        try await apiClient.getGoogleTasklists()
    }

    func getGitHubRepos() async throws -> GitHubReposResponse {
        try await apiClient.getGitHubRepos()
    }

    func getGitHubStatus() async throws -> GitHubStatusResponse {
        try await apiClient.getGitHubStatus()
    }

    func getGitHubRepositories(refresh: Bool = false) async throws -> GitHubRepositoriesResponse {
        try await apiClient.getGitHubRepositories(refresh: refresh)
    }
}
