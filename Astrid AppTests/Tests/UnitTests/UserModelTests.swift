import XCTest
@testable import Astrid_App

/// Unit tests for User model
final class UserModelTests: XCTestCase {

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
}
