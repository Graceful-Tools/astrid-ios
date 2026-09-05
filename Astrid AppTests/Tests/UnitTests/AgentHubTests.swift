//  AgentHubTests.swift
//  Regression guard for AITD-297 — "[ios] Native Agent Hub: ownership-first agent settings with
//  web parity".
//
//  The web Agent Hub (astrid-web PRs #272–#274) asks ONE question per provider row — who owns the
//  runtime — and only then which transport. Storage stays the four-state execution mode; ownership
//  is derived for display and never written. These tests pin the derivation, the transition rules,
//  the optimistic-with-rollback write, the wire shapes of the new endpoints, and the
//  cross-platform contract (both settings screens expose the hub, iOS-only views stay out of the
//  Mac target).

import XCTest
@testable import Astrid_App

@MainActor
final class AgentHubTests: XCTestCase {

    private var claude: AgentRuntimeRow { AgentRuntimeRow.all[0] }
    private var codex: AgentRuntimeRow { AgentRuntimeRow.all[1] }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Ownership is derived, never stored

    func testAITD297_OwnershipIsDerivedFromTheStoredMode() {
        XCTAssertEqual(AgentOwnership(mode: .api), .astrid)
        XCTAssertEqual(AgentOwnership(mode: .off), .off)
        XCTAssertEqual(AgentOwnership(mode: .polling), .user)
        XCTAssertEqual(AgentOwnership(mode: .webhook), .user)
        XCTAssertEqual(AgentOwnership.allCases, [.astrid, .user, .off], "web order: Astrid runs it / I run it / Off")
    }

    func testAITD297_TheWireCarriesOnlyAgentAndMode() throws {
        let request = UpdateAgentModeRequest(agent: "claude", mode: .polling)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: String]
        )
        XCTAssertEqual(Set(object.keys), ["agent", "mode"], "no invented ownership field on the wire")
    }

    func testAITD297_SelectingAnOwnershipWritesTheModeTheWebWrites() {
        XCTAssertEqual(AgentOwnership.modeToWrite(selecting: .astrid, current: .polling), .api)
        XCTAssertEqual(AgentOwnership.modeToWrite(selecting: .off, current: .api), .off)
        // Entering "I run it" from api/off defaults to polling; the transport picker refines it.
        XCTAssertEqual(AgentOwnership.modeToWrite(selecting: .user, current: .api), .polling)
        XCTAssertEqual(AgentOwnership.modeToWrite(selecting: .user, current: .off), .polling)
        // Already "I run it": re-selecting it must not clobber a chosen webhook transport.
        XCTAssertNil(AgentOwnership.modeToWrite(selecting: .user, current: .polling))
        XCTAssertNil(AgentOwnership.modeToWrite(selecting: .user, current: .webhook))
        XCTAssertNil(AgentOwnership.modeToWrite(selecting: .astrid, current: .api))
        XCTAssertNil(AgentOwnership.modeToWrite(selecting: .off, current: .off))
    }

    func testAITD297_TransportsUnderIRunItMatchTheWeb() {
        XCTAssertEqual(AgentSelfTransport.allCases, [.polling, .webhook, .sse])
        XCTAssertEqual(AgentSelfTransport.polling.mode, .polling)
        XCTAssertEqual(AgentSelfTransport.webhook.mode, .webhook)
        XCTAssertNil(AgentSelfTransport.sse.mode, "a Custom Agent is its own identity, not a per-provider mode")
        XCTAssertEqual(AgentSelfTransport(mode: .polling), .polling)
        XCTAssertEqual(AgentSelfTransport(mode: .webhook), .webhook)
        XCTAssertNil(AgentSelfTransport(mode: .api))
        XCTAssertNil(AgentSelfTransport(mode: .off))
    }

    // MARK: - The shared model

    func testAITD297_MissingMailboxDefaultsToPolling() {
        let model = AgentHubModel(service: FakeAgentHubService())
        XCTAssertEqual(model.mode(for: claude), .polling)
        XCTAssertEqual(model.ownership(for: claude), .user)
    }

    func testAITD297_ModeWriteIsOptimisticThenAdoptsTheServerAnswer() async {
        let service = FakeAgentHubService()
        let model = AgentHubModel(service: service)
        model.modes = ["claude": .polling, "openai": .api]

        service.onUpdateMode = { _, _ in
            // Visible before the server answers — that is what "optimistic" means.
            XCTAssertEqual(model.modes["claude"], .api)
        }
        service.updateModeResult = .success(
            AgentModesResponse(agents: [], modes: ["claude": .api, "openai": .off], meta: nil)
        )

        await model.setMode(.api, for: claude)

        XCTAssertEqual(model.modes, ["claude": .api, "openai": .off], "the server's map wins once it answers")
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertNil(model.savingRowID)
    }

    func testAITD297_FailedModeWriteRollsBackToThePreviousMode() async {
        let service = FakeAgentHubService()
        let model = AgentHubModel(service: service)
        model.modes = ["claude": .webhook]
        service.updateModeResult = .failure(AstridAPIError.httpError(statusCode: 500, message: "boom"))

        await model.setMode(.off, for: claude)

        XCTAssertEqual(model.modes["claude"], .webhook)
        XCTAssertNotNil(model.actionErrorMessage)
        XCTAssertNil(model.savingRowID)
    }

    func testAITD297_FailedModeWriteForAnUnsetMailboxRemovesTheOptimisticEntry() async {
        let service = FakeAgentHubService()
        let model = AgentHubModel(service: service)
        service.updateModeResult = .failure(AstridAPIError.httpError(statusCode: 500, message: "boom"))

        await model.setMode(.api, for: claude)

        XCTAssertNil(model.modes["claude"], "nothing was stored before, nothing is stored after")
        XCTAssertEqual(model.mode(for: claude), .polling)
    }

    func testAITD297_ReselectingIRunItDoesNotWrite() async {
        let service = FakeAgentHubService()
        let model = AgentHubModel(service: service)
        model.modes = ["claude": .webhook]

        let wrote = await model.select(.user, for: claude)

        XCTAssertFalse(wrote)
        XCTAssertEqual(service.updateModeCalls.count, 0)
        XCTAssertEqual(model.modes["claude"], .webhook)
    }

    func testAITD297_SelectingAstridRunsItWritesApiForTheRowsModeMailbox() async {
        let service = FakeAgentHubService()
        let model = AgentHubModel(service: service)
        service.updateModeResult = .success(AgentModesResponse(agents: [], modes: ["openai": .api], meta: nil))

        let wrote = await model.select(.astrid, for: codex)

        XCTAssertTrue(wrote)
        XCTAssertEqual(service.updateModeCalls.map(\.agent), ["openai"], "the Codex row stores against the openai mailbox")
        XCTAssertEqual(service.updateModeCalls.map(\.mode), [.api])
    }

    func testAITD297_NeedsSetupOnlyWhenAstridRunsItWithoutACredential() {
        let model = AgentHubModel(service: FakeAgentHubService())
        model.modes = ["claude": .api, "copilot": .api, "gemini": .polling]
        model.keyStatuses = ["claude": AIAPIKeyStatus(hasKey: true, keyPreview: "…ab", isValid: nil, lastTested: nil, error: nil)]
        model.copilotConnected = false

        XCTAssertTrue(model.isConfigured(claude))
        XCTAssertFalse(model.isConfigured(AgentRuntimeRow.all[2]), "Copilot in api mode needs the GitHub OAuth grant")
        XCTAssertTrue(model.isConfigured(AgentRuntimeRow.all[3]), "polling never needs a key")
    }

    func testAITD297_WebSessionRequirementIsRecognised() {
        XCTAssertTrue(AgentHubErrors.requiresWebSession(AstridAPIError.httpError(statusCode: 403, message: "session")))
        XCTAssertTrue(AgentHubErrors.requiresWebSession(AstridAPIError.unauthorized))
        XCTAssertFalse(AgentHubErrors.requiresWebSession(AstridAPIError.httpError(statusCode: 500, message: "boom")))
        XCTAssertFalse(AgentHubErrors.requiresWebSession(URLError(.notConnectedToInternet)))
    }

    // MARK: - Wire shapes of the new endpoints

    func testAITD297_WebhookSettingsDecodeTheUnconfiguredAndConfiguredShapes() throws {
        let unconfigured = try JSONDecoder().decode(WebhookSettings.self, from: Data("""
        {"configured":false,"availableEvents":["task.assigned","comment.created","task.updated"],
         "availableAgents":["claude","openai","gemini","copilot"],"meta":{"apiVersion":"v1","authSource":"session"}}
        """.utf8))
        XCTAssertFalse(unconfigured.configured)
        XCTAssertEqual(unconfigured.availableAgents, ["claude", "openai", "gemini", "copilot"])
        XCTAssertNil(unconfigured.webhookUrl)

        let configured = try JSONDecoder().decode(WebhookSettings.self, from: Data("""
        {"configured":true,"enabled":true,"events":["task.assigned"],"agents":["claude"],
         "webhookUrl":"https://example.com/hook","hasSecret":true,"lastFiredAt":"2026-09-05T10:00:00.000Z",
         "failureCount":2,"maxRetries":3,"createdAt":"x","updatedAt":"y",
         "availableEvents":["task.assigned"],"availableAgents":["claude"]}
        """.utf8))
        XCTAssertTrue(configured.configured)
        XCTAssertEqual(configured.webhookUrl, "https://example.com/hook")
        XCTAssertEqual(configured.hasSecret, true)
        XCTAssertEqual(configured.failureCount, 2)
        XCTAssertEqual(configured.agents, ["claude"])
    }

    func testAITD297_WebhookUpdateRequestMatchesTheWebPayload() throws {
        let request = UpdateWebhookSettingsRequest(
            webhookUrl: "https://example.com/hook",
            enabled: false,
            regenerateSecret: true,
            events: WebhookSettings.defaultEvents,
            agents: ["claude", "gemini"]
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["webhookUrl"] as? String, "https://example.com/hook")
        XCTAssertEqual(object["enabled"] as? Bool, false)
        XCTAssertEqual(object["regenerateSecret"] as? Bool, true)
        XCTAssertEqual(object["events"] as? [String], ["task.assigned", "comment.created"])
        XCTAssertEqual(object["agents"] as? [String], ["claude", "gemini"])
    }

    func testAITD297_WebhookSaveResponseCarriesTheOneTimeSecret() throws {
        let saved = try JSONDecoder().decode(WebhookSettingsSaveResponse.self, from: Data("""
        {"success":true,"enabled":true,"events":[],"agents":[],"webhookUrl":"https://x",
         "webhookSecret":"abc123","secretRegenerated":false,"message":"Saved"}
        """.utf8))
        XCTAssertEqual(saved.webhookSecret, "abc123")

        let updated = try JSONDecoder().decode(WebhookSettingsSaveResponse.self, from: Data("""
        {"success":true,"enabled":true,"events":[],"agents":[],"webhookUrl":"https://x","message":"Updated"}
        """.utf8))
        XCTAssertNil(updated.webhookSecret)
    }

    func testAITD297_CustomAgentRegistrationSendsListIdsOnlyWhenGiven() throws {
        let withLists = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RegisterCustomAgentRequest(agentName: "buddy", listIds: ["l1"]))
        ) as? [String: Any])
        XCTAssertEqual(withLists["agentName"] as? String, "buddy")
        XCTAssertEqual(withLists["listIds"] as? [String], ["l1"])

        let without = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RegisterCustomAgentRequest(agentName: "buddy", listIds: nil))
        ) as? [String: Any])
        XCTAssertNil(without["listIds"])
    }

    func testAITD297_CustomAgentNamesFollowTheServerRule() {
        XCTAssertTrue(CustomAgentNaming.isValid("buddy"))
        XCTAssertTrue(CustomAgentNaming.isValid("dev-bot.2"))
        XCTAssertFalse(CustomAgentNaming.isValid("a"), "two characters minimum")
        XCTAssertFalse(CustomAgentNaming.isValid("Buddy"), "lowercase only")
        XCTAssertFalse(CustomAgentNaming.isValid("-buddy"), "must start alphanumeric")
        XCTAssertFalse(CustomAgentNaming.isValid("openclaw"), "reserved")
        XCTAssertTrue(CustomAgentNaming.isReserved("admin"))
    }

    func testAITD297_CopilotCloudAgentSetupMatchesTheWebConfig() throws {
        XCTAssertEqual(CopilotCloudAgentSetup.secretName(wordmark: "astrid"), "COPILOT_MCP_ASTRID_TOKEN")
        XCTAssertEqual(CopilotCloudAgentSetup.secretName(wordmark: "my brand"), "COPILOT_MCP_MY_BRAND_TOKEN")

        let json = CopilotCloudAgentSetup.mcpConfig(origin: "https://astrid.cc/", wordmark: "Astrid")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        let server = try XCTUnwrap(servers["astrid"] as? [String: Any], "keyed by the lowercased wordmark")
        XCTAssertEqual(server["type"] as? String, "http")
        XCTAssertEqual(server["url"] as? String, "https://astrid.cc/mcp")
        XCTAssertEqual((server["headers"] as? [String: String])?["Authorization"], "Bearer $COPILOT_MCP_ASTRID_TOKEN")
        XCTAssertEqual(server["tools"] as? [String], ["*"])

        let request = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(MCPUserTokenRequest.copilotCloudAgent)
        ) as? [String: Any])
        XCTAssertEqual(request["permissions"] as? [String], ["read", "write"])
        XCTAssertEqual(request["expiresInDays"] as? Int, 365)
        XCTAssertEqual(request["agent"] as? String, "copilot")
        XCTAssertEqual(request["description"] as? String, "GitHub Copilot cloud agent")
    }

    func testAITD297_LinksPointAtTheGeneratedWebResources() {
        XCTAssertEqual(AgentHubLinks.loopsGuide(origin: "https://astrid.cc/")?.absoluteString, "https://astrid.cc/docs/loops")
        XCTAssertEqual(AgentHubLinks.workflowDownload(origin: "https://astrid.cc")?.absoluteString,
                       "https://astrid.cc/api/downloads/ASTRID_WORKFLOW.md")
        XCTAssertEqual(AgentHubLinks.webAgentSettings(origin: "https://astrid.cc")?.absoluteString,
                       "https://astrid.cc/settings/agents")
    }

    func testAITD297_ServerRunFilterIsAQueryParameter() {
        XCTAssertEqual(AstridAPIClient.availableAgentsQueryItems(serverRunOnly: true),
                       [URLQueryItem(name: "serverRun", value: "true")])
        XCTAssertNil(AstridAPIClient.availableAgentsQueryItems(serverRunOnly: false),
                     "the unfiltered list is for assignee pickers and must stay unfiltered")
    }

    func testAITD297_CapabilitiesCarryCustomAgents() throws {
        let off = try JSONDecoder().decode(ServerCapabilities.self,
                                           from: Data(#"{"integrations":{"customAgents":false}}"#.utf8))
        XCTAssertFalse(off.integrations.customAgents)
        XCTAssertTrue(ServerCapabilities.permissive.integrations.customAgents)
        XCTAssertTrue(try JSONDecoder().decode(ServerCapabilities.self, from: Data("{}".utf8)).integrations.customAgents)
    }

    // MARK: - The client calls the live endpoints

    func testAITD297_ClientUsesTheCustomAgentsNamesNotTheLegacyAliases() throws {
        let client = try source("Astrid App/Core/Networking/AstridAPIClient.swift")
        XCTAssertTrue(client.contains("\"/api/v1/custom-agents/register\""))
        XCTAssertTrue(client.contains("\"/api/v1/custom-agents/agents\""))
        XCTAssertTrue(client.contains("\"/api/v1/custom-agents/agents/\\("))
        XCTAssertTrue(client.contains("\"/api/v1/users/me/webhook-settings\""))
        XCTAssertTrue(client.contains("\"/api/mcp/user-tokens\""))
        XCTAssertFalse(client.contains("/api/v1/openclaw"), "openclaw paths are legacy aliases")
    }

    // MARK: - Both platforms expose the hub

    func testAITD297_SettingsExposesTheHubOnIOSAndMac() throws {
        XCTAssertTrue(try source("Astrid App/Views/Settings/SettingsView.swift").contains("AgentHubView()"))
        XCTAssertTrue(try source("Astrid Mac/App/MacSettingsView.swift").contains("MacAgentHubView()"))
    }

    /// iOS settings views use UIKit-only API, so every file under Views/Settings must be listed in
    /// the Mac target's membership exceptions — a file added without the entry breaks the Mac build.
    func testAITD297_EveryIOSSettingsViewIsExcludedFromTheMacTarget() throws {
        let settings = repoRoot().appendingPathComponent("Astrid App/Views/Settings")
        let files = try FileManager.default.contentsOfDirectory(atPath: settings.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        let project = try source("Astrid App.xcodeproj/project.pbxproj")
        let missing = files.filter { !project.contains("Views/Settings/\($0),") }
        XCTAssertEqual(missing, [], "add these to the \"Astrid Mac\" exceptions in project.pbxproj")
    }
}

// MARK: - Fake service

@MainActor
private final class FakeAgentHubService: AgentHubServicing {
    var updateModeResult: Result<AgentModesResponse, Error> = .success(AgentModesResponse(agents: [], modes: [:], meta: nil))
    var updateModeCalls: [(agent: String, mode: AgentExecutionMode)] = []
    var onUpdateMode: ((String, AgentExecutionMode) -> Void)?

    func getAgentModes() async throws -> AgentModesResponse {
        AgentModesResponse(agents: [], modes: [:], meta: nil)
    }

    func updateAgentMode(agent: String, mode: AgentExecutionMode) async throws -> AgentModesResponse {
        updateModeCalls.append((agent, mode))
        onUpdateMode?(agent, mode)
        return try updateModeResult.get()
    }

    func getAIAPIKeys() async throws -> AIAPIKeysResponse { AIAPIKeysResponse(keys: [:]) }
    func saveAIAPIKey(serviceId: String, apiKey: String) async throws -> SaveAPIKeyResponse { SaveAPIKeyResponse(success: true) }
    func testAIAPIKey(serviceId: String) async throws -> TestAPIKeyResponse { TestAPIKeyResponse(success: true, error: nil) }
    func deleteAIAPIKey(serviceId: String) async throws -> DeleteAPIKeyResponse { DeleteAPIKeyResponse(success: true) }
    func getCopilotIntegrationStatus() async throws -> CopilotIntegrationStatus { CopilotIntegrationStatus(connected: false) }
    func getCopilotAuthorization() async throws -> CopilotAuthorizationResponse { CopilotAuthorizationResponse(url: "https://github.com/login") }
    func disconnectCopilot() async throws -> CopilotIntegrationStatus { CopilotIntegrationStatus(connected: false) }
}
