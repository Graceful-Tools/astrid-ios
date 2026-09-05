//  AgentHubDTOs.swift
//  Wire types for the Agent Hub surfaces that are not per-provider modes (AITD-297):
//  webhook transport, Custom Agents, and the Copilot cloud-agent MCP token.

import Foundation

// MARK: - Webhook transport (`/api/v1/users/me/webhook-settings`)

/// GET answer. `configured == false` still carries the option lists the editor is built from.
/// The secret is never returned — only `hasSecret`.
struct WebhookSettings: Codable, Equatable {
    static let defaultEvents = ["task.assigned", "comment.created"]
    static let defaultAgents = ["claude", "openai", "gemini", "copilot"]

    let configured: Bool
    var enabled: Bool?
    var webhookUrl: String?
    var hasSecret: Bool?
    var events: [String]?
    var agents: [String]?
    var failureCount: Int?
    var lastFiredAt: String?
    var availableEvents: [String]?
    var availableAgents: [String]?

    static let unconfigured = WebhookSettings(configured: false)

    init(configured: Bool, enabled: Bool? = nil, webhookUrl: String? = nil, hasSecret: Bool? = nil,
         events: [String]? = nil, agents: [String]? = nil, failureCount: Int? = nil,
         lastFiredAt: String? = nil, availableEvents: [String]? = nil, availableAgents: [String]? = nil) {
        self.configured = configured
        self.enabled = enabled
        self.webhookUrl = webhookUrl
        self.hasSecret = hasSecret
        self.events = events
        self.agents = agents
        self.failureCount = failureCount
        self.lastFiredAt = lastFiredAt
        self.availableEvents = availableEvents
        self.availableAgents = availableAgents
    }

    /// Every key is optional on the wire except `configured`, and unknown keys (`meta`,
    /// `maxRetries`, timestamps) are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        webhookUrl = try c.decodeIfPresent(String.self, forKey: .webhookUrl)
        hasSecret = try c.decodeIfPresent(Bool.self, forKey: .hasSecret)
        events = try c.decodeIfPresent([String].self, forKey: .events)
        agents = try c.decodeIfPresent([String].self, forKey: .agents)
        failureCount = try c.decodeIfPresent(Int.self, forKey: .failureCount)
        lastFiredAt = try c.decodeIfPresent(String.self, forKey: .lastFiredAt)
        availableEvents = try c.decodeIfPresent([String].self, forKey: .availableEvents)
        availableAgents = try c.decodeIfPresent([String].self, forKey: .availableAgents)
    }
}

/// PUT body — the same five fields the web editor sends.
struct UpdateWebhookSettingsRequest: Codable, Equatable {
    let webhookUrl: String
    let enabled: Bool
    let regenerateSecret: Bool
    let events: [String]
    let agents: [String]
}

/// PUT answer. `webhookSecret` is present exactly once: on first configuration, or when the
/// caller asked to regenerate it.
struct WebhookSettingsSaveResponse: Codable {
    let success: Bool
    let webhookSecret: String?
    let secretRegenerated: Bool?
    let message: String?
}

/// POST (test-fire) answer.
struct WebhookTestResult: Codable, Equatable {
    let success: Bool
    let message: String?
    let responseTime: Int?
    let statusCode: Int?
    let error: String?
}

struct WebhookDeleteResponse: Codable {
    let success: Bool
}

// MARK: - Custom Agents (`/api/v1/custom-agents/*`)

/// One agent the user registered. The server still stores these as `openclaw_worker`; the
/// product name is Custom Agent and the v1 paths use `custom-agents`.
struct CustomAgent: Codable, Identifiable, Equatable {
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

struct CustomAgentsResponse: Codable {
    let agents: [CustomAgent]
}

struct RegisterCustomAgentRequest: Codable, Equatable {
    let agentName: String
    /// Lists the new agent should join as a member. Omitted when nil so the server's own
    /// default applies.
    let listIds: [String]?
}

struct CustomAgentRegistrationAgent: Codable {
    let id: String
    let email: String
    let name: String
    let aiAgentType: String
}

struct CustomAgentRegistrationOAuth: Codable {
    let clientId: String
    let clientSecret: String
    let scopes: [String]
}

struct CustomAgentRegistrationConfig: Codable {
    let sseEndpoint: String
    let apiBase: String
    let tokenEndpoint: String
}

/// The one-time registration answer: the client secret is shown once and never again.
struct CustomAgentRegistrationResult: Codable, Identifiable {
    let agent: CustomAgentRegistrationAgent
    let oauth: CustomAgentRegistrationOAuth
    let config: CustomAgentRegistrationConfig

    var id: String { agent.id }
}

struct UpdateCustomAgentRequest: Codable {
    let image: String?
}

struct CustomAgentUpdateResponse: Codable {
    let success: Bool
    let image: String?
}

struct CustomAgentDeleteResponse: Codable {
    let success: Bool?
}

// MARK: - Copilot cloud agent token (`POST /api/mcp/user-tokens`)

struct MCPUserTokenRequest: Codable, Equatable {
    let permissions: [String]
    let expiresInDays: Int
    let description: String
    let agent: String

    /// What the web Copilot MCP setup requests: a year-long read/write token minted for the
    /// copilot identity.
    static let copilotCloudAgent = MCPUserTokenRequest(
        permissions: ["read", "write"],
        expiresInDays: 365,
        description: CopilotCloudAgentSetup.tokenDescription,
        agent: "copilot"
    )
}

struct MCPUserTokenResponse: Codable {
    let token: String
    let expiresAt: String?
}
