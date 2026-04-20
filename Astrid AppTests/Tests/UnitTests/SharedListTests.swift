import XCTest
@testable import Astrid_App

/// Unit tests for shared list functionality
/// Tests task creation in shared lists, task assignment, and collaboration features
final class SharedListTests: XCTestCase {

    // MARK: - Test Data Setup

    private func createSharedListWithMembers() -> (list: TaskList, owner: User, member: User) {
        let owner = TestHelpers.createTestUser(id: "owner-123", name: "List Owner", email: "owner@example.com")
        let member = TestHelpers.createTestUser(id: "member-456", name: "Team Member", email: "member@example.com")

        // Role strings are lowercase per server contract — match web's
        // `getUserRoleInList` which compares against exactly "admin" / "member".
        let listMember = ListMember(
            id: "lm-1",
            listId: "shared-list",
            userId: member.id,
            role: "member",
            createdAt: Date(),
            updatedAt: nil,
            user: member
        )

        let list = TaskList(
            id: "shared-list",
            name: "Team Project",
            color: "#3b82f6",
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: owner.id,
            owner: owner,
            admins: nil,
            members: [member],
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
            createdAt: Date(),
            updatedAt: nil,
            description: "A shared project list",
            tasks: nil,
            taskCount: 0,
            isFavorite: false,
            favoriteOrder: nil,
            isVirtual: false
        )

        return (list, owner, member)
    }

    // MARK: - Create Task in Shared List Tests

    func testCreateTaskInSharedList() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Creating a task in the shared list
        let task = TestHelpers.createTestTask(
            id: "shared-task-1",
            title: "Design the homepage",
            creatorId: owner.id,
            creator: owner,
            listIds: [list.id],
            lists: [list]
        )

        // Then: Task should be in the shared list
        XCTAssertEqual(task.listIds?.first, list.id)
        XCTAssertEqual(task.lists?.first?.privacy, .SHARED)
        XCTAssertTrue(task.isCreatedBy(owner.id))
    }

    func testMemberCreatesTaskInSharedList() {
        // Given: A shared list with a member
        let (list, _, member) = createSharedListWithMembers()

        // When: Member creates a task
        let task = TestHelpers.createTestTask(
            id: "member-task-1",
            title: "Implement feature",
            creatorId: member.id,
            creator: member,
            listIds: [list.id],
            lists: [list]
        )

        // Then: Task should be created by member in shared list
        XCTAssertTrue(task.isCreatedBy(member.id))
        XCTAssertEqual(task.listIds?.first, list.id)
    }

    func testCreateTaskWithPriorityInSharedList() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Creating a high-priority task
        let task = TestHelpers.createTestTask(
            title: "Urgent bug fix",
            priority: .high,
            creatorId: owner.id,
            listIds: [list.id],
            lists: [list]
        )

        // Then: Priority should be set correctly
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.priority.displayName, "High")
    }

    // MARK: - Assign Task in Shared List Tests

    func testAssignTaskToMember() {
        // Given: A shared list with owner and member
        let (list, owner, member) = createSharedListWithMembers()

        // When: Owner creates task and assigns it to member
        let task = TestHelpers.createTestTask(
            id: "assigned-task",
            title: "Complete the report",
            assigneeId: member.id,
            assignee: member,
            creatorId: owner.id,
            creator: owner,
            listIds: [list.id],
            lists: [list]
        )

        // Then: Task should be assigned to member
        XCTAssertEqual(task.assigneeId, member.id)
        XCTAssertNotNil(task.assignee)
        XCTAssertEqual(task.assignee?.name, "Team Member")
        XCTAssertTrue(task.isCreatedBy(owner.id))
    }

    func testAssignTaskToSelf() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Owner creates and assigns task to self
        let task = TestHelpers.createTestTask(
            title: "My task",
            assigneeId: owner.id,
            assignee: owner,
            creatorId: owner.id,
            creator: owner,
            listIds: [list.id]
        )

        // Then: Task should be self-assigned
        XCTAssertEqual(task.assigneeId, task.effectiveCreatorId)
    }

    func testUnassignedTaskInSharedList() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Creating an unassigned task
        let task = TestHelpers.createTestTask(
            title: "Unassigned task",
            assigneeId: nil,
            assignee: nil,
            creatorId: owner.id,
            listIds: [list.id]
        )

        // Then: Task should have no assignee
        XCTAssertNil(task.assigneeId)
        XCTAssertNil(task.assignee)
    }

    func testReassignTask() {
        // Given: A task assigned to member
        let (list, owner, member) = createSharedListWithMembers()
        let newAssignee = TestHelpers.createTestUser(id: "new-member", name: "New Member")

        // Create initial task assigned to member
        let task = TestHelpers.createTestTask(
            assigneeId: member.id,
            assignee: member,
            creatorId: owner.id,
            listIds: [list.id]
        )

        // When: Reassigning to new member (simulated by creating new task object)
        let reassignedTask = TestHelpers.createTestTask(
            id: task.id,
            title: task.title,
            assigneeId: newAssignee.id,
            assignee: newAssignee,
            creatorId: owner.id,
            listIds: [list.id]
        )

        // Then: Task should be assigned to new member
        XCTAssertEqual(reassignedTask.assigneeId, newAssignee.id)
        XCTAssertEqual(reassignedTask.assignee?.name, "New Member")
    }

    // MARK: - List Default Assignee Tests

    func testListWithDefaultAssignee() {
        // Given: A list with default assignee set
        let member = TestHelpers.createTestUser(id: "default-assignee", name: "Default Person")

        let list = TaskList(
            id: "list-default-assignee",
            name: "Auto-Assign List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: "owner-123",
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: member.id,
            defaultAssignee: member,
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

        // Then: Default assignee should be set
        XCTAssertEqual(list.defaultAssigneeId, member.id)
        XCTAssertEqual(list.defaultAssignee?.name, "Default Person")
    }

    // MARK: - Private Task in Shared List Tests

    func testPrivateTaskInSharedList() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Creating a private task in shared list
        let task = TestHelpers.createTestTask(
            title: "My private note",
            creatorId: owner.id,
            listIds: [list.id],
            isPrivate: true
        )

        // Then: Task should be marked as private
        XCTAssertTrue(task.isPrivate)
        XCTAssertEqual(task.listIds?.first, list.id)
    }

    func testPublicTaskInSharedList() {
        // Given: A shared list
        let (list, owner, _) = createSharedListWithMembers()

        // When: Creating a public (visible to all) task
        let task = TestHelpers.createTestTask(
            title: "Visible to all",
            creatorId: owner.id,
            listIds: [list.id],
            isPrivate: false
        )

        // Then: Task should not be private
        XCTAssertFalse(task.isPrivate)
    }

    // MARK: - Task Visibility Tests

    func testListMemberCanSeeTask() {
        // Given: A shared list with members
        let (list, _, member) = createSharedListWithMembers()

        // When: Checking if member can see tasks
        let isMemberOfList = list.isMember(userId: member.id)

        // Then: Member should have access
        XCTAssertTrue(isMemberOfList)
    }

    func testNonMemberCannotSeeTask() {
        // Given: A shared list
        let (list, _, _) = createSharedListWithMembers()

        // When: Checking if non-member can see tasks
        let isNonMemberOfList = list.isMember(userId: "random-user")

        // Then: Non-member should not have access
        XCTAssertFalse(isNonMemberOfList)
    }

    // MARK: - Task with Due Date in Shared List Tests

    func testCreateTaskWithDueDateInSharedList() {
        // Given: A shared list
        let (list, owner, member) = createSharedListWithMembers()
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 7)

        // When: Creating task with due date and assignment
        let task = TestHelpers.createTestTask(
            title: "Weekly report",
            dueDateTime: dueDate,
            isAllDay: false,
            assigneeId: member.id,
            assignee: member,
            creatorId: owner.id,
            listIds: [list.id]
        )

        // Then: Task should have due date and assignee
        XCTAssertNotNil(task.dueDateTime)
        XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.assigneeId, member.id)
    }

    // MARK: - Complete Workflow Tests

    func testCompleteSharedListWorkflow() {
        // Simulates: Full workflow of creating a shared list, adding members, creating and assigning tasks

        // Step 1: Create owner and members
        let owner = TestHelpers.createTestUser(id: "owner-1", name: "Project Manager", email: "pm@company.com")
        let dev1 = TestHelpers.createTestUser(id: "dev-1", name: "Developer 1", email: "dev1@company.com")
        let dev2 = TestHelpers.createTestUser(id: "dev-2", name: "Developer 2", email: "dev2@company.com")

        // Step 2: Create shared list
        let listMembers = [
            ListMember(id: "lm-1", listId: "project-list", userId: dev1.id, role: "member", createdAt: nil, updatedAt: nil, user: dev1),
            ListMember(id: "lm-2", listId: "project-list", userId: dev2.id, role: "member", createdAt: nil, updatedAt: nil, user: dev2)
        ]

        let projectList = TaskList(
            id: "project-list",
            name: "Sprint 1 Tasks",
            color: "#10b981",
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: owner.id,
            owner: owner,
            admins: nil,
            members: [dev1, dev2],
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
            createdAt: Date(),
            updatedAt: nil,
            description: "Sprint 1 development tasks",
            tasks: nil,
            taskCount: 0,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        // Step 3: Create and assign tasks
        let task1 = TestHelpers.createTestTask(
            id: "task-1",
            title: "Implement login feature",
            priority: .high,
            dueDateTime: TestHelpers.createRelativeDate(daysFromNow: 3),
            assigneeId: dev1.id,
            assignee: dev1,
            creatorId: owner.id,
            creator: owner,
            listIds: [projectList.id]
        )

        let task2 = TestHelpers.createTestTask(
            id: "task-2",
            title: "Design database schema",
            priority: .medium,
            dueDateTime: TestHelpers.createRelativeDate(daysFromNow: 5),
            assigneeId: dev2.id,
            assignee: dev2,
            creatorId: owner.id,
            creator: owner,
            listIds: [projectList.id]
        )

        let task3 = TestHelpers.createTestTask(
            id: "task-3",
            title: "Unassigned research task",
            priority: .low,
            creatorId: owner.id,
            creator: owner,
            listIds: [projectList.id]
        )

        // Verify the complete workflow
        XCTAssertEqual(projectList.privacy, .SHARED)
        XCTAssertTrue(projectList.isMember(userId: owner.id))
        XCTAssertTrue(projectList.isMember(userId: dev1.id))
        XCTAssertTrue(projectList.isMember(userId: dev2.id))

        XCTAssertEqual(task1.assigneeId, dev1.id)
        XCTAssertEqual(task1.priority, .high)

        XCTAssertEqual(task2.assigneeId, dev2.id)
        XCTAssertEqual(task2.priority, .medium)

        XCTAssertNil(task3.assigneeId)
        XCTAssertEqual(task3.priority, .low)

        // All tasks should be in the project list
        XCTAssertEqual(task1.listIds?.first, projectList.id)
        XCTAssertEqual(task2.listIds?.first, projectList.id)
        XCTAssertEqual(task3.listIds?.first, projectList.id)
    }

    // MARK: - Edge Cases

    func testEmptySharedList() {
        // Given: A shared list with no tasks
        let (list, _, _) = createSharedListWithMembers()

        // Then: Task count should be 0
        XCTAssertEqual(list.taskCount, 0)
    }

    func testSharedListWithMultipleMemberRoles() {
        // Given: A shared list with different member roles
        let owner = TestHelpers.createTestUser(id: "owner", name: "Owner")
        let admin = TestHelpers.createTestUser(id: "admin", name: "Admin")
        let member = TestHelpers.createTestUser(id: "member", name: "Member")

        // Server contract uses lowercase role strings.
        let listMembers = [
            ListMember(id: "lm-1", listId: "list-1", userId: admin.id, role: "admin", createdAt: nil, updatedAt: nil, user: admin),
            ListMember(id: "lm-2", listId: "list-1", userId: member.id, role: "member", createdAt: nil, updatedAt: nil, user: member)
        ]

        let list = TaskList(
            id: "list-1",
            name: "Multi-Role List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: .SHARED,
            publicListType: nil,
            ownerId: owner.id,
            owner: owner,
            admins: [admin],
            members: [member],
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

        // Then: All should be members
        XCTAssertTrue(list.isMember(userId: owner.id))
        XCTAssertTrue(list.isMember(userId: admin.id))
        XCTAssertTrue(list.isMember(userId: member.id))

        // Verify roles (lowercase per server contract).
        XCTAssertEqual(listMembers[0].role, "admin")
        XCTAssertEqual(listMembers[1].role, "member")
    }
}
