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

    // Filter settings for virtual lists
    var filterCompletion: String?
    var filterDueDate: String?
    var filterAssignee: String?
    var filterAssignedBy: String?
    var filterRepeating: String?
    var filterPriority: String?
    var filterInLists: String?
    
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
        case filterCompletion, filterDueDate, filterAssignee, filterAssignedBy
        case filterRepeating, filterPriority, filterInLists
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

extension TaskList {
    /// Check if the current user can access settings for this list
    /// Returns true if user is owner or admin, false otherwise
    func canUserSaveServerSettings() -> Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return false
        }

        // Check if user is owner
        if ownerId == currentUserId || owner?.id == currentUserId {
            return true
        }

        // Check if user is admin in legacy admins array
        if let admins = admins, admins.contains(where: { $0.id == currentUserId }) {
            return true
        }

        // Check in listMembers for admin role
        if let listMembers = listMembers {
            if listMembers.contains(where: { $0.user?.id == currentUserId && $0.role == "admin" }) {
                return true
            }
        }

        return false
    }

    /// Check if a user is a member of this list (owner, admin, or member)
    /// Used to determine if tasks in this list should be visible to the user
    func isMember(userId: String) -> Bool {
        // Check if user is owner
        if ownerId == userId || owner?.id == userId {
            return true
        }

        // Check if user is admin in legacy admins array
        if let admins = admins, admins.contains(where: { $0.id == userId }) {
            return true
        }

        // Check if user is member in legacy members array
        if let members = members, members.contains(where: { $0.id == userId }) {
            return true
        }

        // Check in listMembers for any role (admin, member)
        if let listMembers = listMembers {
            if listMembers.contains(where: { $0.userId == userId }) {
                return true
            }
        }

        return false
    }
}
