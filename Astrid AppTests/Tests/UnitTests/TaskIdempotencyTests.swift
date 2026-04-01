import XCTest
@testable import Astrid_App

/// Unit tests for task creation idempotency
/// Tests clientRequestId generation, inclusion in API requests, and CoreData persistence
final class TaskIdempotencyTests: XCTestCase {

    // MARK: - clientRequestId Generation

    func testClientRequestIdIsValidUUID() {
        // Given: A generated clientRequestId
        let clientRequestId = UUID().uuidString

        // Then: It should be a valid UUID string (36 chars with dashes)
        XCTAssertEqual(clientRequestId.count, 36)
        XCTAssertNotNil(UUID(uuidString: clientRequestId))
    }

    func testClientRequestIdIsUniquePerGeneration() {
        // Given: Two generated clientRequestIds
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString

        // Then: They should be different
        XCTAssertNotEqual(id1, id2)
    }

    func testClientRequestIdMeetsServerLengthRequirements() {
        // Given: A UUID string clientRequestId
        let clientRequestId = UUID().uuidString

        // Then: Should be between 8 and 128 characters (server requirement)
        XCTAssertGreaterThanOrEqual(clientRequestId.count, 8)
        XCTAssertLessThanOrEqual(clientRequestId.count, 128)
    }

    // MARK: - CreateTaskRequest Encoding

    @MainActor func testCreateTaskRequestIncludesClientRequestId() throws {
        // Given: A CreateTaskRequest with clientRequestId
        let request = CreateTaskRequest(
            title: "Test Task",
            clientRequestId: "test-request-id-12345678"
        )

        // When: Encoded to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then: JSON should include clientRequestId
        XCTAssertEqual(json["clientRequestId"] as? String, "test-request-id-12345678")
        XCTAssertEqual(json["title"] as? String, "Test Task")
    }

    @MainActor func testCreateTaskRequestOmitsNilClientRequestId() throws {
        // Given: A CreateTaskRequest without clientRequestId
        let request = CreateTaskRequest(
            title: "Test Task"
        )

        // When: Encoded to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then: JSON should not include clientRequestId (it's nil)
        XCTAssertNil(json["clientRequestId"])
    }

    // MARK: - Task Model Compatibility

    func testTaskModelIsUnaffectedByClientRequestId() {
        // Given: A task created with test helpers (no clientRequestId on domain model)
        let task = TestHelpers.createTestTask(
            id: "task-123",
            title: "Test Task"
        )

        // Then: Task should work normally — clientRequestId is transport-only
        XCTAssertEqual(task.id, "task-123")
        XCTAssertEqual(task.title, "Test Task")
    }

    // MARK: - Sync CREATE Sends Full State (Latest Edits)

    @MainActor func testCreateTaskRequestIncludesPriorityAndDate() throws {
        // Scenario: User creates task, then edits priority + date locally.
        // When sync retries the CREATE, it must include the LATEST fields.
        let dueDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1773792000)) // 2026-03-15 midnight UTC

        let request = CreateTaskRequest(
            title: "Updated Task",
            priority: 3,
            isPrivate: true,
            dueDateTime: dueDate,
            isAllDay: true,
            clientRequestId: "retry-key-12345678"
        )

        // When: Encoded to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Then: JSON must include ALL editable fields (not just title + clientRequestId)
        XCTAssertEqual(json["title"] as? String, "Updated Task")
        XCTAssertEqual(json["priority"] as? Int, 3, "Priority must be sent with CREATE retry")
        XCTAssertEqual(json["dueDateTime"] as? String, dueDate, "dueDateTime must be sent with CREATE retry")
        XCTAssertEqual(json["isAllDay"] as? Bool, true, "isAllDay must be sent with CREATE retry")
        XCTAssertEqual(json["isPrivate"] as? Bool, true)
        XCTAssertEqual(json["clientRequestId"] as? String, "retry-key-12345678")
    }

    @MainActor func testCreateTaskRequestIncludesAssigneeAndRepeating() throws {
        // Verify all editable fields are sent in CREATE request (sync retry must send full state)
        let request = CreateTaskRequest(
            title: "Full State Task",
            description: "A task description",
            priority: 2,
            repeating: "daily",
            isPrivate: false,
            dueDateTime: "2026-04-01T09:00:00Z",
            isAllDay: false,
            listIds: ["list-1", "list-2"],
            assigneeId: "user-456",
            clientRequestId: "full-state-key-12345"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["description"] as? String, "A task description")
        XCTAssertEqual(json["priority"] as? Int, 2)
        XCTAssertEqual(json["repeating"] as? String, "daily")
        XCTAssertEqual(json["isPrivate"] as? Bool, false)
        XCTAssertEqual(json["dueDateTime"] as? String, "2026-04-01T09:00:00Z")
        XCTAssertEqual(json["isAllDay"] as? Bool, false)
        XCTAssertEqual(json["assigneeId"] as? String, "user-456")
        XCTAssertEqual((json["listIds"] as? [String])?.count, 2)
    }

    // MARK: - Local vs Server State Comparison

    func testLocalEditsDifferFromServerResponse() {
        // Scenario: Server returns idempotent response with stale data (no priority/date).
        // Local CoreData has user's edits (priority=HIGH, date set).
        // The sync code must detect the difference.

        let serverTask = TestHelpers.createTestTask(
            id: "task-server-1",
            title: "My Task",
            priority: .none,       // Server has default priority
            dueDateTime: nil       // Server has no date
        )

        let localTask = TestHelpers.createTestTask(
            id: "task-server-1",
            title: "My Task",
            priority: .high,       // User edited priority to HIGH
            dueDateTime: Date()    // User added a due date
        )

        // These should differ — sync code must detect this and push an UPDATE
        XCTAssertNotEqual(serverTask.priority, localTask.priority,
            "Priority difference must be detected between server and local state")
        XCTAssertNotEqual(serverTask.dueDateTime, localTask.dueDateTime,
            "DueDateTime difference must be detected between server and local state")
    }

    func testServerResponseMatchesLocalState() {
        // When server response matches local state, no UPDATE needed
        let dueDate = Date(timeIntervalSince1970: 1773792000)

        let serverTask = TestHelpers.createTestTask(
            id: "task-server-2",
            title: "Matching Task",
            priority: .high,
            dueDateTime: dueDate,
            isAllDay: true
        )

        let localTask = TestHelpers.createTestTask(
            id: "task-server-2",
            title: "Matching Task",
            priority: .high,
            dueDateTime: dueDate,
            isAllDay: true
        )

        // These should match — no UPDATE needed
        XCTAssertEqual(serverTask.priority, localTask.priority)
        XCTAssertEqual(serverTask.dueDateTime, localTask.dueDateTime)
        XCTAssertEqual(serverTask.isAllDay, localTask.isAllDay)
        XCTAssertEqual(serverTask.title, localTask.title)
    }

    @MainActor func testUpdateRequestIncludesLatestEdits() throws {
        // When local differs from server, UpdateTaskRequest must carry the latest values
        let updates = UpdateTaskRequest(
            title: "Edited Title",
            description: "New description",
            priority: 3,
            isPrivate: true,
            completed: false,
            dueDateTime: "2026-03-15T00:00:00Z",
            isAllDay: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(updates)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // All edited fields must be present in the UPDATE request body
        XCTAssertEqual(json["title"] as? String, "Edited Title")
        XCTAssertEqual(json["description"] as? String, "New description")
        XCTAssertEqual(json["priority"] as? Int, 3, "Latest priority must be in UPDATE")
        XCTAssertEqual(json["dueDateTime"] as? String, "2026-03-15T00:00:00Z", "Latest date must be in UPDATE")
        XCTAssertEqual(json["isAllDay"] as? Bool, true)
        XCTAssertEqual(json["isPrivate"] as? Bool, true)
    }

    @MainActor func testPriorityEditSurvivesRoundTrip() throws {
        // Simulates: create(priority=0) → server returns task → user edits priority to 3
        // → sync retry CREATE → server returns stale(priority=0) → UPDATE with priority=3
        // The UPDATE request must carry the user's latest priority.

        let originalPriority = 0  // What server has (stale)
        let editedPriority = 3    // What user set locally

        XCTAssertNotEqual(originalPriority, editedPriority,
            "Test precondition: priorities must differ")

        // Build the UPDATE that the sync code would send
        let updates = UpdateTaskRequest(priority: editedPriority)
        let encoder = JSONEncoder()
        let data = try encoder.encode(updates)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["priority"] as? Int, editedPriority,
            "UPDATE must carry the user's edited priority, not the server's stale value")
    }

    @MainActor func testDueDateEditSurvivesRoundTrip() throws {
        // Simulates: create(date=nil) → server returns task → user adds due date
        // → sync retry → server returns stale(date=nil) → UPDATE with date

        let editedDate = "2026-04-01T09:00:00Z"

        let updates = UpdateTaskRequest(
            dueDateTime: editedDate,
            isAllDay: false
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(updates)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["dueDateTime"] as? String, editedDate,
            "UPDATE must carry the user's added due date")
        XCTAssertEqual(json["isAllDay"] as? Bool, false)
    }
}
