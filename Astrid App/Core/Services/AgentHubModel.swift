//  AgentHubModel.swift
//  State and writes behind the Agent Hub, shared by the iOS and Mac views (AITD-297).
//
//  The views are thin: every rule that could drift between the two platforms — which mode an
//  ownership choice writes, that a write is optimistic and rolls back, what "needs setup" means —
//  lives here where AgentHubTests can pin it. Service access goes through a protocol so the
//  rollback path is testable without the network.

import Foundation
import Combine

// MARK: - Service boundaries

/// The per-provider slice of `RemoteResourceService` the hub needs.
protocol AgentHubServicing: AnyObject {
    func getAgentModes() async throws -> AgentModesResponse
    func updateAgentMode(agent: String, mode: AgentExecutionMode) async throws -> AgentModesResponse
    func getAIAPIKeys() async throws -> AIAPIKeysResponse
    func saveAIAPIKey(serviceId: String, apiKey: String) async throws -> SaveAPIKeyResponse
    func testAIAPIKey(serviceId: String) async throws -> TestAPIKeyResponse
    func deleteAIAPIKey(serviceId: String) async throws -> DeleteAPIKeyResponse
    func getCopilotIntegrationStatus() async throws -> CopilotIntegrationStatus
    func getCopilotAuthorization() async throws -> CopilotAuthorizationResponse
    func disconnectCopilot() async throws -> CopilotIntegrationStatus
}

protocol WebhookSettingsServicing: AnyObject {
    func getWebhookSettings() async throws -> WebhookSettings
    func updateWebhookSettings(_ request: UpdateWebhookSettingsRequest) async throws -> WebhookSettingsSaveResponse
    func deleteWebhookSettings() async throws -> WebhookDeleteResponse
    func testWebhook() async throws -> WebhookTestResult
}

protocol CustomAgentsServicing: AnyObject {
    func getCustomAgents() async throws -> [CustomAgent]
    func registerCustomAgent(name: String, listIds: [String]?) async throws -> CustomAgentRegistrationResult
    func updateCustomAgent(id: String, image: String?) async throws -> CustomAgentUpdateResponse
    func deleteCustomAgent(id: String) async throws
    func createCopilotCloudAgentToken() async throws -> MCPUserTokenResponse
}

extension RemoteResourceService: AgentHubServicing, WebhookSettingsServicing, CustomAgentsServicing {}

// MARK: - Provider rows

@MainActor
final class AgentHubModel: ObservableObject {
    @Published var modes: [String: AgentExecutionMode] = [:]
    @Published var keyStatuses: [String: AIAPIKeyStatus] = [:]
    @Published var copilotConnected = false
    @Published var isLoading = true
    @Published var loadErrorMessage: String?
    @Published var actionErrorMessage: String?
    @Published var setupErrorMessage: String?
    @Published var savingRowID: String?
    @Published var keyOperationService: String?
    @Published var isPollingCopilot = false

    let rows = AgentRuntimeRow.all
    private let service: AgentHubServicing

    init(service: AgentHubServicing = RemoteResourceService.shared) {
        self.service = service
    }

    // MARK: Derived state

    func mode(for row: AgentRuntimeRow) -> AgentExecutionMode {
        modes[row.modeMailbox] ?? .unset
    }

    func ownership(for row: AgentRuntimeRow) -> AgentOwnership {
        mode(for: row).ownership
    }

    func transport(for row: AgentRuntimeRow) -> AgentSelfTransport? {
        AgentSelfTransport(mode: mode(for: row))
    }

    /// "Needs setup" — only "Astrid runs it" needs a credential: a key for key providers, the
    /// GitHub OAuth grant for Copilot. The user's own runtime never needs one here.
    func isConfigured(_ row: AgentRuntimeRow) -> Bool {
        guard mode(for: row) == .api else { return true }
        if row.usesOAuth { return copilotConnected }
        return keyStatuses[row.service]?.hasKey == true
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        actionErrorMessage = nil
        setupErrorMessage = nil
        defer { isLoading = false }

        do {
            modes = try await service.getAgentModes().modes
        } catch {
            loadErrorMessage = String(
                format: NSLocalizedString("settings.agents.load_failed", comment: ""),
                AgentHubErrors.message(error)
            )
            return
        }

        await refreshCredentials()
    }

    func refreshCredentials() async {
        do {
            keyStatuses = try await service.getAIAPIKeys().keys
        } catch {
            setupErrorMessage = AgentHubErrors.message(error)
        }
        await refreshCopilotStatus()
    }

    func refreshCopilotStatus() async {
        do {
            copilotConnected = try await service.getCopilotIntegrationStatus().connected
        } catch {
            setupErrorMessage = AgentHubErrors.message(error)
        }
    }

    // MARK: Ownership and transport

    /// Apply an ownership choice. Returns whether a write happened.
    @discardableResult
    func select(_ ownership: AgentOwnership, for row: AgentRuntimeRow) async -> Bool {
        guard let mode = AgentOwnership.modeToWrite(selecting: ownership, current: mode(for: row)) else {
            return false
        }
        await setMode(mode, for: row)
        return true
    }

    /// Apply a transport choice under "I run it". `sse` stores nothing — the view hands over to
    /// the Custom Agents section. Returns whether a write happened.
    @discardableResult
    func select(_ transport: AgentSelfTransport, for row: AgentRuntimeRow) async -> Bool {
        guard let mode = transport.mode, mode != self.mode(for: row) else { return false }
        await setMode(mode, for: row)
        return true
    }

    /// Optimistic write with rollback, exactly like the web: the row shows the new mode at once;
    /// a failed PUT restores whatever was there before (including "nothing").
    func setMode(_ mode: AgentExecutionMode, for row: AgentRuntimeRow) async {
        let previous = modes[row.modeMailbox]
        modes[row.modeMailbox] = mode
        savingRowID = row.id
        actionErrorMessage = nil
        defer { savingRowID = nil }

        do {
            let response = try await service.updateAgentMode(agent: row.modeMailbox, mode: mode)
            modes = response.modes
        } catch {
            if let previous {
                modes[row.modeMailbox] = previous
            } else {
                modes.removeValue(forKey: row.modeMailbox)
            }
            actionErrorMessage = String(
                format: NSLocalizedString("settings.agents.save_failed", comment: ""),
                AgentHubErrors.message(error)
            )
        }
    }

    // MARK: Provider keys ("Astrid runs it")

    func saveKey(_ key: String, for serviceID: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keyOperationService = serviceID
        actionErrorMessage = nil
        defer { keyOperationService = nil }

        do {
            _ = try await service.saveAIAPIKey(serviceId: serviceID, apiKey: trimmed)
            keyStatuses = try await service.getAIAPIKeys().keys
        } catch {
            actionErrorMessage = AgentHubErrors.message(error)
        }
    }

    /// Returns the test outcome so a view can show it inline; the key status is updated too.
    @discardableResult
    func testKey(for serviceID: String) async -> TestAPIKeyResponse? {
        keyOperationService = serviceID
        actionErrorMessage = nil
        defer { keyOperationService = nil }

        do {
            let result = try await service.testAIAPIKey(serviceId: serviceID)
            let current = keyStatuses[serviceID]
            keyStatuses[serviceID] = AIAPIKeyStatus(
                hasKey: current?.hasKey ?? true,
                keyPreview: current?.keyPreview,
                isValid: result.success,
                lastTested: current?.lastTested,
                error: result.error
            )
            if let error = result.error {
                actionErrorMessage = error
            }
            return result
        } catch {
            actionErrorMessage = AgentHubErrors.message(error)
            return nil
        }
    }

    func deleteKey(for serviceID: String) async {
        keyOperationService = serviceID
        actionErrorMessage = nil
        defer { keyOperationService = nil }

        do {
            _ = try await service.deleteAIAPIKey(serviceId: serviceID)
            keyStatuses.removeValue(forKey: serviceID)
        } catch {
            actionErrorMessage = AgentHubErrors.message(error)
        }
    }

    // MARK: Copilot (GitHub OAuth)

    /// The GitHub OAuth URL to present. The callback is handled server-side and ends on a
    /// "return to the app" page, so after the browser closes the caller polls `pollCopilotStatus`.
    func copilotAuthorizationURL() async throws -> URL {
        let response = try await service.getCopilotAuthorization()
        guard let url = URL(string: response.url) else { throw URLError(.badURL) }
        return url
    }

    /// Re-check the connection until it reads connected or the attempts run out.
    func pollCopilotStatus(maxAttempts: Int = 20, interval: Duration = .seconds(2)) async {
        isPollingCopilot = true
        defer { isPollingCopilot = false }
        var attempt = 0
        await refreshCopilotStatus()
        while !copilotConnected && attempt < maxAttempts {
            try? await _Concurrency.Task.sleep(for: interval)
            await refreshCopilotStatus()
            attempt += 1
        }
    }

    func disconnectCopilot() async {
        do {
            copilotConnected = try await service.disconnectCopilot().connected
        } catch {
            setupErrorMessage = AgentHubErrors.message(error)
        }
    }
}

// MARK: - Webhook transport

@MainActor
final class WebhookSettingsModel: ObservableObject {
    @Published var settings: WebhookSettings = .unconfigured
    @Published var isLoading = true
    @Published var isSaving = false
    @Published var isTesting = false
    @Published var errorMessage: String?
    @Published var requiresWebSession = false
    /// Shown once, right after the save that minted it.
    @Published var newSecret: String?
    @Published var testResult: WebhookTestResult?

    // Draft the editor binds to.
    @Published var webhookUrl = ""
    @Published var enabled = true
    @Published var selectedAgents: [String] = []
    @Published var regenerateSecret = false

    private let service: WebhookSettingsServicing

    init(service: WebhookSettingsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    var availableAgents: [String] {
        settings.availableAgents ?? WebhookSettings.defaultAgents
    }

    var canSave: Bool {
        !isSaving && URL(string: webhookUrl.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            settings = try await service.getWebhookSettings()
            adoptDraft(from: settings)
        } catch {
            errorMessage = AgentHubErrors.message(error)
        }
    }

    private func adoptDraft(from settings: WebhookSettings) {
        webhookUrl = settings.webhookUrl ?? webhookUrl
        enabled = settings.enabled ?? true
        selectedAgents = settings.agents ?? selectedAgents
    }

    func toggleAgent(_ agent: String) {
        if let index = selectedAgents.firstIndex(of: agent) {
            selectedAgents.remove(at: index)
        } else {
            selectedAgents.append(agent)
        }
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        newSecret = nil
        defer { isSaving = false }
        do {
            let response = try await service.updateWebhookSettings(UpdateWebhookSettingsRequest(
                webhookUrl: webhookUrl.trimmingCharacters(in: .whitespaces),
                enabled: enabled,
                regenerateSecret: regenerateSecret,
                events: settings.events ?? WebhookSettings.defaultEvents,
                agents: selectedAgents
            ))
            newSecret = response.webhookSecret
            regenerateSecret = false
            requiresWebSession = false
            settings = try await service.getWebhookSettings()
            adoptDraft(from: settings)
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }

    func delete() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await service.deleteWebhookSettings()
            settings = .unconfigured
            webhookUrl = ""
            enabled = true
            selectedAgents = []
            newSecret = nil
            testResult = nil
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }

    func test() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            testResult = try await service.testWebhook()
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            testResult = WebhookTestResult(success: false, message: AgentHubErrors.message(error),
                                           responseTime: nil, statusCode: nil, error: nil)
        }
    }
}

// MARK: - Custom Agents

@MainActor
final class CustomAgentsModel: ObservableObject {
    @Published var agents: [CustomAgent] = []
    @Published var isLoading = true
    @Published var isRegistering = false
    @Published var deletingId: String?
    @Published var updatingPhotoId: String?
    @Published var errorMessage: String?
    @Published var registerErrorMessage: String?
    @Published var successMessage: String?
    /// The one-time credentials of the agent just registered.
    @Published var registrationResult: CustomAgentRegistrationResult?

    private let service: CustomAgentsServicing

    init(service: CustomAgentsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            agents = try await service.getCustomAgents()
        } catch {
            errorMessage = AgentHubErrors.message(error)
        }
    }

    /// Returns whether registration succeeded; on success `registrationResult` holds the
    /// credentials to show once.
    @discardableResult
    func register(name: String, listIds: [String]? = nil) async -> Bool {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard CustomAgentNaming.isValid(cleaned) else { return false }
        isRegistering = true
        registerErrorMessage = nil
        defer { isRegistering = false }
        do {
            let result = try await service.registerCustomAgent(name: cleaned, listIds: listIds)
            registrationResult = result
            agents = (try? await service.getCustomAgents()) ?? agents
            flash(NSLocalizedString("settings.openclaw.agent_created", comment: ""))
            return true
        } catch {
            registerErrorMessage = AgentHubErrors.message(error)
            return false
        }
    }

    func delete(_ agent: CustomAgent) async {
        deletingId = agent.id
        errorMessage = nil
        defer { deletingId = nil }
        do {
            try await service.deleteCustomAgent(id: agent.id)
            agents.removeAll { $0.id == agent.id }
            flash(NSLocalizedString("settings.openclaw.agent_deleted", comment: ""))
        } catch {
            errorMessage = AgentHubErrors.message(error)
        }
    }

    /// Edit — the profile photo is the one field the server lets a registered agent change.
    func updatePhoto(_ agent: CustomAgent, imageData: Data) async {
        updatingPhotoId = agent.id
        errorMessage = nil
        defer { updatingPhotoId = nil }
        do {
            let upload = try await AccountService.shared.uploadProfileImage(
                imageData, fileName: "\(agent.agentName)-avatar.jpg", mimeType: "image/jpeg"
            )
            let response = try await service.updateCustomAgent(id: agent.id, image: upload.url)
            if let index = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[index] = CustomAgent(
                    id: agent.id, email: agent.email, name: agent.name, image: response.image,
                    agentName: agent.agentName, status: agent.status, registeredAt: agent.registeredAt,
                    lastActiveAt: agent.lastActiveAt, oauthClientId: agent.oauthClientId
                )
            }
        } catch {
            errorMessage = AgentHubErrors.message(error)
        }
    }

    private func flash(_ message: String) {
        successMessage = message
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .seconds(3))
            if successMessage == message { successMessage = nil }
        }
    }
}

// MARK: - Copilot cloud agent (GitHub.com) token

@MainActor
final class CopilotCloudAgentModel: ObservableObject {
    @Published var token: String?
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var requiresWebSession = false

    private let service: CustomAgentsServicing

    init(service: CustomAgentsServicing = RemoteResourceService.shared) {
        self.service = service
    }

    var secretName: String { CopilotCloudAgentSetup.secretName(wordmark: Brand.wordmark) }

    var config: String {
        CopilotCloudAgentSetup.mcpConfig(origin: Constants.API.baseURL, wordmark: Brand.wordmark)
    }

    func createToken() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            token = try await service.createCopilotCloudAgentToken().token
            requiresWebSession = false
        } catch {
            requiresWebSession = AgentHubErrors.requiresWebSession(error)
            errorMessage = AgentHubErrors.message(error)
        }
    }
}
