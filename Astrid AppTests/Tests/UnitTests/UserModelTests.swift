import XCTest
@testable import Astrid_App

/// Unit tests for User model
final class UserModelTests: XCTestCase {

    // MARK: - Basic User Tests

    func testCreateUser() {
        let user = User(
            id: "user-123",
            email: "test@example.com",
            name: "John Doe",
            image: "https://example.com/avatar.jpg",
            createdAt: Date(),
            defaultDueTime: "09:00",
            isPending: false,
            isAIAgent: false,
            aiAgentType: nil
        )

        XCTAssertEqual(user.id, "user-123")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertEqual(user.name, "John Doe")
        XCTAssertEqual(user.image, "https://example.com/avatar.jpg")
        XCTAssertEqual(user.defaultDueTime, "09:00")
        XCTAssertEqual(user.isPending, false)
        XCTAssertEqual(user.isAIAgent, false)
    }

    func testCreateMinimalUser() {
        let user = User(
            id: "minimal-user",
            email: nil,
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )

        XCTAssertEqual(user.id, "minimal-user")
        XCTAssertNil(user.email)
        XCTAssertNil(user.name)
    }

    // MARK: - Display Name Tests

    func testDisplayNameWithName() {
        let user = TestHelpers.createTestUser(id: "1", name: "Alice Smith", email: "alice@example.com")
        XCTAssertEqual(user.displayName, "Alice Smith")
    }

    func testDisplayNameWithOnlyEmail() {
        let user = User(
            id: "2",
            email: "alice@example.com",
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )
        XCTAssertEqual(user.displayName, "alice@example.com")
    }

    func testDisplayNameWithNeither() {
        let user = User(
            id: "3",
            email: nil,
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )
        XCTAssertEqual(user.displayName, "Unknown User")
    }

    // MARK: - Initials Tests

    func testInitialsWithTwoPartName() {
        let user = TestHelpers.createTestUser(name: "John Doe")
        XCTAssertEqual(user.initials, "JD")
    }

    func testInitialsWithThreePartName() {
        let user = TestHelpers.createTestUser(name: "John Middle Doe")
        XCTAssertEqual(user.initials, "JM")  // Uses first and second parts (John + Middle)
    }

    func testInitialsWithSingleName() {
        let user = TestHelpers.createTestUser(name: "Alice")
        XCTAssertEqual(user.initials, "AL")  // First two characters
    }

    func testInitialsWithEmail() {
        let user = User(
            id: "email-user",
            email: "alice@example.com",
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )
        XCTAssertEqual(user.initials, "AL")  // First two characters of email
    }

    func testInitialsWithNeitherNameNorEmail() {
        let user = User(
            id: "no-name-user",
            email: nil,
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )
        // A single neutral glyph, not "??" (42013da7). Two question marks read as an error
        // rather than as a person we simply have no profile for yet.
        XCTAssertEqual(user.initials, "•")
        XCTAssertEqual(user.initials.count, 1)
    }

    func testInitialsAreLowercase() {
        let user = TestHelpers.createTestUser(name: "john doe")
        XCTAssertEqual(user.initials, "JD")  // Should be uppercase
    }

    // MARK: - AI Agent Tests

    func testAIAgentUser() {
        let aiUser = User(
            id: "ai-agent",
            email: "claude@astrid.cc",
            name: "Claude",
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: true,
            aiAgentType: "claude"
        )

        XCTAssertTrue(aiUser.isAIAgent ?? false)
        XCTAssertEqual(aiUser.aiAgentType, "claude")
    }

    func testAvatarURL() {
        // AI agents now have their logos stored in the image field
        // avatarURL simply returns the image field for all users
        let claudeUser = User(
            id: "claude-agent",
            email: "claude@astrid.cc",
            name: "Claude",
            image: "https://astrid.cc/images/ai-agents/claude.svg",
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: true,
            aiAgentType: "claude"
        )
        XCTAssertEqual(claudeUser.avatarURL, "https://astrid.cc/images/ai-agents/claude.svg")

        // Test that a non-AI agent user returns their own image URL
        let normalUser = User(
            id: "normal-user",
            email: "test@example.com",
            name: "Test User",
            image: "https://example.com/test.jpg",
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: false,
            aiAgentType: nil
        )
        XCTAssertEqual(normalUser.avatarURL, "https://example.com/test.jpg")

        // Test user with no image
        let noImageUser = User(
            id: "no-image",
            email: "noimage@example.com",
            name: "No Image",
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: false,
            aiAgentType: nil
        )
        XCTAssertNil(noImageUser.avatarURL)
    }


    func testPendingUser() {
        let pendingUser = User(
            id: "pending-user",
            email: "invite@example.com",
            name: nil,
            image: nil,
            createdAt: nil,
            defaultDueTime: nil,
            isPending: true,
            isAIAgent: nil,
            aiAgentType: nil
        )

        XCTAssertTrue(pendingUser.isPending ?? false)
    }

    // MARK: - Equatable Tests

    @MainActor func testUserEquality() {
        let user1 = TestHelpers.createTestUser(id: "same-id", name: "User One")
        let user2 = TestHelpers.createTestUser(id: "same-id", name: "User One")

        XCTAssertEqual(user1, user2)
    }

    @MainActor func testUserInequality() {
        let user1 = TestHelpers.createTestUser(id: "user-1", name: "User One")
        let user2 = TestHelpers.createTestUser(id: "user-2", name: "User Two")

        XCTAssertNotEqual(user1, user2)
    }

    // MARK: - Hashable Tests

    @MainActor func testUserHashable() {
        let user = TestHelpers.createTestUser(id: "hash-user")

        var userSet = Set<User>()
        userSet.insert(user)

        XCTAssertTrue(userSet.contains(user))
    }

    @MainActor func testUserInDictionary() {
        let user1 = TestHelpers.createTestUser(id: "user-1")
        let user2 = TestHelpers.createTestUser(id: "user-2")

        var dict: [User: String] = [:]
        dict[user1] = "First"
        dict[user2] = "Second"

        XCTAssertEqual(dict[user1], "First")
        XCTAssertEqual(dict[user2], "Second")
    }
}
