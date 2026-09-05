import XCTest
@testable import Astrid_App

/// Unit tests for TaskList model and related types
final class TaskListModelTests: XCTestCase {

    // MARK: - Privacy Enum Tests

    func testPrivacyRawValues() {
        XCTAssertEqual(TaskList.Privacy.PRIVATE.rawValue, "PRIVATE")
        XCTAssertEqual(TaskList.Privacy.SHARED.rawValue, "SHARED")
        XCTAssertEqual(TaskList.Privacy.PUBLIC.rawValue, "PUBLIC")
    }

    // MARK: - Basic List Creation Tests

    func testCreateMinimalList() {
        let list = TaskList(
            id: "list-123",
            name: "My List",
            color: nil,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: nil,
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
            tasks: nil,
            taskCount: nil,
            isFavorite: nil,
            favoriteOrder: nil,
            isVirtual: nil
        )

        XCTAssertEqual(list.id, "list-123")
        XCTAssertEqual(list.name, "My List")
        XCTAssertNil(list.color)
        XCTAssertNil(list.privacy)
    }

    func testCreateFullList() {
        let owner = TestHelpers.createTestUser(id: "owner-123", name: "List Owner")

        let list = TestHelpers.createTestList(
            id: "full-list",
            name: "Full Featured List",
            color: "#ff0000",
            privacy: .SHARED,
            ownerId: "owner-123",
            owner: owner,
            description: "A full featured list with all options",
            taskCount: 42,
            isFavorite: true,
            isVirtual: false,
            defaultAssigneeId: "owner-123",
            defaultPriority: 2,
            defaultRepeating: "weekly"
        )

        XCTAssertEqual(list.id, "full-list")
        XCTAssertEqual(list.name, "Full Featured List")
        XCTAssertEqual(list.color, "#ff0000")
        XCTAssertEqual(list.privacy, .SHARED)
        XCTAssertEqual(list.ownerId, "owner-123")
        XCTAssertEqual(list.description, "A full featured list with all options")
        XCTAssertEqual(list.taskCount, 42)
        XCTAssertEqual(list.isFavorite, true)
        XCTAssertEqual(list.defaultAssigneeId, "owner-123")
        XCTAssertEqual(list.defaultPriority, 2)
        XCTAssertEqual(list.defaultRepeating, "weekly")
    }

    // MARK: - Display Color Tests

    func testDisplayColorWithColor() {
        let list = TestHelpers.createTestList(color: "#ff5733")
        XCTAssertEqual(list.displayColor, "#ff5733")
    }

    func testDisplayColorWithNilColor() {
        let list = TestHelpers.createTestList(color: nil)
        XCTAssertEqual(list.displayColor, "#3b82f6")  // Default blue
    }

    // MARK: - Privacy Tests

    func testPrivateList() {
        let list = TestHelpers.createTestList(privacy: .PRIVATE)
        XCTAssertEqual(list.privacy, .PRIVATE)
    }

    func testSharedList() {
        let list = TestHelpers.createTestList(privacy: .SHARED)
        XCTAssertEqual(list.privacy, .SHARED)
    }

    func testPublicList() {
        let list = TestHelpers.createTestList(privacy: .PUBLIC)
        XCTAssertEqual(list.privacy, .PUBLIC)
    }

    // MARK: - Virtual List Tests

    func testVirtualList() {
        let list = TestHelpers.createTestList(isVirtual: true)
        XCTAssertEqual(list.isVirtual, true)
    }

    func testNonVirtualList() {
        let list = TestHelpers.createTestList(isVirtual: false)
        XCTAssertEqual(list.isVirtual, false)
    }

    // MARK: - Favorite Tests

    func testFavoriteList() {
        let list = TestHelpers.createTestList(isFavorite: true)
        XCTAssertEqual(list.isFavorite, true)
    }

    func testNonFavoriteList() {
        let list = TestHelpers.createTestList(isFavorite: false)
        XCTAssertEqual(list.isFavorite, false)
    }

    // MARK: - Equatable Tests

    @MainActor func testListEquality() {
        let list1 = TestHelpers.createTestList(id: "same-id", name: "List")
        let list2 = TestHelpers.createTestList(id: "same-id", name: "List")

        XCTAssertEqual(list1, list2)
    }

    @MainActor func testListInequality() {
        let list1 = TestHelpers.createTestList(id: "list-1", name: "List One")
        let list2 = TestHelpers.createTestList(id: "list-2", name: "List Two")

        XCTAssertNotEqual(list1, list2)
    }

    // MARK: - Hashable Tests

    @MainActor func testListHashable() {
        let list = TestHelpers.createTestList(id: "hash-list")

        var listSet = Set<TaskList>()
        listSet.insert(list)

        XCTAssertTrue(listSet.contains(list))
    }

    // MARK: - ListMember Tests

    func testCreateListMember() {
        let member = ListMember(
            id: "member-123",
            listId: "list-456",
            userId: "user-789",
            role: "MEMBER",
            createdAt: Date(),
            updatedAt: nil,
            user: TestHelpers.createTestUser(id: "user-789")
        )

        XCTAssertEqual(member.id, "member-123")
        XCTAssertEqual(member.listId, "list-456")
        XCTAssertEqual(member.userId, "user-789")
        XCTAssertEqual(member.role, "MEMBER")
        XCTAssertNotNil(member.user)
    }

    func testListMemberRoles() {
        let owner = ListMember(id: "1", listId: "list", userId: "user1", role: "OWNER", createdAt: nil, updatedAt: nil, user: nil)
        let admin = ListMember(id: "2", listId: "list", userId: "user2", role: "ADMIN", createdAt: nil, updatedAt: nil, user: nil)
        let member = ListMember(id: "3", listId: "list", userId: "user3", role: "MEMBER", createdAt: nil, updatedAt: nil, user: nil)

        XCTAssertEqual(owner.role, "OWNER")
        XCTAssertEqual(admin.role, "ADMIN")
        XCTAssertEqual(member.role, "MEMBER")
    }

    // MARK: - ListInvite Tests

    func testCreateListInvite() {
        let invite = ListInvite(
            id: "invite-123",
            listId: "list-456",
            email: "invitee@example.com",
            role: "MEMBER",
            token: "abc123token",
            createdAt: Date(),
            createdBy: "inviter-user-id"
        )

        XCTAssertEqual(invite.id, "invite-123")
        XCTAssertEqual(invite.listId, "list-456")
        XCTAssertEqual(invite.email, "invitee@example.com")
        XCTAssertEqual(invite.role, "MEMBER")
        XCTAssertEqual(invite.token, "abc123token")
        XCTAssertEqual(invite.createdBy, "inviter-user-id")
    }

    // MARK: - List Default Settings Tests

    func testListDefaultAssignee() {
        let list = TestHelpers.createTestList(defaultAssigneeId: "default-user-123")
        XCTAssertEqual(list.defaultAssigneeId, "default-user-123")
    }

    func testListDefaultPriority() {
        let lowPriorityList = TestHelpers.createTestList(defaultPriority: 1)
        let highPriorityList = TestHelpers.createTestList(defaultPriority: 3)

        XCTAssertEqual(lowPriorityList.defaultPriority, 1)
        XCTAssertEqual(highPriorityList.defaultPriority, 3)
    }

    func testListDefaultRepeating() {
        let dailyList = TestHelpers.createTestList(defaultRepeating: "daily")
        let weeklyList = TestHelpers.createTestList(defaultRepeating: "weekly")

        XCTAssertEqual(dailyList.defaultRepeating, "daily")
        XCTAssertEqual(weeklyList.defaultRepeating, "weekly")
    }

    // MARK: - REGRESSION: Default Due Date Tests (Fix for stale list data)
    // Regression test for: iOS default due date "today" not being applied to tasks
    // Bug: QuickAddTaskView used nil when list not found in listService.lists instead of falling back to selectedList

    func testListDefaultDueDateToday() {
        // Given: A list with defaultDueDate = "today"
        let list = TestHelpers.createTestList(defaultDueDate: "today")

        // Then: defaultDueDate should be correctly set
        XCTAssertEqual(list.defaultDueDate, "today")
    }

    func testListDefaultDueDateTomorrow() {
        // Given: A list with defaultDueDate = "tomorrow"
        let list = TestHelpers.createTestList(defaultDueDate: "tomorrow")

        // Then: defaultDueDate should be correctly set
        XCTAssertEqual(list.defaultDueDate, "tomorrow")
    }

    func testListDefaultDueDateNextWeek() {
        // Given: A list with various due date defaults
        let list = TestHelpers.createTestList(defaultDueDate: "next_week")

        // Then: defaultDueDate should be correctly set
        XCTAssertEqual(list.defaultDueDate, "next_week")
    }

    func testListDefaultDueDateNone() {
        // Given: A list with no default due date
        let list = TestHelpers.createTestList(defaultDueDate: "none")

        // Then: defaultDueDate should be "none"
        XCTAssertEqual(list.defaultDueDate, "none")
    }

    func testListDefaultDueTime() {
        // Given: A list with a default due time
        let list = TestHelpers.createTestList(defaultDueTime: "09:00")

        // Then: defaultDueTime should be correctly set
        XCTAssertEqual(list.defaultDueTime, "09:00")
    }

    func testListDefaultDueTimeNil() {
        // Given: A list with no default due time (all-day tasks)
        let list = TestHelpers.createTestList(defaultDueTime: nil)

        // Then: defaultDueTime should be nil (all-day)
        XCTAssertNil(list.defaultDueTime)
    }

    func testListDefaultDueDateAndTimeCombo() {
        // Given: A list with both default due date and time
        // This represents: "Tasks created in this list default to due tomorrow at 9am"
        let list = TestHelpers.createTestList(
            defaultDueDate: "tomorrow",
            defaultDueTime: "09:00"
        )

        // Then: Both should be correctly set
        XCTAssertEqual(list.defaultDueDate, "tomorrow")
        XCTAssertEqual(list.defaultDueTime, "09:00")
    }

    func testListDefaultDueDateTodayAllDay() {
        // Given: A list with defaultDueDate = "today" and no time (all-day)
        // This is the specific case from the bug report
        let list = TestHelpers.createTestList(
            defaultDueDate: "today",
            defaultDueTime: nil
        )

        // Then: Should create all-day task due today
        XCTAssertEqual(list.defaultDueDate, "today")
        XCTAssertNil(list.defaultDueTime) // nil = all-day task
    }

    // MARK: - REGRESSION: Virtual List Defaults (Fix for priority/assignee not applied)
    // Regression test for: Virtual lists (like "Today") should respect their own defaults
    // Bug: QuickAddTaskView treated all virtual lists as "My Tasks" and ignored their defaults

    func testVirtualListWithDefaultPriority() {
        // Given: A virtual list (like "Today") with a default priority
        let list = TestHelpers.createTestList(
            isVirtual: true,
            defaultPriority: 2  // Medium priority
        )

        // Then: Virtual list should still have defaultPriority accessible
        XCTAssertEqual(list.isVirtual, true)
        XCTAssertEqual(list.defaultPriority, 2)
    }

    func testVirtualListWithDefaultAssignee() {
        // Given: A virtual list with a default assignee
        let list = TestHelpers.createTestList(
            isVirtual: true,
            defaultAssigneeId: "user-123"
        )

        // Then: Virtual list should still have defaultAssigneeId accessible
        XCTAssertEqual(list.isVirtual, true)
        XCTAssertEqual(list.defaultAssigneeId, "user-123")
    }

    func testVirtualListWithAllDefaults() {
        // Given: A virtual list (like "Today") with all defaults set
        // This simulates the "Today" list which has defaultDueDate: "today"
        let list = TestHelpers.createTestList(
            isVirtual: true,
            defaultAssigneeId: "user-456",
            defaultPriority: 3,
            defaultDueDate: "today",
            defaultDueTime: nil
        )

        // Then: All defaults should be accessible on virtual list
        XCTAssertEqual(list.isVirtual, true)
        XCTAssertEqual(list.defaultAssigneeId, "user-456")
        XCTAssertEqual(list.defaultPriority, 3)
        XCTAssertEqual(list.defaultDueDate, "today")
        XCTAssertNil(list.defaultDueTime)
    }

    func testDefaultAssigneeUnassigned() {
        // Given: A list with defaultAssigneeId = "unassigned"
        // This explicitly means "don't assign to anyone"
        let list = TestHelpers.createTestList(
            defaultAssigneeId: "unassigned"
        )

        // Then: Should have "unassigned" as the value
        XCTAssertEqual(list.defaultAssigneeId, "unassigned")
    }

    // MARK: - AI/MCP Settings Tests

    func testListWithMCPEnabled() {
        _ = TestHelpers.createTestList()
        // MCP settings are optional in factory, test full initialization
        let mcpList = TaskList(
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
            githubRepositoryId: "repo-123",
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

        XCTAssertEqual(mcpList.mcpEnabled, true)
        XCTAssertEqual(mcpList.mcpAccessLevel, "FULL")
        XCTAssertEqual(mcpList.aiAstridEnabled, true)
        XCTAssertEqual(mcpList.preferredAiProvider, "claude")
        XCTAssertEqual(mcpList.fallbackAiProvider, "openai")
        XCTAssertEqual(mcpList.githubRepositoryId, "repo-123")
        XCTAssertEqual(mcpList.aiAgentsEnabled?.count, 2)
    }

    // MARK: - List with Tasks Tests

    func testListWithTasks() {
        let task1 = TestHelpers.createTestTask(title: "Task 1")
        let task2 = TestHelpers.createTestTask(title: "Task 2")

        let list = TestHelpers.createTestList()
        // Create list with tasks inline
        let listWithTasks = TaskList(
            id: list.id,
            name: list.name,
            color: list.color,
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: list.privacy,
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

        XCTAssertEqual(listWithTasks.tasks?.count, 2)
        XCTAssertEqual(listWithTasks.taskCount, 2)
    }

    // MARK: - Board fields (added 2026-05-12)

    /// Status lists return all seven board fields under `/api/v1/lists/*`.
    /// This pins the iOS-side decoder against that contract.
    func testDecode_statusListIncludesAllBoardFields() throws {
        let json = """
        {
          "id": "l-ready",
          "name": "Ready",
          "projectId": "p1",
          "listType": "status",
          "statusRole": "ready",
          "statusOrder": 0,
          "statusDescription": "Time to get to work!",
          "statusCompleted": false,
          "recentlyCompletedWindow": null,
          "privacy": "SHARED",
          "ownerId": "u1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let list = try decoder.decode(TaskList.self, from: json)
        XCTAssertEqual(list.projectId, "p1")
        XCTAssertEqual(list.listType, "status")
        XCTAssertEqual(list.statusRole, "ready")
        XCTAssertEqual(list.statusOrder, 0)
        XCTAssertEqual(list.statusDescription, "Time to get to work!")
        XCTAssertEqual(list.statusCompleted, false)
        XCTAssertNil(list.recentlyCompletedWindow)
    }

    /// Legacy lists with no project attached return null/defaults — make
    /// sure the decoder treats those as absent without crashing.
    func testDecode_legacyListHasNilBoardFields() throws {
        let json = """
        {
          "id": "legacy",
          "name": "Legacy List",
          "privacy": "PRIVATE",
          "ownerId": "u1",
          "projectId": null,
          "listType": "regular",
          "statusRole": null,
          "statusOrder": null,
          "statusDescription": null,
          "statusCompleted": false,
          "recentlyCompletedWindow": null
        }
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(TaskList.self, from: json)
        XCTAssertNil(list.projectId)
        XCTAssertEqual(list.listType, "regular")
        XCTAssertNil(list.statusRole)
        XCTAssertNil(list.statusOrder)
        XCTAssertNil(list.statusDescription)
        XCTAssertEqual(list.statusCompleted, false)
        XCTAssertNil(list.recentlyCompletedWindow)
    }

    /// `recentlyCompletedWindow` is a discriminated union; iOS must decode
    /// every shape the web emits. Spot-check each kind.
    func testDecode_recentlyCompletedWindow_eachKind() throws {
        struct Wrap: Codable { var window: RecentlyCompletedWindow? }
        let cases: [(String, RecentlyCompletedWindow)] = [
            ("{\"kind\":\"duration\",\"amount\":7,\"unit\":\"day\"}",
             .duration(amount: 7, unit: .day)),
            ("{\"kind\":\"since-weekday\",\"weekday\":1}",
             .sinceWeekday(weekday: 1)),
            ("{\"kind\":\"since-day-of-month\",\"day\":15}",
             .sinceDayOfMonth(day: 15)),
            ("{\"kind\":\"since-date\",\"date\":\"2026-04-01\"}",
             .sinceDate(date: "2026-04-01")),
        ]
        for (windowJson, expected) in cases {
            let json = "{\"window\":\(windowJson)}".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(Wrap.self, from: json)
            XCTAssertEqual(decoded.window, expected)
        }
    }

    /// A TaskList carrying a recentlyCompletedWindow encodes it back as
    /// the same shape iOS receives — important for PUT round-trips.
    func testEncode_taskListWithWindow_roundTrips() throws {
        var list = TestHelpers.createTestList(id: "l-1", name: "List")
        list.projectId = "p-1"
        list.listType = "status"
        list.recentlyCompletedWindow = .duration(amount: 7, unit: .day)

        let data = try JSONEncoder().encode(list)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"projectId\":\"p-1\""))
        XCTAssertTrue(json.contains("\"listType\":\"status\""))
        XCTAssertTrue(json.contains("\"recentlyCompletedWindow\""))

        let decoded = try JSONDecoder().decode(TaskList.self, from: data)
        XCTAssertEqual(decoded.projectId, "p-1")
        XCTAssertEqual(decoded.recentlyCompletedWindow, .duration(amount: 7, unit: .day))
    }

    // MARK: - aiAgentsEnabled wire shapes

    /// Regression for the 2026-08-29 Mac log
    /// `typeMismatch … Path: lists[10].aiAgentsEnabled … Expected to decode Array<Any> but
    /// found a dictionary instead` — one list whose agent config had been saved on the web in the
    /// server's stored object form `{ enabledTypes, defaultAgentId }` failed the decode of the
    /// WHOLE `/api/v1/lists` response, and every list in the account disappeared ("offline mode,
    /// 0 lists"). The server now emits the array again plus a sibling `aiAgentConfig`, but the
    /// client must never let one field on one list zero the cache: an array, a dictionary, and
    /// null must all decode, and the other lists must survive whatever the eleventh one holds.
    func testDecode_aiAgentsEnabled_objectForm_doesNotZeroTheList() throws {
        let json = """
        {"lists":[
          {"id":"l-object","name":"Web-configured","createdAt":"2026-08-29T10:00:00.000Z",
           "aiAgentsEnabled":{"enabledTypes":["claude","coding"],"defaultAgentId":"agent-1"}},
          {"id":"l-array","name":"Legacy","aiAgentsEnabled":["claude"],
           "aiAgentConfig":{"enabledTypes":["claude"],"defaultAgentId":null}},
          {"id":"l-null","name":"Untouched","aiAgentsEnabled":null}
        ]}
        """
        let decoder = TaskListModelTests.apiDecoder()

        let response = try decoder.decode(ListsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.lists.map(\.id), ["l-object", "l-array", "l-null"])

        let object = response.lists[0]
        XCTAssertEqual(object.aiAgentsEnabled, ["claude", "coding"])
        XCTAssertEqual(object.aiAgentConfig?.enabledTypes, ["claude", "coding"],
                       "a dictionary carries the full config — keep it, it's what the web reads")
        XCTAssertEqual(object.aiAgentConfig?.defaultAgentId, "agent-1")

        let array = response.lists[1]
        XCTAssertEqual(array.aiAgentsEnabled, ["claude"])
        XCTAssertEqual(array.aiAgentConfig?.enabledTypes, ["claude"])
        XCTAssertNil(array.aiAgentConfig?.defaultAgentId)

        let untouched = response.lists[2]
        XCTAssertNil(untouched.aiAgentsEnabled)
        XCTAssertNil(untouched.aiAgentConfig, "absent on the wire stays absent — no invented config")
    }

    /// PUT bodies keep sending the array the server has always accepted.
    func testEncode_aiAgentsEnabled_staysAnArray() throws {
        var list = TestHelpers.createTestList(id: "l-1", name: "List")
        list.aiAgentsEnabled = ["claude"]

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(list), encoding: .utf8))

        XCTAssertTrue(json.contains("\"aiAgentsEnabled\":[\"claude\"]"), json)
    }

    /// Mirrors `AstridAPIClient`'s decoder (which is private): ISO8601 with or without
    /// fractional seconds. The field under test doesn't depend on it, but the payload above is
    /// what the real endpoint returns and should decode through the same configuration.
    private static func apiDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: dateString) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: dateString) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        return decoder
    }
}
