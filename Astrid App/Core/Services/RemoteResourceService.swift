import Foundation

/// Canonical service facade for the remaining backend-backed resources that the
/// settings / list-admin / picker screens consume: user reminder settings, AI
/// API keys, OpenClaw agents, shortcodes, public-list discovery/copy, user &
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

    // MARK: - AI API keys

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

    // MARK: - OpenClaw agents

    func getOpenClawAgents() async throws -> [OpenClawAgent] {
        try await apiClient.getOpenClawAgents()
    }

    func registerOpenClawAgent(name: String) async throws -> OpenClawRegistrationResult {
        try await apiClient.registerOpenClawAgent(name: name)
    }

    func deleteOpenClawAgent(id: String) async throws {
        try await apiClient.deleteOpenClawAgent(id: id)
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
