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
    /// Full per-list agent config as the server emits it beside `aiAgentsEnabled`
    /// (added 2026-08-29). Carries the default agent the array cannot express.
    var aiAgentConfig: ListAgentConfig?
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
        case preferredAiProvider, fallbackAiProvider, githubRepositoryId, aiAgentsEnabled, aiAgentConfig
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

    // MARK: - Memberwise init

    /// The memberwise init Swift stops synthesizing once `init(from:)` exists — same parameter
    /// order as the declarations above, every optional defaulting to nil, so call sites are unchanged.
    init(
        id: String,
        name: String,
        color: String? = nil,
        imageUrl: String? = nil,
        coverImageUrl: String? = nil,
        privacy: Privacy? = nil,
        publicListType: String? = nil,
        ownerId: String? = nil,
        owner: User? = nil,
        admins: [User]? = nil,
        members: [User]? = nil,
        listMembers: [ListMember]? = nil,
        invitations: [ListInvite]? = nil,
        defaultAssigneeId: String? = nil,
        defaultAssignee: User? = nil,
        defaultPriority: Int? = nil,
        defaultRepeating: String? = nil,
        defaultIsPrivate: Bool? = nil,
        defaultDueDate: String? = nil,
        defaultDueTime: String? = nil,
        mcpEnabled: Bool? = nil,
        mcpAccessLevel: String? = nil,
        aiAstridEnabled: Bool? = nil,
        preferredAiProvider: String? = nil,
        fallbackAiProvider: String? = nil,
        githubRepositoryId: String? = nil,
        aiAgentsEnabled: [String]? = nil,
        aiAgentConfig: ListAgentConfig? = nil,
        aiAgentConfiguredBy: String? = nil,
        copyCount: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        description: String? = nil,
        tasks: [Task]? = nil,
        taskCount: Int? = nil,
        isFavorite: Bool? = nil,
        favoriteOrder: Int? = nil,
        isVirtual: Bool? = nil,
        virtualListType: String? = nil,
        sortBy: String? = nil,
        manualSortOrder: [String]? = nil,
        showSubtasks: Bool? = nil,
        filterCompletion: String? = nil,
        filterDueDate: String? = nil,
        filterAssignee: String? = nil,
        filterAssignedBy: String? = nil,
        filterRepeating: String? = nil,
        filterPriority: String? = nil,
        filterInLists: String? = nil,
        projectId: String? = nil,
        listType: String? = nil,
        statusRole: String? = nil,
        statusOrder: Int? = nil,
        statusDescription: String? = nil,
        statusCompleted: Bool? = nil,
        recentlyCompletedWindow: RecentlyCompletedWindow? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.imageUrl = imageUrl
        self.coverImageUrl = coverImageUrl
        self.privacy = privacy
        self.publicListType = publicListType
        self.ownerId = ownerId
        self.owner = owner
        self.admins = admins
        self.members = members
        self.listMembers = listMembers
        self.invitations = invitations
        self.defaultAssigneeId = defaultAssigneeId
        self.defaultAssignee = defaultAssignee
        self.defaultPriority = defaultPriority
        self.defaultRepeating = defaultRepeating
        self.defaultIsPrivate = defaultIsPrivate
        self.defaultDueDate = defaultDueDate
        self.defaultDueTime = defaultDueTime
        self.mcpEnabled = mcpEnabled
        self.mcpAccessLevel = mcpAccessLevel
        self.aiAstridEnabled = aiAstridEnabled
        self.preferredAiProvider = preferredAiProvider
        self.fallbackAiProvider = fallbackAiProvider
        self.githubRepositoryId = githubRepositoryId
        self.aiAgentsEnabled = aiAgentsEnabled
        self.aiAgentConfig = aiAgentConfig
        self.aiAgentConfiguredBy = aiAgentConfiguredBy
        self.copyCount = copyCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.description = description
        self.tasks = tasks
        self.taskCount = taskCount
        self.isFavorite = isFavorite
        self.favoriteOrder = favoriteOrder
        self.isVirtual = isVirtual
        self.virtualListType = virtualListType
        self.sortBy = sortBy
        self.manualSortOrder = manualSortOrder
        self.showSubtasks = showSubtasks
        self.filterCompletion = filterCompletion
        self.filterDueDate = filterDueDate
        self.filterAssignee = filterAssignee
        self.filterAssignedBy = filterAssignedBy
        self.filterRepeating = filterRepeating
        self.filterPriority = filterPriority
        self.filterInLists = filterInLists
        self.projectId = projectId
        self.listType = listType
        self.statusRole = statusRole
        self.statusOrder = statusOrder
        self.statusDescription = statusDescription
        self.statusCompleted = statusCompleted
        self.recentlyCompletedWindow = recentlyCompletedWindow
    }

    // MARK: - Decoding

    /// Hand-written so that ONE field on ONE list can never fail the decode of the whole
    /// `/api/v1/lists` response. On 2026-08-29 a single list carrying `aiAgentsEnabled` in
    /// the server's stored object form `{ enabledTypes, defaultAgentId }` threw a typeMismatch
    /// at `lists[10].aiAgentsEnabled`, and because the array decodes as a unit, every list in
    /// the account vanished ("offline mode, 0 lists"). Everything else is decoded exactly as the
    /// synthesized init would; `encode(to:)` stays synthesized so PUT bodies keep sending the
    /// plain array the server has always accepted.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        coverImageUrl = try c.decodeIfPresent(String.self, forKey: .coverImageUrl)
        privacy = try c.decodeIfPresent(Privacy.self, forKey: .privacy)
        publicListType = try c.decodeIfPresent(String.self, forKey: .publicListType)
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        owner = try c.decodeIfPresent(User.self, forKey: .owner)
        admins = try c.decodeIfPresent([User].self, forKey: .admins)
        members = try c.decodeIfPresent([User].self, forKey: .members)
        listMembers = try c.decodeIfPresent([ListMember].self, forKey: .listMembers)
        invitations = try c.decodeIfPresent([ListInvite].self, forKey: .invitations)
        defaultAssigneeId = try c.decodeIfPresent(String.self, forKey: .defaultAssigneeId)
        defaultAssignee = try c.decodeIfPresent(User.self, forKey: .defaultAssignee)
        defaultPriority = try c.decodeIfPresent(Int.self, forKey: .defaultPriority)
        defaultRepeating = try c.decodeIfPresent(String.self, forKey: .defaultRepeating)
        defaultIsPrivate = try c.decodeIfPresent(Bool.self, forKey: .defaultIsPrivate)
        defaultDueDate = try c.decodeIfPresent(String.self, forKey: .defaultDueDate)
        defaultDueTime = try c.decodeIfPresent(String.self, forKey: .defaultDueTime)
        mcpEnabled = try c.decodeIfPresent(Bool.self, forKey: .mcpEnabled)
        mcpAccessLevel = try c.decodeIfPresent(String.self, forKey: .mcpAccessLevel)
        aiAstridEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiAstridEnabled)
        preferredAiProvider = try c.decodeIfPresent(String.self, forKey: .preferredAiProvider)
        fallbackAiProvider = try c.decodeIfPresent(String.self, forKey: .fallbackAiProvider)
        githubRepositoryId = try c.decodeIfPresent(String.self, forKey: .githubRepositoryId)

        // `aiAgentsEnabled`: the contract says string[], the server once leaked its stored
        // object form, and null/absent are both common. Accept all three.
        let sibling = try c.decodeIfPresent(ListAgentConfig.self, forKey: .aiAgentConfig)
        if let types = try? c.decodeIfPresent([String].self, forKey: .aiAgentsEnabled) {
            aiAgentsEnabled = types
            aiAgentConfig = sibling
        } else if let embedded = try? c.decodeIfPresent(ListAgentConfig.self, forKey: .aiAgentsEnabled) {
            aiAgentsEnabled = embedded.enabledTypes
            aiAgentConfig = sibling ?? embedded
        } else {
            aiAgentsEnabled = nil
            aiAgentConfig = sibling
        }

        aiAgentConfiguredBy = try c.decodeIfPresent(String.self, forKey: .aiAgentConfiguredBy)
        copyCount = try c.decodeIfPresent(Int.self, forKey: .copyCount)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        tasks = try c.decodeIfPresent([Task].self, forKey: .tasks)
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite)
        favoriteOrder = try c.decodeIfPresent(Int.self, forKey: .favoriteOrder)
        isVirtual = try c.decodeIfPresent(Bool.self, forKey: .isVirtual)
        virtualListType = try c.decodeIfPresent(String.self, forKey: .virtualListType)
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy)
        manualSortOrder = try c.decodeIfPresent([String].self, forKey: .manualSortOrder)
        showSubtasks = try c.decodeIfPresent(Bool.self, forKey: .showSubtasks)
        filterCompletion = try c.decodeIfPresent(String.self, forKey: .filterCompletion)
        filterDueDate = try c.decodeIfPresent(String.self, forKey: .filterDueDate)
        filterAssignee = try c.decodeIfPresent(String.self, forKey: .filterAssignee)
        filterAssignedBy = try c.decodeIfPresent(String.self, forKey: .filterAssignedBy)
        filterRepeating = try c.decodeIfPresent(String.self, forKey: .filterRepeating)
        filterPriority = try c.decodeIfPresent(String.self, forKey: .filterPriority)
        filterInLists = try c.decodeIfPresent(String.self, forKey: .filterInLists)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        listType = try c.decodeIfPresent(String.self, forKey: .listType)
        statusRole = try c.decodeIfPresent(String.self, forKey: .statusRole)
        statusOrder = try c.decodeIfPresent(Int.self, forKey: .statusOrder)
        statusDescription = try c.decodeIfPresent(String.self, forKey: .statusDescription)
        statusCompleted = try c.decodeIfPresent(Bool.self, forKey: .statusCompleted)
        recentlyCompletedWindow = try c.decodeIfPresent(RecentlyCompletedWindow.self, forKey: .recentlyCompletedWindow)
    }
}

/// `{ enabledTypes, defaultAgentId }` — the shape the server stores and, since 2026-08-29,
/// emits as `aiAgentConfig` beside the plain `aiAgentsEnabled` array.
struct ListAgentConfig: Codable, Equatable, Hashable {
    var enabledTypes: [String]
    var defaultAgentId: String?
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
