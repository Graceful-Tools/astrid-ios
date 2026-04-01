import XCTest
@testable import Astrid_App

/// Unit tests for list management functionality
/// Tests list creation, sharing, privacy settings, and member management
final class ListManagementTests: XCTestCase {

    // MARK: - List Creation Tests

    func testCreatePrivateList() {
        // Given: A new private list
        let list = TestHelpers.createTestList(
            id: "private-list",
            name: "My Private List",
            privacy: .PRIVATE
        )

        // Then: List should be private
        XCTAssertEqual(list.id, "private-list")
        XCTAssertEqual(list.name, "My Private List")
        XCTAssertEqual(list.privacy, .PRIVATE)
    }

    func testCreateSharedList() {
        // Given: A shared list
        let list = TestHelpers.createTestList(
            id: "shared-list",
            name: "Team List",
            privacy: .SHARED
        )

        // Then: List should be shared
        XCTAssertEqual(list.privacy, .SHARED)
    }

    func testCreatePublicList() {
        // Given: A public list
        let list = TestHelpers.createTestList(
            id: "public-list",
            name: "Public Wishlist",
            privacy: .PUBLIC
        )

        // Then: List should be public
        XCTAssertEqual(list.privacy, .PUBLIC)
    }

    func testCreateListWithColor() {
        // Given: A list with custom color
        let list = TestHelpers.createTestList(
            name: "Colored List",
            color: "#ff5733"
        )

        // Then: Color should be set
        XCTAssertEqual(list.color, "#ff5733")
        XCTAssertEqual(list.displayColor, "#ff5733")
    }

    func testListDefaultColor() {
        // Given: A list without custom color
        let list = TestHelpers.createTestList(color: nil)

        // Then: Should use default blue
        XCTAssertNil(list.color)
        XCTAssertEqual(list.displayColor, "#3b82f6")
    }

    func testCreateListWithDescription() {
        // Given: A list with description
        let list = TestHelpers.createTestList(
            name: "Project Alpha",
            description: "Tasks for Project Alpha development"
        )

        // Then: Description should be set
        XCTAssertEqual(list.description, "Tasks for Project Alpha development")
    }

    // MARK: - List Owner Tests

    func testListWithOwner() {
        // Given: A list with owner
        let owner = TestHelpers.createTestUser(id: "owner-123", name: "List Owner")
        let list = TestHelpers.createTestList(
            name: "My List",
            ownerId: owner.id,
            owner: owner
        )

        // Then: Owner should be set
        XCTAssertEqual(list.ownerId, "owner-123")
        XCTAssertNotNil(list.owner)
        XCTAssertEqual(list.owner?.name, "List Owner")
    }

    func testListOwnerCanSaveSettings() {
        // Note: This test would require AuthManager mock
        // Testing the logic pattern instead
        let owner = TestHelpers.createTestUser(id: "owner-123")
        let list = TestHelpers.createTestList(
            ownerId: owner.id,
            owner: owner
        )

        // Verify owner ID is set for permission checks
        XCTAssertEqual(list.ownerId, "owner-123")
    }

    // MARK: - List Sharing Tests

    func testAddMemberToList() {
        // Given: A list member
        let member = ListMember(
            id: "member-123",
            listId: "list-456",
            userId: "user-789",
            role: "MEMBER",
            createdAt: Date(),
            updatedAt: nil,
            user: TestHelpers.createTestUser(id: "user-789", name: "Team Member")
        )

        // Then: Member should have correct properties
        XCTAssertEqual(member.id, "member-123")
        XCTAssertEqual(member.listId, "list-456")
        XCTAssertEqual(member.userId, "user-789")
        XCTAssertEqual(member.role, "MEMBER")
        XCTAssertNotNil(member.user)
    }

    func testListMemberRoles() {
        // Given: Members with different roles
        let owner = ListMember(id: "1", listId: "list", userId: "user1", role: "OWNER", createdAt: nil, updatedAt: nil, user: nil)
        let admin = ListMember(id: "2", listId: "list", userId: "user2", role: "ADMIN", createdAt: nil, updatedAt: nil, user: nil)
        let member = ListMember(id: "3", listId: "list", userId: "user3", role: "MEMBER", createdAt: nil, updatedAt: nil, user: nil)

        // Then: Roles should be correct
        XCTAssertEqual(owner.role, "OWNER")
        XCTAssertEqual(admin.role, "ADMIN")
        XCTAssertEqual(member.role, "MEMBER")
    }

    func testCreateListInvite() {
        // Given: An invitation to join a list
        let invite = ListInvite(
            id: "invite-123",
            listId: "list-456",
            email: "newuser@example.com",
            role: "MEMBER",
            token: "abc123token",
            createdAt: Date(),
            createdBy: "owner-123"
        )

        // Then: Invite should have correct properties
        XCTAssertEqual(invite.id, "invite-123")
        XCTAssertEqual(invite.listId, "list-456")
        XCTAssertEqual(invite.email, "newuser@example.com")
        XCTAssertEqual(invite.role, "MEMBER")
        XCTAssertEqual(invite.token, "abc123token")
        XCTAssertEqual(invite.createdBy, "owner-123")
    }

    func testListWithMembers() {
        // Given: A list with multiple members
        let member1 = TestHelpers.createTestUser(id: "member-1", name: "Alice")
        let member2 = TestHelpers.createTestUser(id: "member-2", name: "Bob")

        let listMembers = [
            ListMember(id: "lm-1", listId: "list-1", userId: member1.id, role: "MEMBER", createdAt: nil, updatedAt: nil, user: member1),
            ListMember(id: "lm-2", listId: "list-1", userId: member2.id, role: "MEMBER", createdAt: nil, updatedAt: nil, user: member2)
        ]

        // Create a list with members inline
        let list = TaskList(
            id: "list-1",
            name: "Team List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: "owner-123",
            owner: nil,
            admins: nil,
            members: [member1, member2],
            listMembers: listMembers,
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: nil,
            updatedAt: nil,
            description: nil,
            tasks: nil,
            taskCount: nil,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        // Then: Members should be present
        XCTAssertEqual(list.members?.count, 2)
        XCTAssertEqual(list.listMembers?.count, 2)
    }

    // MARK: - List Permission Tests

    func testIsMemberAsOwner() {
        // Given: A list with owner
        let ownerId = "owner-123"
        let list = TestHelpers.createTestList(ownerId: ownerId)

        // Then: Owner should be a member
        XCTAssertTrue(list.isMember(userId: ownerId))
    }

    func testIsMemberAsListMember() {
        // Given: A list with members
        let memberId = "member-123"
        let member = TestHelpers.createTestUser(id: memberId)
        let listMember = ListMember(
            id: "lm-1",
            listId: "list-1",
            userId: memberId,
            role: "MEMBER",
            createdAt: nil,
            updatedAt: nil,
            user: member
        )

        let list = TaskList(
            id: "list-1",
            name: "Test List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: "owner-123",
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: [listMember],
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: nil,
            updatedAt: nil,
            description: nil,
            tasks: nil,
            taskCount: nil,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        // Then: Member should be recognized
        XCTAssertTrue(list.isMember(userId: memberId))
    }

    func testIsNotMember() {
        // Given: A list without the user as member
        let list = TestHelpers.createTestList(ownerId: "owner-123")

        // Then: Random user should not be a member
        XCTAssertFalse(list.isMember(userId: "random-user"))
    }

    // MARK: - List Default Settings Tests

    func testListDefaultAssignee() {
        // Given: A list with default assignee
        let list = TestHelpers.createTestList(defaultAssigneeId: "default-user")

        // Then: Default assignee should be set
        XCTAssertEqual(list.defaultAssigneeId, "default-user")
    }

    func testListDefaultPriority() {
        // Given: Lists with different default priorities
        let lowPriorityList = TestHelpers.createTestList(defaultPriority: 1)
        let highPriorityList = TestHelpers.createTestList(defaultPriority: 3)

        // Then: Default priorities should be set
        XCTAssertEqual(lowPriorityList.defaultPriority, 1)
        XCTAssertEqual(highPriorityList.defaultPriority, 3)
    }

    func testListDefaultRepeating() {
        // Given: A list with default repeating pattern
        let list = TestHelpers.createTestList(defaultRepeating: "weekly")

        // Then: Default repeating should be set
        XCTAssertEqual(list.defaultRepeating, "weekly")
    }

    // MARK: - Favorite List Tests

    func testFavoriteList() {
        // Given: A favorite list
        let list = TestHelpers.createTestList(isFavorite: true)

        // Then: Should be marked as favorite
        XCTAssertEqual(list.isFavorite, true)
    }

    func testNonFavoriteList() {
        // Given: A non-favorite list
        let list = TestHelpers.createTestList(isFavorite: false)

        // Then: Should not be marked as favorite
        XCTAssertEqual(list.isFavorite, false)
    }

    // MARK: - Virtual List Tests

    func testVirtualList() {
        // Given: A virtual list (like "Today" or "This Week")
        let list = TestHelpers.createTestList(isVirtual: true)

        // Then: Should be marked as virtual
        XCTAssertEqual(list.isVirtual, true)
    }

    func testRegularList() {
        // Given: A regular (non-virtual) list
        let list = TestHelpers.createTestList(isVirtual: false)

        // Then: Should not be virtual
        XCTAssertEqual(list.isVirtual, false)
    }

    // MARK: - Task Count Tests

    func testListTaskCount() {
        // Given: A list with task count
        let list = TestHelpers.createTestList(taskCount: 42)

        // Then: Task count should be set
        XCTAssertEqual(list.taskCount, 42)
    }

    func testListWithTasks() {
        // Given: A list with embedded tasks
        let task1 = TestHelpers.createTestTask(title: "Task 1")
        let task2 = TestHelpers.createTestTask(title: "Task 2")

        let list = TaskList(
            id: "list-with-tasks",
            name: "List with Tasks",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .PRIVATE,
            publicListType: nil,
            ownerId: nil,
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: nil,
            updatedAt: nil,
            description: nil,
            tasks: [task1, task2],
            taskCount: 2,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        // Then: Tasks should be present
        XCTAssertEqual(list.tasks?.count, 2)
        XCTAssertEqual(list.taskCount, 2)
    }

    // MARK: - AI/MCP Settings Tests

    func testListWithMCPEnabled() {
        // Given: A list with MCP enabled
        let list = TaskList(
            id: "mcp-list",
            name: "MCP Enabled List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .PRIVATE,
            publicListType: nil,
            ownerId: nil,
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: true,
            mcpAccessLevel: "FULL",
            aiAstridEnabled: true,
            preferredAiProvider: "claude",
            fallbackAiProvider: "openai",
            githubRepositoryId: nil,
            aiAgentsEnabled: ["claude", "gemini"],
            aiAgentConfiguredBy: "user-123",
            copyCount: nil,
            createdAt: nil,
            updatedAt: nil,
            description: nil,
            tasks: nil,
            taskCount: nil,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        // Then: MCP/AI settings should be set
        XCTAssertEqual(list.mcpEnabled, true)
        XCTAssertEqual(list.mcpAccessLevel, "FULL")
        XCTAssertEqual(list.aiAstridEnabled, true)
        XCTAssertEqual(list.preferredAiProvider, "claude")
        XCTAssertEqual(list.fallbackAiProvider, "openai")
        XCTAssertEqual(list.aiAgentsEnabled?.count, 2)
    }

    // MARK: - List Equality Tests

    func testListIdEquality() {
        // Given: Two lists with same ID
        let list1 = TestHelpers.createTestList(id: "same-id", name: "List 1")
        let list2 = TestHelpers.createTestList(id: "same-id", name: "List 2")

        // Then: Should have same ID
        XCTAssertEqual(list1.id, list2.id)
    }

    func testListIdInequality() {
        // Given: Two lists with different IDs
        let list1 = TestHelpers.createTestList(id: "list-1")
        let list2 = TestHelpers.createTestList(id: "list-2")

        // Then: Should have different IDs
        XCTAssertNotEqual(list1.id, list2.id)
    }

    // MARK: - List Hashable Tests

    @MainActor func testListHashable() {
        // Given: A list
        let list = TestHelpers.createTestList(id: "hash-test")

        // Then: Should work in Set
        var listSet = Set<TaskList>()
        listSet.insert(list)
        XCTAssertTrue(listSet.contains(list))
    }

    // MARK: - Complete Workflow Tests

    func testCreateAndShareListWorkflow() {
        // Simulates: User creates a list and shares it with a team member

        // Step 1: Create list
        let ownerId = "owner-123"
        let owner = TestHelpers.createTestUser(id: ownerId, name: "List Owner")

        let list = TestHelpers.createTestList(
            id: "team-list",
            name: "Project Tasks",
            color: "#3b82f6",
            privacy: .SHARED,
            ownerId: ownerId,
            owner: owner,
            description: "Tasks for our team project"
        )

        // Step 2: Add a team member
        let teamMemberId = "team-member-456"
        let teamMember = TestHelpers.createTestUser(id: teamMemberId, name: "Team Member")
        let listMember = ListMember(
            id: "lm-1",
            listId: list.id,
            userId: teamMemberId,
            role: "MEMBER",
            createdAt: Date(),
            updatedAt: nil,
            user: teamMember
        )

        // Verify the workflow
        XCTAssertEqual(list.privacy, .SHARED)
        XCTAssertEqual(list.ownerId, ownerId)
        XCTAssertTrue(list.isMember(userId: ownerId))
        XCTAssertEqual(listMember.role, "MEMBER")
        XCTAssertEqual(listMember.listId, list.id)
    }
}
