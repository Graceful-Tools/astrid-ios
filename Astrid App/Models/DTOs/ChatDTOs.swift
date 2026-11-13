import Foundation

// MARK: - Chat Message DTOs

struct ChatMessagesResponse: Codable {
    let messages: [ChatMessage]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Agent DTOs

struct AvailableAgentsResponse: Codable {
    let agents: [AvailableAgent]
}

struct AIAssistantSettingsResponse: Codable {
    var defaultAgentId: String?
    var preferredService: String?
}

struct UpdateAIAssistantSettingsRequest: Codable {
    var defaultAgentId: String?
    var preferredService: String?
}
