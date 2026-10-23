import XCTest
@testable import Astrid_App

/// Unit tests for chat message and channel models
final class ChatMessageTests: XCTestCase {

    // MARK: - ChatMessage Model Tests

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

    // MARK: - AIAgentSettings Model Tests

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
