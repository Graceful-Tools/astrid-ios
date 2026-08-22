import Foundation

struct TaskList: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var color: String?
    var imageUrl: String?
    var coverImageUrl: String?
    var privacy: Privacy?  // Optional - not always returned in minimal API responses
    var publicListType: String?
    var ownerId: String?  // Optional - MCP API doesn't return this, only owner object
    var owner: User?
    var admins: [User]?
    var members: [User]?
    var listMembers: [ListMember]?
    var invitations: [ListInvite]?
    var defaultAssigneeId: String?
    var defaultAssignee: User?
    var defaultPriority: Int?
    var defaultRepeating: String?
    var defaultIsPrivate: Bool?
    var defaultDueDate: String?
    var defaultDueTime: String?
    var mcpEnabled: Bool?
    var mcpAccessLevel: String?
    var aiAstridEnabled: Bool?
    var preferredAiProvider: String?
    var fallbackAiProvider: String?
    var githubRepositoryId: String?
    var aiAgentsEnabled: [String]?
    var aiAgentConfiguredBy: String?
    var copyCount: Int?
    var createdAt: Date?
    var updatedAt: Date?
    var description: String?
    var tasks: [Task]?
    var taskCount: Int?
    var isFavorite: Bool?
    var favoriteOrder: Int?
    var isVirtual: Bool?
    var virtualListType: String?
    var sortBy: String?
    var manualSortOrder: [String]?
    /// Whether this list splices subtasks inline (task ba1deb9d). **nil means SHOW** — a list
    /// fetched before the field existed must render exactly as it did. See ListSubtaskVisibility.
    var showSubtasks: Bool?

    // Filter settings for virtual lists
    var filterCompletion: String?
    var filterDueDate: String?
    var filterAssignee: String?
    var filterAssignedBy: String?
    var filterRepeating: String?
    var filterPriority: String?
    var filterInLists: String?

    // ── Project status board (added 2026-05-12 for board parity) ─────
    //
    // `projectId` is set when this list belongs to a project. A project
    // contains both `listType: "regular"` (domain) lists and
    // `listType: "status"` (board column) lists. Inbox and Done are
    // virtual columns derived from task state and are never stored.
    var projectId: String?
    var listType: String?           // "regular" | "status"
    var statusRole: String?         // "ready" | "doing" | "waiting" | "custom" | "inbox" | "done"
    var statusOrder: Int?
    var statusDescription: String?
    var statusCompleted: Bool?
    /// Per-list "Recently completed" window config. `nil` falls back to
    /// the legacy 24h default. See `RecentlyCompletedWindow.swift`.
    var recentlyCompletedWindow: RecentlyCompletedWindow?

    enum Privacy: String, Codable {
        case PRIVATE, SHARED, PUBLIC
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, imageUrl, coverImageUrl, privacy, publicListType
        case ownerId, owner, admins, members, listMembers, invitations
        case defaultAssigneeId, defaultAssignee, defaultPriority, defaultRepeating
        case defaultIsPrivate, defaultDueDate, defaultDueTime
        case mcpEnabled, mcpAccessLevel, aiAstridEnabled
        case preferredAiProvider, fallbackAiProvider, githubRepositoryId, aiAgentsEnabled
        case aiAgentConfiguredBy, copyCount
        case createdAt, updatedAt, description, tasks, taskCount
        case isFavorite, favoriteOrder, isVirtual, virtualListType, sortBy, manualSortOrder
        case showSubtasks
        case filterCompletion, filterDueDate, filterAssignee, filterAssignedBy
        case filterRepeating, filterPriority, filterInLists
        case projectId, listType, statusRole, statusOrder
        case statusDescription, statusCompleted, recentlyCompletedWindow
    }
    
    var displayColor: String {
        color ?? "#3b82f6"
    }
}

struct ListMember: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var listId: String?
    let userId: String
    let role: String
    var createdAt: Date?
    var updatedAt: Date?
    var user: User?

    init(id: String, listId: String?, userId: String, role: String, createdAt: Date? = nil, updatedAt: Date? = nil, user: User? = nil) {
        self.id = id
        self.listId = listId
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.role = try container.decode(String.self, forKey: .role)
        self.listId = try container.decodeIfPresent(String.self, forKey: .listId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.user = try container.decodeIfPresent(User.self, forKey: .user)
        // id may be missing in embedded list member responses (e.g. create task)
        // Fall back to userId to satisfy Identifiable
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? userId
    }
}

struct ListInvite: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let listId: String
    let email: String
    let role: String
    let token: String
    var createdAt: Date?
    var createdBy: String?
}

// MARK: - TaskList Permission Checks
//
// These mirror `astrid-web/lib/list-permissions.ts` — `listMembers` is the
// canonical source of role information on both platforms. The legacy
// `admins` and `members` fields on this struct are kept only so Codable
// decoding still works against the `/api/v1/public/lists` endpoint
// (which synthesizes an `admins` array from `listMembers` for older
// clients). Do NOT consult them when determining a user's role —
// consulting them here would diverge from the web's permission checks.

extension TaskList {
    /// True for status/state rows (Ready/Doing/Waiting/custom project states),
    /// which are never rendered as ordinary lists in sidebars/pickers.
    var isStatusList: Bool { listType == "status" }

    /// True for list-shaped destinations users can navigate/file tasks into.
    var isDomainList: Bool { !isStatusList }

    /// User's role on this list. Returns nil if user has no access.
    /// Matches web's `getUserRoleInList`.
    func role(for userId: String) -> ListRole? {
        if ownerId == userId || owner?.id == userId {
            return .owner
        }
        if let listMembers = listMembers,
           listMembers.contains(where: { $0.userId == userId && $0.role == "admin" }) {
            return .admin
        }
        if let listMembers = listMembers,
           listMembers.contains(where: { $0.userId == userId && $0.role == "member" }) {
            return .member
        }
        if privacy == .PUBLIC {
            return .viewer
        }
        return nil
    }

    /// Check if the current user can access settings for this list.
    /// Returns true if user is owner or admin.
    func canUserSaveServerSettings() -> Bool {
        guard let currentUserId = AuthManager.shared.userId else { return false }
        let role = role(for: currentUserId)
        return role == .owner || role == .admin
    }

    /// Check if a user is a member of this list (owner, admin, or member).
    /// Used to determine if tasks in this list should be visible to the user.
    func isMember(userId: String) -> Bool {
        let role = role(for: userId)
        return role == .owner || role == .admin || role == .member
    }
}

enum ListRole: String {
    case owner, admin, member, viewer
}
