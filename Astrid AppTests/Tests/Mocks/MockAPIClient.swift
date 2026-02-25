import Foundation
@testable import Astrid_App

/// Mock API Client for testing offline scenarios and pending operations
@MainActor
class MockAPIClient {
    static let shared = MockAPIClient()

    // Simulation flags
    var shouldFailRequests = false
    var simulatedNetworkDelay: TimeInterval = 0.1
    var simulatedError: Error?

    // Response configuration
    var nextCommentId: String? // If set, use this ID for next comment creation
    var nextMember: ListMemberData? // If set, return this member (user exists)
    var nextMemberInvitation: InvitationData? // If set, return invitation (user doesn't exist)

    // Tracking for verification in tests
    var createCommentCalls: [(taskId: String, content: String, type: Comment.CommentType)] = []
    var updateCommentCalls: [(commentId: String, content: String)] = []
    var deleteCommentCalls: [String] = []
    var addMemberCalls: [(listId: String, email: String, role: String)] = []
    var updateMemberCalls: [(listId: String, userId: String, role: String)] = []
    var removeMemberCalls: [(listId: String, userId: String)] = []

    // Task operation tracking
    var createTaskCalls: [(title: String, listIds: [String]?)] = []
    var updateTaskCalls: [(id: String, title: String?)] = []
    var deleteTaskCalls: [String] = []

    // Task response configuration
    var nextTaskId: String? // If set, use this ID for next task creation

    /// Factory method for tests - creates a fresh instance
    static func createForTesting() -> MockAPIClient {
        let instance = MockAPIClient()
        instance.reset()
        return instance
    }

    init() {}

    // MARK: - Comment Operations

    /// Simulate creating a comment
    func createComment(
        taskId: String,
        content: String,
        type: Comment.CommentType = .TEXT,
        fileId: String? = nil,
        parentCommentId: String? = nil
    ) async throws -> CommentResponse {
        // Track the call
        createCommentCalls.append((taskId, content, type))

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        let commentId = nextCommentId ?? "server-\(UUID().uuidString)"
        let comment = Comment(
            id: commentId,
            content: content,
            type: type,
            authorId: "test-author",
            author: nil,
            taskId: taskId,
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: parentCommentId,
            replies: nil,
            secureFiles: nil
        )

        return CommentResponse(
            comment: comment,
            meta: MetaInfo(apiVersion: "1", authSource: "test")
        )
    }

    /// Simulate updating a comment
    func updateComment(
        commentId: String,
        content: String
    ) async throws -> CommentResponse {
        // Track the call
        updateCommentCalls.append((commentId, content))

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        let comment = Comment(
            id: commentId,
            content: content,
            type: .TEXT,
            authorId: "test-author",
            author: nil,
            taskId: "test-task",
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        return CommentResponse(
            comment: comment,
            meta: MetaInfo(apiVersion: "1", authSource: "test")
        )
    }

    /// Simulate deleting a comment
    func deleteComment(commentId: String) async throws -> DeleteResponse {
        // Track the call
        deleteCommentCalls.append(commentId)

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        return DeleteResponse(
            success: true,
            message: "Comment deleted successfully",
            meta: MetaInfo(apiVersion: "1", authSource: "test")
        )
    }

    // MARK: - Task Operations

    /// Simulate creating a task
    func createTask(
        title: String,
        listIds: [String]? = nil,
        description: String? = nil,
        priority: Int? = nil,
        assigneeId: String? = nil,
        dueDateTime: Date? = nil,
        isAllDay: Bool? = nil,
        isPrivate: Bool? = nil,
        repeating: String? = nil
    ) async throws -> Task {
        createTaskCalls.append((title, listIds))

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        let taskId = nextTaskId ?? "server-\(UUID().uuidString)"
        return TestHelpers.createTestTask(
            id: taskId,
            title: title,
            priority: Task.Priority(rawValue: priority ?? 0) ?? .none,
            dueDateTime: dueDateTime,
            isAllDay: isAllDay ?? true,
            assigneeId: assigneeId,
            listIds: listIds,
            isPrivate: isPrivate ?? true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Simulate updating a task
    func updateTask(
        id: String,
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        completed: Bool? = nil
    ) async throws -> Task {
        updateTaskCalls.append((id, title))

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        return TestHelpers.createTestTask(
            id: id,
            title: title ?? "Updated Task",
            priority: Task.Priority(rawValue: priority ?? 0) ?? .none,
            completed: completed ?? false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Simulate deleting a task
    func deleteTask(id: String) async throws {
        deleteTaskCalls.append(id)

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }
    }

    // MARK: - Test Utilities

    /// Reset all tracking and simulation state
    func reset() {
        shouldFailRequests = false
        simulatedNetworkDelay = 0.1
        simulatedError = nil
        createCommentCalls.removeAll()
        updateCommentCalls.removeAll()
        deleteCommentCalls.removeAll()
        createTaskCalls.removeAll()
        updateTaskCalls.removeAll()
        deleteTaskCalls.removeAll()
        nextTaskId = nil
    }

    // MARK: - List Member Operations

    /// Simulate adding a list member
    func addListMember(listId: String, email: String, role: String) async throws -> AddMemberResponse {
        // Track the call
        addMemberCalls.append((listId, email, role))

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        if let invitation = nextMemberInvitation {
            // User doesn't exist, return invitation
            return AddMemberResponse(
                message: "Invitation sent",
                member: nil,
                invitation: invitation,
                meta: MetaInfo(apiVersion: "v1", authSource: "session")
            )
        } else {
            // User exists, return member
            let member = nextMember ?? ListMemberData(
                id: "user-\(UUID().uuidString)",
                name: "Test User",
                email: email,
                image: nil,
                role: role,
                isOwner: false,
                isAdmin: role == "admin"
            )
            return AddMemberResponse(
                message: "Member added",
                member: member,
                invitation: nil,
                meta: MetaInfo(apiVersion: "v1", authSource: "session")
            )
        }
    }

    /// Simulate updating a member's role
    func updateListMember(listId: String, userId: String, role: String) async throws -> UpdateMemberResponse {
        // Track the call
        updateMemberCalls.append((listId, userId, role))

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        let member = ListMemberData(
            id: userId,
            name: "Test User",
            email: "test@example.com",
            image: nil,
            role: role,
            isOwner: false,
            isAdmin: role == "admin"
        )
        return UpdateMemberResponse(
            message: "Member updated",
            member: member,
            meta: MetaInfo(apiVersion: "v1", authSource: "session")
        )
    }

    /// Simulate removing a member
    func removeListMember(listId: String, userId: String) async throws -> DeleteResponse {
        // Track the call
        removeMemberCalls.append((listId, userId))

        // Simulate network delay
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(simulatedNetworkDelay * 1_000_000_000))

        // Fail if configured
        if shouldFailRequests {
            throw simulatedError ?? MockAPIError.networkUnavailable
        }

        // Return mock response
        return DeleteResponse(
            success: true,
            message: "Member removed",
            meta: MetaInfo(apiVersion: "v1", authSource: "session")
        )
    }

    // MARK: - Test Helpers

    /// Simulate going offline
    func simulateOffline() {
        shouldFailRequests = true
        simulatedError = MockAPIError.networkUnavailable
    }

    /// Simulate going online
    func simulateOnline() {
        shouldFailRequests = false
        simulatedError = nil
    }
}

// MARK: - Mock Errors

enum MockAPIError: Error, LocalizedError {
    case networkUnavailable
    case serverError
    case unauthorized
    case notFound

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network unavailable"
        case .serverError:
            return "Server error"
        case .unauthorized:
            return "Unauthorized"
        case .notFound:
            return "Not found"
        }
    }
}
