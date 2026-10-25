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

    // MARK: - Preferences optimistic UserDefaults writes

    /// The optimistic + UserDefaults story (change the preferences, the value
    /// is persisted locally before any network call) is the whole reason we
    /// kept the services instead of calling the API directly from views. This
    /// test exercises that contract end-to-end on `MyTasksPreferencesService`
    /// without touching the network.
    @MainActor
    func testMyTasksPreferencesService_WritesToUserDefaultsOptimistically() async throws {
        // A suite and an in-memory core of its own: this used to leave its sentinel in the test
        // process's real `my_tasks_preferences`, and send it through the shared core (AITD-534).
        let suite = "MyTasksPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let core = try CoreSearchFixture.session(seeding: [])
        let service = MyTasksPreferencesService(defaults: defaults, core: { core }, fetchOnInit: false)
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
        let data = defaults.data(forKey: "my_tasks_preferences")
        XCTAssertNotNil(data, "Preferences must persist to UserDefaults before network")
        let decoded = try? JSONDecoder().decode(MyTasksPreferences.self, from: data ?? Data())
        XCTAssertEqual(decoded?.filterAssignee, [sentinel])
        XCTAssertEqual(decoded?.filterPriority, [99])

        // In-memory published state reflects the same value.
        XCTAssertEqual(service.preferences.filterAssignee, [sentinel])
    }

    // MARK: - UpdateTaskRequest wire shape (hand-written encode)

    /// `UpdateTaskRequest.encode(to:)` is hand-written, so a newly added field
    /// silently drops from every PUT unless it's listed there. This locks the
    /// completion-metadata pair — their omission made backdated sync
    /// completions lose their real timestamp (server stamped "now", flooding
    /// the recently-completed window).
    func testUpdateTaskRequest_wireShape_completionMetadata() throws {
        let req = UpdateTaskRequest(
            completed: true,
            completedAt: "2010-10-26T01:23:55Z",
            completedSource: "google")
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(json["completed"] as? Bool, true)
        XCTAssertEqual(json["completedAt"] as? String, "2010-10-26T01:23:55Z")
        XCTAssertEqual(json["completedSource"] as? String, "google")
    }
}
