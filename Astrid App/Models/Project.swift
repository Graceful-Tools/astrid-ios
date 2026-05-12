import Foundation

/// A project (status board). Mirrors `Project` in `types/task.ts` and the
/// `V1Project` shape served by `/api/v1/projects` on the web.
///
/// A board exists when `projectId` is set on a `TaskList`. The project
/// holds shared metadata + members; its `lists` array contains both
/// regular (domain) lists and status lists (one per board column).
/// Inbox and Done remain virtual columns derived from task state and are
/// never stored. See `docs/product/project-status-board.md` (astrid-web).
public struct Project: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var description: String?
    public var color: String?
    public var imageUrl: String?
    public var ownerId: String?
    public var owner: User?
    public var members: [ProjectMember]?
    public var lists: [TaskList]?
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        color: String? = nil,
        imageUrl: String? = nil,
        ownerId: String? = nil,
        owner: User? = nil,
        members: [ProjectMember]? = nil,
        lists: [TaskList]? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.imageUrl = imageUrl
        self.ownerId = ownerId
        self.owner = owner
        self.members = members
        self.lists = lists
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayColor: String {
        color ?? "#3b82f6"
    }
}

public struct ProjectMember: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public let projectId: String?
    public let userId: String
    public let role: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var user: User?

    public init(
        id: String,
        projectId: String? = nil,
        userId: String,
        role: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        user: User? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.userId = userId
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.user = user
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.role = try container.decode(String.self, forKey: .role)
        self.projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        self.user = try container.decodeIfPresent(User.self, forKey: .user)
        // Embedded responses may omit `id`; fall back to userId so the
        // struct stays Identifiable.
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? userId
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectId, userId, role, createdAt, updatedAt, user
    }
}
