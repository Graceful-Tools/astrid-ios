import XCTest
@testable import Astrid_App

/// Regression tests for the "canonical control points" audit.
///
/// The audit fixed several places in the app where views or non-service
/// modules called `AstridAPIClient` directly and bypassed the service
/// layer (which owns optimistic updates + offline queue + dedup). These
/// tests lock down:
///
/// 1. The JSON wire shape of `MyTasksPreferences` and `UserSettings` so
///    a rename or field removal is caught at unit-test time — iOS and
///    web must stay aligned on these endpoints.
/// 2. That `ListMemberService` exposes the four methods every caller
///    is expected to use (addMember, updateMemberRole, removeMember,
///    cancelInvitation). A compile-time contract check — if any is
///    renamed or removed, the test fails to build, forcing an update
///    of callers and CLAUDE.md together.
/// 3. That `ChatService` exposes the AI-assistant helpers so the
///    ChatInputView on-device-Astrid path has a canonical entry point.
final class CanonicalControlPointsTests: XCTestCase {

    // MARK: - MyTasksPreferences wire contract

    func testMyTasksPreferences_JSONRoundTrip() throws {
        let prefs = MyTasksPreferences(
            filterPriority: [1, 2, 3],
            filterAssignee: ["u1", "u2"],
            filterDueDate: "week",
            filterCompletion: "default",
            sortBy: "priority",
            manualSortOrder: ["t1", "t2"]
        )
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(MyTasksPreferences.self, from: data)
        XCTAssertEqual(decoded.filterPriority, [1, 2, 3])
        XCTAssertEqual(decoded.filterAssignee, ["u1", "u2"])
        XCTAssertEqual(decoded.filterDueDate, "week")
        XCTAssertEqual(decoded.filterCompletion, "default")
        XCTAssertEqual(decoded.sortBy, "priority")
        XCTAssertEqual(decoded.manualSortOrder, ["t1", "t2"])
    }

    /// Lock down the exact field names the web's `/api/user/my-tasks-preferences`
    /// endpoint expects. Changing any of these without coordinating with the web
    /// will silently drop a field on PATCH.
    func testMyTasksPreferences_WireFieldNames() throws {
        let prefs = MyTasksPreferences(
            filterPriority: [1],
            filterAssignee: ["u"],
            filterDueDate: "overdue",
            filterCompletion: "hide",
            sortBy: "auto",
            manualSortOrder: nil
        )
        let data = try JSONEncoder().encode(prefs)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["filterPriority"] as? [Int], [1])
        XCTAssertEqual(json["filterAssignee"] as? [String], ["u"])
        XCTAssertEqual(json["filterDueDate"] as? String, "overdue")
        XCTAssertEqual(json["filterCompletion"] as? String, "hide")
        XCTAssertEqual(json["sortBy"] as? String, "auto")
    }

    // MARK: - UserSettings wire contract

    func testUserSettings_JSONRoundTrip() throws {
        let settings = UserSettings(
            smartTaskCreationEnabled: false,
            emailToTaskEnabled: true,
            defaultTaskDueOffset: "2_weeks",
            defaultDueTime: "09:00",
            subtaskDisplay: "under_parent"
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded.smartTaskCreationEnabled, false)
        XCTAssertEqual(decoded.emailToTaskEnabled, true)
        XCTAssertEqual(decoded.defaultTaskDueOffset, "2_weeks")
        XCTAssertEqual(decoded.defaultDueTime, "09:00")
        XCTAssertEqual(decoded.subtaskDisplay, "under_parent")
    }

    func testUserSettings_WireFieldNames() throws {
        let settings = UserSettings(
            smartTaskCreationEnabled: true,
            emailToTaskEnabled: false,
            defaultTaskDueOffset: "1_day",
            defaultDueTime: "17:00",
            subtaskDisplay: "indented"
        )
        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["smartTaskCreationEnabled"] as? Bool, true)
        XCTAssertEqual(json["emailToTaskEnabled"] as? Bool, false)
        XCTAssertEqual(json["defaultTaskDueOffset"] as? String, "1_day")
        XCTAssertEqual(json["defaultDueTime"] as? String, "17:00")
        XCTAssertEqual(json["subtaskDisplay"] as? String, "indented")
    }

    // MARK: - ListMemberService method contract
    //
    // This is a compile-time contract: if any of the four canonical methods
    // is renamed or removed, this test stops compiling and the caller audit
    // has to run again. Each assertion is `XCTAssertNotNil` on a tuple of
    // method references — we don't actually invoke them (that would need
    // network/CoreData mocks) but we prove they exist with the expected
    // signatures.

    @MainActor
    func testListMemberService_HasCanonicalMethods() {
        let service = ListMemberService.shared
        // Reference each expected method so a rename breaks the build here.
        let add: (String, String, String) async throws -> ListMember = { listId, email, role in
            try await service.addMember(listId: listId, email: email, role: role)
        }
        let update: (String, String, String) async throws -> Void = { listId, userId, role in
            try await service.updateMemberRole(listId: listId, userId: userId, role: role)
        }
        let remove: (String, String) async throws -> Void = { listId, userId in
            try await service.removeMember(listId: listId, userId: userId)
        }
        let cancel: (String, String, String) async throws -> Void = { listId, invitationId, email in
            try await service.cancelInvitation(listId: listId, invitationId: invitationId, email: email)
        }
        XCTAssertNotNil(add)
        XCTAssertNotNil(update)
        XCTAssertNotNil(remove)
        XCTAssertNotNil(cancel)
    }

    // MARK: - ChatService AI-assistant method contract

    @MainActor
    func testChatService_HasAIAssistantHelpers() {
        let service = ChatService.shared
        let getSettings: () async throws -> AIAssistantSettings = {
            try await service.getAIAssistantSettings()
        }
        let post: (String, String) async throws -> Void = { channelId, content in
            try await service.postAgentResponse(channelId: channelId, content: content)
        }
        let updateSettings: (String?) async throws -> AIAssistantSettings = { agentId in
            try await service.updateAIAssistantSettings(defaultAgentId: agentId)
        }
        let getAgents: () async throws -> [AvailableAgent] = {
            try await service.fetchAvailableAgents()
        }
        let getAgentUsers: () async throws -> [User] = {
            try await service.fetchAvailableAgentUsers()
        }
        let refreshMessages: (String) async throws -> [ChatMessage] = { channelId in
            try await service.refreshMessagesFromServer(channelId: channelId)
        }
        XCTAssertNotNil(getSettings)
        XCTAssertNotNil(post)
        XCTAssertNotNil(updateSettings)
        XCTAssertNotNil(getAgents)
        XCTAssertNotNil(getAgentUsers)
        XCTAssertNotNil(refreshMessages)
        // Invalidate the TTL cache from any caller that mutates the setting.
        service.invalidateAIAssistantSettingsCache()
    }

    // MARK: - Task/List service boundary method contracts

    @MainActor
    func testTaskService_HasServerFirstAndFeaturedListHelpers() {
        let service = TaskService.shared
        let updateServerFirst: (String, UpdateTaskRequest) async throws -> Task = { taskId, updates in
            try await service.updateTaskOnServer(taskId: taskId, updates: updates)
        }
        let fetchListTasks: (String) async throws -> [Task] = { listId in
            try await service.fetchTasksForListFromServer(listId)
        }
        XCTAssertNotNil(updateServerFirst)
        XCTAssertNotNil(fetchListTasks)
    }

    @MainActor
    func testListService_HasServerFirstHelpers() {
        let service = ListService.shared
        let leave: (String) async throws -> Void = { listId in
            try await service.leaveList(listId: listId)
        }
        let updateServerFirst: (String, UpdateListRequest) async throws -> TaskList = { listId, updates in
            try await service.updateListOnServer(listId: listId, updates: updates)
        }
        XCTAssertNotNil(leave)
        XCTAssertNotNil(updateServerFirst)
    }

    func testRefactoredViews_DoNotCallAstridAPIClientDirectly() throws {
        let root = try repositoryRoot()
        let auditedViews = [
            "Astrid App/Views/Tasks/TaskDetailViewNew.swift",
            "Astrid App/Views/Tasks/TaskListView.swift",
            "Astrid App/Views/Chat/ChatPanelView.swift",
            "Astrid App/Views/Lists/ListAgentSettingsView.swift",
            "Astrid App/Views/Lists/ListSettingsModal.swift",
            "Astrid App/Views/Settings/DefaultAgentPickerView.swift"
        ]

        for relativePath in auditedViews {
            let url = root.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url)
            XCTAssertFalse(
                source.contains("AstridAPIClient.shared"),
                "\(relativePath) must route backend work through a service layer"
            )
        }
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "astrid-ios" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
    }

    // MARK: - AstridAPIClient exposes the preferences endpoints

    @MainActor
    func testAstridAPIClient_HasPreferenceMethods() {
        let client = AstridAPIClient.shared
        let getMT: () async throws -> MyTasksPreferences = {
            try await client.getMyTasksPreferences()
        }
        let updateMT: (MyTasksPreferences) async throws -> Void = { prefs in
            try await client.updateMyTasksPreferences(prefs)
        }
        let getST: () async throws -> UserSettings = {
            try await client.getSmartTaskSettings()
        }
        let updateST: (UserSettings) async throws -> Void = { s in
            try await client.updateSmartTaskSettings(s)
        }
        XCTAssertNotNil(getMT)
        XCTAssertNotNil(updateMT)
        XCTAssertNotNil(getST)
        XCTAssertNotNil(updateST)
    }

    // MARK: - Preferences optimistic UserDefaults writes

    /// The optimistic + UserDefaults story (change the preferences, the value
    /// is persisted locally before any network call) is the whole reason we
    /// kept the services instead of calling the API directly from views. This
    /// test exercises that contract end-to-end on `MyTasksPreferencesService`
    /// without touching the network.
    @MainActor
    func testMyTasksPreferencesService_WritesToUserDefaultsOptimistically() async {
        let service = MyTasksPreferencesService.shared
        let sentinel = "test-sentinel-\(UUID().uuidString)"
        let updates = MyTasksPreferences(
            filterPriority: [99],
            filterAssignee: [sentinel],
            filterDueDate: "test",
            filterCompletion: "test",
            sortBy: "test",
            manualSortOrder: nil
        )

        await service.updatePreferences(updates)

        // UserDefaults write happens synchronously before the debounced
        // network call fires, so we can read it back immediately.
        let data = UserDefaults.standard.data(forKey: "my_tasks_preferences")
        XCTAssertNotNil(data, "Preferences must persist to UserDefaults before network")
        let decoded = try? JSONDecoder().decode(MyTasksPreferences.self, from: data ?? Data())
        XCTAssertEqual(decoded?.filterAssignee, [sentinel])
        XCTAssertEqual(decoded?.filterPriority, [99])

        // In-memory published state reflects the same value.
        XCTAssertEqual(service.preferences.filterAssignee, [sentinel])
    }
}
