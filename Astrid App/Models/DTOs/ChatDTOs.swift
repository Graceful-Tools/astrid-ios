import Foundation

// MARK: - Chat Channel DTOs

struct ChatChannelResponse: Codable {
    let channel: ChatChannel
}

struct CreateChatChannelRequest: Codable {
    var listId: String?
    var virtualKey: String?
}

// MARK: - Chat Message DTOs

struct ChatMessagesResponse: Codable {
    let messages: [ChatMessage]
    let hasMore: Bool
    let nextCursor: String?
}

struct ChatMessageResponse: Codable {
    let message: ChatMessage
}

struct CreateChatMessageRequest: Codable {
    var content: String
    var type: String?  // TEXT, MARKDOWN, ATTACHMENT
    var fileId: String?
    var attachmentUrl: String?
    var attachmentName: String?
    var attachmentType: String?
    var attachmentSize: Int?
    var replyToId: String?
    var clientRequestId: String?
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

struct AvailableModelsResponse: Codable {
    let models: [String]
    let source: String?  // "live" or "static"
}
