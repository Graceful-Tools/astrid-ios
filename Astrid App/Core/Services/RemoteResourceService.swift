import AstridCore
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

    private init() {}

    // MARK: - User settings

    func getUserSettings() async throws -> UserSettingsResponse {
        try await apiClient.getUserSettings()
    }

    // MARK: - App version (AITD-383)

    func getAppVersion(platform: String) async throws -> AppVersionResponse {
        try await apiClient.getAppVersion(platform: platform)
    }

    // MARK: - AI agents and API keys

    func getAgentModes() async throws -> AgentModesResponse {
        try await core.run(CopilotCommands.modes(), as: AgentModesResponse.self)
    }

    func updateAgentMode(agent: String, mode: AgentExecutionMode) async throws -> AgentModesResponse {
        try await core.run(CopilotCommands.setMode(UpdateAgentModeRequest(agent: agent, mode: mode)),
                           as: AgentModesResponse.self)
    }

    func getCopilotIntegrationStatus() async throws -> CopilotIntegrationStatus {
        try await core.run(CopilotCommands.status(), as: CopilotIntegrationStatus.self)
    }

    // Connect and disconnect go through astrid-core (AITD-620); the status read has no
    // standalone core command yet.
    func getCopilotAuthorization() async throws -> CopilotAuthorizationResponse {
        try await core.run(CopilotCommands.connect(), as: CopilotAuthorizationResponse.self)
    }

    func disconnectCopilot() async throws {
        try await core.run(CopilotCommands.disconnect())
    }

    // The AI keys go through astrid-core (AITD-620, on AWTD-1610's commands). Save and delete
    // answer only "done"; the test answers `{ works, error }` with the server's reason.
    func getAIAPIKeys() async throws -> AIAPIKeysResponse {
        try await core.run(AgentCredentialCommands.list(), as: AIAPIKeysResponse.self)
    }

    func saveAIAPIKey(serviceId: String, apiKey: String) async throws {
        try await core.run(AgentCredentialCommands.save(serviceId: serviceId, key: apiKey))
    }

    func testAIAPIKey(serviceId: String) async throws -> TestAPIKeyResponse {
        try await core.run(AgentCredentialCommands.test(serviceId: serviceId), as: TestAPIKeyResponse.self)
    }

    func deleteAIAPIKey(serviceId: String) async throws {
        try await core.run(AgentCredentialCommands.delete(serviceId: serviceId))
    }

    // MARK: - Custom Agents (through astrid-core, AITD-620)

    func getCustomAgents() async throws -> [CustomAgent] {
        try await core.run(CustomAgentCommands.list(), as: [CustomAgent].self)
    }

    func registerCustomAgent(name: String, listIds: [String]? = nil) async throws -> CustomAgentRegistrationResult {
        try await core.run(CustomAgentCommands.register(name: name, listIds: listIds),
                          as: CustomAgentRegistrationResult.self)
    }

    func updateCustomAgent(id: String, image: String?) async throws -> CustomAgentUpdateResponse {
        try await core.run(CustomAgentCommands.setPhoto(id: id, image: image), as: CustomAgentUpdateResponse.self)
    }

    func deleteCustomAgent(id: String) async throws {
        try await core.run(CustomAgentCommands.delete(id: id))
    }

    func createCopilotCloudAgentToken() async throws -> MCPUserTokenResponse {
        try await apiClient.createCopilotCloudAgentToken()
    }

    // MARK: - Connections (through astrid-core, AITD-620)

    private var core: CoreSession { AppCore.shared.session }

    func getConnections() async throws -> ConnectionsResponse {
        // The core's panel carries the rows themselves beside its grouping; the screen groups
        // them its own way (`ConnectionsModel.sections`), so only the rows are read.
        try await core.run(ConnectionCommands.list(), as: ConnectionsResponse.self)
    }

    func revokeConnection(_ connection: Connection) async throws {
        try await core.run(ConnectionCommands.revoke(connection))
    }

    func createOAuthClient(preset: OAuthClientPreset, agent: String) async throws -> MintedOAuthClient {
        try await core.run(ConnectionCommands.mint(preset: preset, agent: agent), as: MintedOAuthClient.self)
    }

    func getOAuthClient(clientId: String) async throws -> OAuthClientSummary {
        try await core.run(ConnectionCommands.load(clientId: clientId), as: OAuthClientSummary.self)
    }

    func createOAuthClient(_ body: CreateOAuthClientRequest) async throws -> MintedOAuthClient {
        try await core.run(ConnectionCommands.create(body), as: MintedOAuthClient.self)
    }

    func updateOAuthClient(clientId: String, draft: OAuthClientDraft) async throws -> OAuthClientSummary {
        try await core.run(ConnectionCommands.update(clientId: clientId, draft: draft), as: OAuthClientSummary.self)
    }

    // MARK: - Webhook transport (through astrid-core, AITD-620)

    func getWebhookSettings() async throws -> WebhookSettings {
        try await core.run(WebhookCommands.settings(), as: WebhookSettings.self)
    }

    func updateWebhookSettings(_ request: UpdateWebhookSettingsRequest) async throws -> WebhookSettingsSaveResponse {
        try await core.run(WebhookCommands.save(request), as: WebhookSettingsSaveResponse.self)
    }

    func deleteWebhookSettings() async throws {
        try await core.run(WebhookCommands.delete())
    }

    func testWebhook() async throws -> WebhookTestResult {
        try await core.run(WebhookCommands.test(), as: WebhookTestResult.self)
    }

    // MARK: - Share links (through astrid-core, AITD-620)

    /// Mint a share link to a `task` or a `list`.
    func createShortcode(targetType: String, targetId: String) async throws -> ShortcodeResponse {
        try await core.run(try ShortcodeCommands.link(targetType: targetType, targetId: targetId),
                           as: ShortcodeResponse.self)
    }

    /// What `astrid.cc/s/<code>` opens.
    func resolveShortcode(_ code: String) async throws -> ShortcodeResolution {
        try await core.run(ShortcodeCommands.resolve(code: code), as: ShortcodeResolution.self)
    }

    // MARK: - Public lists (through astrid-core, AITD-620)

    /// The catalogue, most copied first. The core always asks the server for the top 50; a
    /// caller that wants fewer (the sidebar) takes the head of that.
    func getPublicLists(limit: Int = 50) async throws -> [PublicListData] {
        let rows = try await core.run(PublicListCommands.catalogue(), as: [PublicListData].self)
        return Array(rows.prefix(limit))
    }

    /// Copy a public list, with its tasks, into this account. Answers the new list, which the
    /// core has already cached.
    @discardableResult
    func copyList(listId: String) async throws -> TaskList {
        try await core.run(PublicListCommands.copy(listId: listId), as: TaskList.self)
    }

    // MARK: - User & agent search

    func searchUsersWithAIAgents(query: String, taskId: String?, listIds: [String]?) async throws -> [User] {
        // Through astrid-core (AITD-620), which also caches the people it finds so names and
        // avatars resolve offline afterwards.
        try await core.run(ContactCommands.searchUsers(query: query, taskId: taskId, listIds: listIds),
                           as: [User].self)
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
