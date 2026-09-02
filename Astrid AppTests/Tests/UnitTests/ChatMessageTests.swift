import XCTest
@testable import Astrid_App

/// Unit tests for chat message and channel models
final class ChatMessageTests: XCTestCase {

    // MARK: - ChatMessage Model Tests

    func testCreateTextMessage() {
        let message = createTestMessage(
            id: "msg-123",
            content: "Hello from chat",
            type: .TEXT
        )

        XCTAssertEqual(message.id, "msg-123")
        XCTAssertEqual(message.content, "Hello from chat")
        XCTAssertEqual(message.type, .TEXT)
        XCTAssertFalse(message.isFromAgent)
        XCTAssertFalse(message.isPending)
    }

    func testCreateMarkdownMessage() {
        let message = createTestMessage(
            id: "msg-md",
            content: "# Response\n\n**Bold** text here",
            type: .MARKDOWN
        )

        XCTAssertEqual(message.type, .MARKDOWN)
        XCTAssertTrue(message.content.contains("**Bold**"))
    }

    func testAgentMessage() {
        let agentAuthor = User(
            id: "agent-astrid",
            email: "astrid@astrid.cc",
            name: "Astrid",
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: true,
            aiAgentType: "astrid"
        )

        let message = createTestMessage(
            id: "msg-agent",
            content: "I can help with that!",
            author: agentAuthor,
            authorId: "agent-astrid"
        )

        XCTAssertTrue(message.isFromAgent)
        XCTAssertEqual(message.author?.aiAgentType, "astrid")
        XCTAssertEqual(message.author?.isAIAgent, true)
    }

    /// Regression for task 68bebdaa: Copilot's avatar URL serves SVG without an extension.
    /// Chat must use the shared loader that substitutes the bundled mascot before decoding.
    func testTask_68bebdaaChatAvatarUsesAssetAwareImageLoader() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Views/Chat/ChatMessageBubble.swift"), encoding: .utf8)
        let avatarView = try XCTUnwrap(
            source.components(separatedBy: "private var avatarView").last?
                .components(separatedBy: "private var initialsAvatar").first
        )

        XCTAssertTrue(avatarView.contains("CachedAsyncImage(url: url)"),
                      "Chat avatars must recognize bundled agent assets instead of decoding SVG")
        XCTAssertFalse(avatarView.contains("\n            AsyncImage(url: url)"),
                       "AsyncImage falls back to initials for Copilot's SVG endpoint")
    }

    func testPendingMessage() {
        let message = createTestMessage(
            id: "temp_abc123",
            content: "Sending..."
        )

        XCTAssertTrue(message.isPending)
        XCTAssertTrue(message.id.hasPrefix("temp_"))
    }

    func testNonPendingMessage() {
        let message = createTestMessage(
            id: "real-server-id",
            content: "Sent"
        )

        XCTAssertFalse(message.isPending)
    }

    // MARK: - StableId Tests

    func testStableIdWithValidId() {
        let message = createTestMessage(id: "msg-valid")
        XCTAssertEqual(message.stableId, "msg-valid")
    }

    func testStableIdWithEmptyId() {
        let message = createTestMessage(id: "", content: "Some content")
        XCTAssertTrue(message.stableId.hasPrefix("fallback_"))
    }

    // MARK: - ChatChannel Model Tests

    func testChatChannelWithListId() {
        let channel = ChatChannel(
            id: "ch-123",
            listId: "list-456",
            virtualKey: nil,
            name: "Test Channel",
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(channel.id, "ch-123")
        XCTAssertEqual(channel.listId, "list-456")
        XCTAssertNil(channel.virtualKey)
    }

    func testChatChannelWithVirtualKey() {
        let channel = ChatChannel(
            id: "ch-virtual",
            listId: nil,
            virtualKey: "virtual-chat:user123:general",
            name: nil,
            createdAt: nil,
            updatedAt: nil
        )

        XCTAssertEqual(channel.id, "ch-virtual")
        XCTAssertNil(channel.listId)
        XCTAssertEqual(channel.virtualKey, "virtual-chat:user123:general")
    }

    // MARK: - AIAgentSettings Model Tests

    func testAIAssistantSettings() {
        let settings = AIAssistantSettings(
            defaultAgentId: "agent-claude",
            preferredService: "claude"
        )

        XCTAssertEqual(settings.defaultAgentId, "agent-claude")
        XCTAssertEqual(settings.preferredService, "claude")
    }

    func testAvailableAgent() {
        let agent = AvailableAgent(
            id: "agent-1",
            name: "Claude",
            email: "claude@ai.agents",
            image: nil,
            service: "claude"
        )

        XCTAssertEqual(agent.name, "Claude")
        XCTAssertEqual(agent.serviceDisplayName, "Claude")
        XCTAssertTrue(agent.isBuiltIn)
    }

    func testOpenClawAgentIsNotBuiltIn() {
        let agent = AvailableAgent(
            id: "agent-custom",
            name: "My Bot",
            email: "bot@example.com",
            image: nil,
            service: "openclaw"
        )

        XCTAssertFalse(agent.isBuiltIn)
        XCTAssertEqual(agent.serviceDisplayName, "OpenClaw")
    }

    // MARK: - JSON Encoding/Decoding Tests

    @MainActor func testChatMessageCodable() throws {
        let message = createTestMessage(
            id: "msg-codable",
            content: "Test content",
            type: .TEXT
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.content, message.content)
        XCTAssertEqual(decoded.channelId, message.channelId)
        XCTAssertEqual(decoded.type, message.type)
    }

    @MainActor func testChatChannelCodable() throws {
        let channel = ChatChannel(
            id: "ch-codable",
            listId: "list-1",
            virtualKey: nil,
            name: "Test",
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(channel)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatChannel.self, from: data)

        XCTAssertEqual(decoded.id, channel.id)
        XCTAssertEqual(decoded.listId, channel.listId)
    }

    @MainActor func testAvailableAgentCodable() throws {
        let agent = AvailableAgent(
            id: "agent-test",
            name: "Test Agent",
            email: "test@agent.cc",
            image: "https://example.com/avatar.png",
            service: "gemini"
        )

        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(AvailableAgent.self, from: data)

        XCTAssertEqual(decoded.id, agent.id)
        XCTAssertEqual(decoded.name, agent.name)
        XCTAssertEqual(decoded.service, agent.service)
        XCTAssertEqual(decoded.serviceDisplayName, "Gemini")
    }

    // MARK: - Response DTO Tests

    @MainActor func testChatMessagesResponseDecoding() throws {
        let json = """
        {
            "messages": [
                {
                    "id": "msg-1",
                    "channelId": "ch-1",
                    "authorId": "user-1",
                    "content": "Hello",
                    "type": "TEXT"
                }
            ],
            "hasMore": true,
            "nextCursor": "2026-03-28T12:00:00Z"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ChatMessagesResponse.self, from: json)
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertTrue(response.hasMore)
        XCTAssertEqual(response.nextCursor, "2026-03-28T12:00:00Z")
    }

    // MARK: - Helpers

    private func createTestMessage(
        id: String = UUID().uuidString,
        channelId: String = "test-channel",
        content: String = "Test message",
        type: Comment.CommentType = .TEXT,
        author: User? = nil,
        authorId: String? = "test-user"
    ) -> ChatMessage {
        return ChatMessage(
            id: id,
            channelId: channelId,
            authorId: authorId,
            author: author,
            content: content,
            type: type,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            replyToId: nil,
            clientRequestId: nil,
            secureFiles: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
