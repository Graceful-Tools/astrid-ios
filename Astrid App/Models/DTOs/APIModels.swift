import Foundation

// MARK: - Request DTOs

struct SignUpPasswordlessRequest: Codable {
    let email: String
    let name: String?
}

struct SignUpResponse: Codable {
    let success: Bool
    let message: String?
}

struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let user: String
    let email: String?
    let fullName: String?
}

struct GoogleSignInRequest: Codable {
    let idToken: String
}

struct UpdateAccountRequest: Codable {
    var name: String?
    var email: String?
    var image: String?
}

struct DeleteAccountRequest: Codable {
    let confirmationText: String
}

struct CreateTaskRequest: Codable {
    var title: String
    var description: String?
    var priority: Int?
    var repeating: String?
    var repeatingData: CustomRepeatingPattern?
    var repeatFrom: String?  // "DUE_DATE" or "COMPLETION_DATE"
    var isPrivate: Bool?
    var dueDateTime: String?  // Primary datetime field (ISO8601)
    var isAllDay: Bool?  // Whether this is an all-day task
    var reminderTime: String? // ISO8601
    var reminderType: String?
    var listIds: [String]?
    var assigneeId: String?
    var assigneeEmail: String?
    var clientRequestId: String?  // Idempotency key for dedup (server unique constraint)
    var timerDuration: Int?
    var parentTaskId: String?  // Subtasks: parent task id (nil = top-level)
}

struct UpdateTaskRequest: Codable {
    var title: String?
    var description: String?
    var priority: Int?
    var repeating: String?
    var repeatingData: CustomRepeatingPattern?
    var repeatFrom: String?  // "DUE_DATE" or "COMPLETION_DATE"
    var isPrivate: Bool?
    var completed: Bool?
    var dueDateTime: String?  // Primary datetime field (ISO8601)
    var isAllDay: Bool?  // Whether this is an all-day task
    var reminderTime: String?
    var reminderType: String?
    var listIds: [String]?
    var assigneeId: String?
    var timerDuration: Int?
    var lastTimerValue: String?

    // Track which fields were explicitly set (including to nil)
    private var explicitlySetFields: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case title, description, priority, repeating
        case repeatingData
        case repeatFrom, isPrivate, completed
        case dueDateTime, isAllDay, reminderTime, reminderType
        case listIds, assigneeId, timerDuration, lastTimerValue
    }

    init(
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: String? = nil,
        isPrivate: Bool? = nil,
        completed: Bool? = nil,
        dueDateTime: String? = nil,
        isAllDay: Bool? = nil,
        reminderTime: String? = nil,
        reminderType: String? = nil,
        listIds: [String]? = nil,
        assigneeId: String? = nil,
        timerDuration: Int? = nil,
        lastTimerValue: String? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.repeating = repeating
        self.repeatingData = repeatingData
        self.repeatFrom = repeatFrom
        self.isPrivate = isPrivate
        self.completed = completed
        self.dueDateTime = dueDateTime
        self.isAllDay = isAllDay
        self.reminderTime = reminderTime
        self.reminderType = reminderType
        self.listIds = listIds
        self.assigneeId = assigneeId
        self.timerDuration = timerDuration
        self.lastTimerValue = lastTimerValue
    }

    // Custom encode to include explicit nil values
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Only encode fields that were actually set in the initializer
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(repeating, forKey: .repeating)
        try container.encodeIfPresent(repeatingData, forKey: .repeatingData)
        try container.encodeIfPresent(repeatFrom, forKey: .repeatFrom)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        try container.encodeIfPresent(completed, forKey: .completed)

        // Always encode dueDateTime if set (including empty string for clearing)
        if let dueDateTime = dueDateTime {
            try container.encode(dueDateTime, forKey: .dueDateTime)
        }

        // Always encode isAllDay if dueDateTime is set
        if dueDateTime != nil {
            try container.encodeIfPresent(isAllDay, forKey: .isAllDay)
        }

        try container.encodeIfPresent(reminderTime, forKey: .reminderTime)
        try container.encodeIfPresent(reminderType, forKey: .reminderType)
        try container.encodeIfPresent(listIds, forKey: .listIds)
        try container.encodeIfPresent(assigneeId, forKey: .assigneeId)
        try container.encodeIfPresent(timerDuration, forKey: .timerDuration)
        try container.encodeIfPresent(lastTimerValue, forKey: .lastTimerValue)
    }
}

struct CreateListRequest: Codable {
    var name: String
    var description: String?
    var color: String?
    var imageUrl: String?
    var privacy: String
    var adminIds: [String]?
    var memberIds: [String]?
    var memberEmails: [String]?
    var defaultAssigneeId: String?
    var defaultPriority: Int?
    var defaultRepeating: String?
    var defaultIsPrivate: Bool?
    var defaultDueDate: String?
}

struct UpdateListRequest: Codable {
    var name: String?
    var description: String?
    var color: String?
    var imageUrl: String?
    var privacy: String?
    var isFavorite: Bool?
    var defaultAssigneeId: String?
    var defaultPriority: Int?
    var defaultRepeating: String?
    var defaultIsPrivate: Bool?
    var defaultDueDate: String?
    var defaultDueTime: String?
    // Virtual list settings
    var isVirtual: Bool?
    var virtualListType: String?
    // Sort and filter settings
    var sortBy: String?
    var manualSortOrder: [String]?
    var filterPriority: String?
    var filterAssignee: String?
    var filterDueDate: String?
    var filterCompletion: String?
    var filterRepeating: String?
    var filterAssignedBy: String?
    var filterInLists: String?
    // Project status board (round-trips via PUT /api/v1/lists/[id]).
    // `projectId` is set/unset implicitly via project create/delete on the
    // server; iOS rarely needs to send it directly. `recentlyCompletedWindow`
    // is sent by the list admin Recently-completed-window picker.
    var projectId: String?
    var recentlyCompletedWindow: RecentlyCompletedWindow?
}

// MARK: - Projects (status boards)

struct CreateProjectRequest: Codable {
    var name: String
    var description: String?
    var color: String?
    var imageUrl: String?
}

/// Body for the atomic Create Board endpoint (`POST /api/v1/projects/from-list`):
/// creates a project AND attaches the list in one transaction, replacing the
/// two-step flow that could orphan a project.
struct CreateBoardFromListRequest: Codable {
    var listId: String
}

struct ProjectsResponse: Codable {
    var projects: [Project]
}

struct ProjectResponse: Codable {
    var project: Project
}

struct DeleteProjectResponse: Codable {
    var success: Bool
    var detachedListIds: [String]?
}

struct CreateCommentRequest: Codable {
    var content: String
    var type: String?
    var fileId: String?
    var parentCommentId: String?
    var createdAt: Date?  // Client timestamp for correct ordering
    var clientRequestId: String?  // Idempotency key — server dedups retries by this
}

// MARK: - Response DTOs

/// Lossy element wrapper: decoding never throws (even on a broken
/// element), so the surrounding array decode advances normally and
/// preserves every element that DID decode.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

struct TasksResponse: Codable {
    var tasks: [Task]
    var meta: TasksResponseMeta?

    enum CodingKeys: String, CodingKey { case tasks, meta }

    init(tasks: [Task], meta: TasksResponseMeta? = nil) {
        self.tasks = tasks
        self.meta = meta
    }

    /// Resilient array decode: a single bad task (unknown enum value,
    /// missing required field, schema drift) MUST NOT brick the
    /// entire response. One task with `priority: 4` returning 0 tasks
    /// total was the original bug — see TaskDecodingTests.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.meta = try container.decodeIfPresent(TasksResponseMeta.self, forKey: .meta)
        let failable = try container.decode([FailableDecodable<Task>].self, forKey: .tasks)
        let total = failable.count
        let kept = failable.compactMap { $0.value }
        if kept.count < total {
            print("⚠️ [TasksResponse] Dropped \(total - kept.count) un-decodable task(s) out of \(total)")
        }
        self.tasks = kept
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tasks, forKey: .tasks)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

struct TasksResponseMeta: Codable {
    var total: Int
    var limit: Int?
    var offset: Int?
}

struct ListsResponse: Codable {
    var lists: [TaskList]
}

struct CommentsResponse: Codable {
    var comments: [Comment]
}

struct SessionResponse: Codable {
    var user: User
}

struct ErrorResponse: Codable {
    var error: String
}

struct AccountResponse: Codable {
    let user: AccountData
}

struct AccountData: Codable {
    let id: String
    let name: String?
    let email: String
    let emailVerified: Date?
    let image: String?
    let pendingEmail: String?
    let createdAt: Date
    let updatedAt: Date
    let verified: Bool
    let hasPendingChange: Bool
    let hasPendingVerification: Bool
    let verifiedViaOAuth: Bool?
}

struct UpdateAccountResponse: Codable {
    let success: Bool
    let message: String
    let emailVerificationRequired: Bool?
}

struct VerifyEmailResponse: Codable {
    let success: Bool
    let message: String
}

struct DeleteAccountResponse: Codable {
    let success: Bool
    let message: String
}

struct UploadResponse: Codable {
    let url: String
    let name: String
    let size: Int
    let type: String
}

// MARK: - GitHub Integration

/// GitHub repository model matching API response from /api/v1/github/repositories
struct GitHubRepository: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let defaultBranch: String
    let `private`: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName
        case defaultBranch
        case `private`
    }
}

/// Response from /api/v1/github/repositories endpoint
struct GitHubRepositoriesResponse: Codable {
    let repositories: [GitHubRepository]
    let cached: Bool?
    let lastRefreshed: String?
}

/// Response from /api/v1/github/status endpoint
struct GitHubStatusResponse: Codable {
    let isGitHubConnected: Bool
    let hasAIKeys: Bool
    let hasMCPToken: Bool
    let repositoryCount: Int
    let mcpTokenCount: Int
    let isFullyConfigured: Bool
    let aiProviders: [String]
}

// MARK: - User Profile

/// User statistics
struct UserStats: Codable {
    let completed: Int
    let inspired: Int
    let supported: Int
}

/// User profile response from /api/v1/users/[userId]/profile
struct UserProfileResponse: Codable {
    let user: UserProfileData
    let stats: UserStats
    let sharedTasks: [Task]
    let isOwnProfile: Bool
}

/// User profile data (subset of User model with guaranteed fields)
struct UserProfileData: Codable {
    let id: String
    let name: String?
    let email: String
    let image: String?
    let createdAt: Date
    let isAIAgent: Bool?
    let aiAgentType: String?
}
